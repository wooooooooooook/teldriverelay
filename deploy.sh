#!/bin/bash
# deploy.sh — CT104에 파일 동기화 + 서비스 재시작
# 로컬 workspace에서 실행 (본인이 git pull 먼저 수행)
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="root@192.168.0.99"
CT=104

echo "[$(date -Is)] Deploy started"

# 1. git pull (repo 내에서 실행)
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "[1/4] git pull..."
  git -C "$REPO_DIR" pull origin main 2>&1 | tail -3
fi

# 2. rclone_daily.sh 갱신 + 백업
echo "[2/4] Deploy rclone_daily.sh..."
ssh "$HOST" "pct exec $CT -- cp /usr/local/bin/rclone_daily.sh /usr/local/bin/rclone_daily.sh.bak.\$(date +%s)"
scp "$REPO_DIR/scripts/rclone_daily.sh" "$HOST:/tmp/rclone_daily.sh"
ssh "$HOST" "pct push $CT /tmp/rclone_daily.sh /usr/local/bin/rclone_daily.sh"
ssh "$HOST" "pct exec $CT -- chmod +x /usr/local/bin/rclone_daily.sh"

echo "[3/4] Deploy config.json..."
scp "$REPO_DIR/config/config.json" "$HOST:/tmp/config.json"
ssh "$HOST" "pct push $CT /tmp/config.json /var/www/rclone-status/config.json"
ssh "$HOST" "pct exec $CT -- chown www-data:www-data /var/www/rclone-status/config.json"

# 4. systemd reload
echo "[4/4] Reload services..."
ssh "$HOST" "pct exec $CT -- systemctl daemon-reload"
ssh "$HOST" "pct exec $CT -- systemctl restart rclone-status"

echo "[$(date -Is)] Deploy done — check: ssh root@192.168.0.99 \"pct exec 104 -- systemctl status rclone-status | head -5\""