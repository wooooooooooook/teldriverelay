#!/bin/bash
set -Eeuo pipefail
umask 022

# === 설정 ===
RCLONE="/usr/bin/rclone"
STATUS_DIR="/var/www/rclone-status"
STATUS_FILE="$STATUS_DIR/status.json"
mkdir -p "$STATUS_DIR"

ts() { date -Is; }

# 초기 status.json 구조 생성 함수 (파일이 없거나 유효하지 않을 때)
init_status() {
  if [ ! -f "$STATUS_FILE" ] || ! jq . "$STATUS_FILE" >/dev/null 2>&1; then
    echo "{\"last_run\":\"$(ts)\",\"overall\":\"success\",\"details\":[],\"mounts\":[]}" > "$STATUS_FILE"
    chown www-data:www-data "$STATUS_FILE"
  fi
}

# 개별 작업 상태 업데이트 함수 (jq 사용)
update_task_status() {
  local name="$1"
  local status="$2"
  local logfile="$3"
  
  init_status
  
  # 기존 항목이 있으면 업데이트, 없으면 추가
  local tmp_file
  tmp_file=$(mktemp)
  jq --arg name "$name" --arg status "$status" --arg log "$logfile" --arg ts "$(ts)" \
    '(.details[] | select(.task == $name) | .status) = $status | 
     (.details[] | select(.task == $name) | .log) = $log |
     if (.details | any(.task == $name)) then . else .details += [{"task":$name, "status":$status, "log":$log}] end |
     .last_run = $ts |
     # 전체 상태 계산 (하나라도 error면 error, running이 있으면 running, 모두 success면 success)
     .overall = (if (.details | any(.status == "error")) then "error" 
                 elif (.details | any(.status == "running")) then "running" 
                 else "success" end)' \
    "$STATUS_FILE" > "$tmp_file" && mv "$tmp_file" "$STATUS_FILE"
  
  chown www-data:www-data "$STATUS_FILE"
}

# 마운트 상태 갱신 함수
update_mounts() {
  local paths=("$@")
  local mounts_json="[]"
  
  for p in "${paths[@]}"; do
    local exists="false" mounted="false" source="" fstype="" opts=""
    if [[ -d "$p" ]]; then
      exists="true"
      if findmnt -no SOURCE --target "$p" >/dev/null 2>&1; then
        mounted="true"
        source="$(findmnt -no SOURCE --target "$p" 2>/dev/null || echo "")"
        fstype="$(findmnt -no FSTYPE --target "$p" 2>/dev/null || echo "")"
        opts="$(findmnt -no OPTIONS --target "$p" 2>/dev/null || echo "")"
      fi
    fi
    local item
    item=$(jq -n --arg p "$p" --arg e "$exists" --arg m "$mounted" --arg s "$source" --arg f "$fstype" --arg o "$opts" \
      '{path:$p, exists:($e=="true"), mounted:($m=="true"), source:$s, fstype:$f, opts:$o}')
    mounts_json=$(echo "$mounts_json" | jq --argjson item "$item" '. += [$item]')
  done
  
  init_status
  local tmp_file
  tmp_file=$(mktemp)
  jq --argjson mounts "$mounts_json" '.mounts = $mounts' "$STATUS_FILE" > "$tmp_file" && mv "$tmp_file" "$STATUS_FILE"
  chown www-data:www-data "$STATUS_FILE"
}

run_copy () {
  local name="$1"; shift
  local logfile="$1"; shift
  
  # 중복 실행 방지 (작업별 Lock)
  local task_lock="/tmp/rclone_task_${name}.lock"
  if [ -f "$task_lock" ]; then
    local pid
    pid=$(cat "$task_lock")
    if kill -0 "$pid" 2>/dev/null; then
      echo "[$(ts)] Task $name already running (PID $pid). Skipping."
      return 1
    fi
  fi
  echo $$ > "$task_lock"
  trap 'rm -f "$task_lock"' RETURN

  # RC 포트 체크 및 정리 (동시 실행 시 포트 충돌 방지를 위해 루프)
  # 참고: 여러 작업 동시 실행 시 rc 포트를 다르게 주거나 rc를 비활성화해야 할 수도 있음.
  # 여기서는 포트 점유 중이면 정리를 시도함.
  pkill -9 -f "rc-addr localhost:5572" 2>/dev/null || true
  sleep 1

  echo "[$(ts)] START $name" >> "$logfile" 2>&1 || true
  update_task_status "$name" "running" "$logfile"

  if "$@" >> "$logfile" 2>&1; then
    update_task_status "$name" "success" "$logfile"
    echo "[$(ts)] DONE  $name (OK)" >> "$logfile" 2>&1 || true
  else
    update_task_status "$name" "error" "$logfile"
    echo "[$(ts)] FAIL  $name (ERR)" >> "$logfile" 2>&1 || true
  fi
  
  # 로그 tail 추출
  tail -n 100 "$logfile" > "$STATUS_DIR/${name}.tail" 2>/dev/null || true
}

# === 환경 정의 ===
SRC_PHOTOS="/mnt/nas/woooook/Photos"
SRC_HA="/mnt/backups/HA backups"
SRC_SURV="/mnt/surveillance"

TASK_LIST=("photos" "HA_backups" "surveillance")

# 마운트 상태 갱신
update_mounts "$SRC_PHOTOS" "$SRC_HA" "$SRC_SURV"

# 명령행 인자가 있으면 해당 작업만 실행
if [ $# -gt 0 ]; then
  case "$1" in
    _update_status)
      # 내부용: _update_status <name> <status> <logfile>
      update_task_status "$2" "$3" "$4"
      exit 0
      ;;
    photos)
        "$RCLONE" copy "$SRC_PHOTOS" teldrive:/photos \
          --create-empty-src-dirs --exclude '@*/**' --ignore-existing \
          --contimeout 10s --timeout 1m --retries 3 --retries-sleep 10s \
          --transfers 1 --checkers 2 --tpslimit 3 \
          --log-file=/var/log/rclone_photos.log --log-level=INFO \
          --rc --rc-no-auth --rc-addr localhost:5572
      ;;
    HA_backups)
        "$RCLONE" copy "$SRC_HA" "teldrive:/HA backups" \
          --create-empty-src-dirs --exclude '@*/**' --ignore-existing \
          --contimeout 10s --timeout 1m --retries 3 --retries-sleep 10s \
          --transfers 1 --checkers 2 --tpslimit 3 \
          --log-file=/var/log/rclone_HA_backups.log --log-level=INFO \
          --rc --rc-no-auth --rc-addr localhost:5572
      ;;
    surveillance)
        "$RCLONE" copy "$SRC_SURV" "teldrive:/surveillance" \
          --create-empty-src-dirs --exclude '@*/**' --ignore-existing \
          --contimeout 10s --timeout 1m --retries 3 --retries-sleep 10s \
          --transfers 1 --checkers 2 --tpslimit 3 \
          --log-file=/var/log/surveillance.log --log-level=INFO \
          --rc --rc-no-auth --rc-addr localhost:5572
      ;;
    *)
      echo "Unknown task: $1"
      exit 1
      ;;
  esac
else
  # 인자 없으면 순차적으로 모두 실행 (기존 크론용)
  for t in "${TASK_LIST[@]}"; do
    $0 "$t"
    sleep 2
  done
fi
