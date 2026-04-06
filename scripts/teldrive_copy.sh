#!/bin/bash
#!/bin/bash
set -Eeuo pipefail
umask 022  # 로그/상태파일 읽기 권한 확보

# 부팅 직후 또는 간헐적 네트워크 끊김 대비 마운트 강제 재시도
mount -a || true
sleep 2

STATUS_DIR="/var/www/rclone-status"
STATUS_FILE="$STATUS_DIR/status.json"
mkdir -p "$STATUS_DIR"

ts() { date -Is; }  # 2025-10-20T16:03:00+09:00 형태

overall="success"
details=()

# 상태 저장 함수
write_status() {
  printf '{\n  "last_run":"%s",\n  "overall":"%s",\n  "details":[%s]\n}\n' \
    "$(ts)" "$overall" "$(IFS=,; echo "${details[*]}")" > "$STATUS_FILE"
  chown www-data:www-data "$STATUS_FILE" 2>/dev/null || true
}

run_copy () {
  local name="$1"; shift
  local logfile="$2"; shift
  local cmd=("$@")

  echo "[$(ts)] START $name" >> "$logfile"
  write_status

  if "${cmd[@]}" >> "$logfile" 2>&1; then
    details+=("{\"task\":\"$name\",\"status\":\"success\",\"log\":\"$logfile\"}")
    echo "[$(ts)] DONE  $name (OK)" >> "$logfile"
  else
    details+=("{\"task\":\"$name\",\"status\":\"error\",\"log\":\"$logfile\"}")
    overall="error"
    echo "[$(ts)] FAIL  $name (ERR)" >> "$logfile"
  fi
  write_status
}

# 초기 파일 생성
write_status

run_copy "photos" "/var/log/rclone_photos.log" \
  /usr/local/bin/rclone copy /mnt/nas/woooook/Photos teldrive:/photos \
    --create-empty-src-dirs \
    --exclude '@*/**' \
    --ignore-existing \
    --transfers 1 --checkers 2 --tpslimit 3 \
    --log-file=/var/log/rclone_photos.log \
    --log-level=INFO \
    --rc --rc-no-auth --rc-addr localhost:5572

run_copy "HA_backups" "/var/log/rclone_HA_backups.log" \
  /usr/local/bin/rclone copy "/mnt/backups/HA backups" "teldrive:/HA backups" \
    --create-empty-src-dirs \
    --exclude '@*/**' \
    --ignore-existing \
    --transfers 1 --checkers 2 --tpslimit 3 \
    --log-file=/var/log/rclone_HA_backups.log \
    --log-level=INFO \
    --rc --rc-no-auth --rc-addr localhost:5572

run_copy "surveillance" "/var/log/surveillance.log" \
  /usr/local/bin/rclone copy "/mnt/surveillance" "teldrive:/surveillance" \
    --create-empty-src-dirs \
    --exclude '@*/**' \
    --ignore-existing \
    --transfers 1 --checkers 2 --tpslimit 3 \
    --log-file=/var/log/surveillance.log \
    --log-level=INFO \
    --rc --rc-no-auth --rc-addr localhost:5572

tail -n 100 /var/log/rclone_photos.log      > "$STATUS_DIR/photos.tail"
tail -n 100 /var/log/rclone_HA_backups.log  > "$STATUS_DIR/ha_backups.tail"
tail -n 100 /var/log/surveillance.log       > "$STATUS_DIR/surveillance.tail"

