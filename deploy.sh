#!/bin/bash
# deploy.sh — CT104에 파일 동기화 + 서비스 재시작
# 로컬 workspace에서 실행 (git pull은 이 스크립트가 직접 수행)
# config/config.json은 git 추적 대상이 아니므로(gitignore) 이 작업 트리에 있는
# 로컬 파일을 그대로 CT104 라이브 설정으로 복사한다. 없으면 설정 배포는 건너뛴다.
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="root@192.168.0.99"
CT=104
CONFIG_FILE="$REPO_DIR/config/config.json"
LIVE_CONFIG="/var/www/rclone-status/config.json"

echo "[$(date -Is)] Deploy started"

# 1. git pull (repo 내에서 실행)
#    config.json은 untracked 로컬 파일이라 pull로 지워지지 않지만,
#    예전 커밋이 추적하던 클론에서 pull하면 삭제될 수 있어 백업/복원한다.
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "[1/4] git pull..."
  config_backup=""
  if [[ -f "$CONFIG_FILE" ]]; then
    config_backup="$(mktemp)"
    cp -p "$CONFIG_FILE" "$config_backup"
  fi
  git -C "$REPO_DIR" pull origin main 2>&1 | tail -3
  if [[ -n "$config_backup" ]]; then
    if [[ ! -f "$CONFIG_FILE" ]]; then
      cp -p "$config_backup" "$CONFIG_FILE"
      echo "  (pull로 사라진 로컬 config/config.json 복원)"
    fi
    rm -f "$config_backup"
  fi
fi

# 2. rclone_daily.sh 갱신 + 백업
echo "[2/4] Deploy rclone_daily.sh..."
ssh "$HOST" "pct exec $CT -- cp /usr/local/bin/rclone_daily.sh /usr/local/bin/rclone_daily.sh.bak.\$(date +%s)"
scp "$REPO_DIR/scripts/rclone_daily.sh" "$HOST:/tmp/rclone_daily.sh"
ssh "$HOST" "pct push $CT /tmp/rclone_daily.sh /usr/local/bin/rclone_daily.sh"
ssh "$HOST" "pct exec $CT -- chmod +x /usr/local/bin/rclone_daily.sh"

# 3. config.json 배포 (로컬 파일이 있을 때만)
if [[ -f "$CONFIG_FILE" ]]; then
  echo "[3/4] Deploy config.json..."
  # 라이브 설정을 타임스탬프 백업한 뒤 교체
  ssh "$HOST" "pct exec $CT -- cp $LIVE_CONFIG $LIVE_CONFIG.bak.\$(date +%s) 2>/dev/null || true"
  scp "$CONFIG_FILE" "$HOST:/tmp/config.json"
  ssh "$HOST" "pct push $CT /tmp/config.json $LIVE_CONFIG"
  ssh "$HOST" "pct exec $CT -- chown www-data:www-data $LIVE_CONFIG"
else
  echo "[3/4] Skip config.json — $CONFIG_FILE 없음 (config/config.example.json 참고). CT104 라이브 설정은 그대로 둡니다."
fi

# 4. systemd reload
echo "[4/4] Reload services..."
ssh "$HOST" "pct exec $CT -- systemctl daemon-reload"
ssh "$HOST" "pct exec $CT -- systemctl restart rclone-status"

echo "[$(date -Is)] Deploy done — check: ssh root@192.168.0.99 \"pct exec 104 -- systemctl status rclone-status | head -5\""
