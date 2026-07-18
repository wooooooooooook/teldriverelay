#!/bin/bash
# deploy.sh — git pull → CT104에 파일 동기화 후 서비스 재시작
# Usage: ./deploy.sh
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="root@192.168.0.99"
CT=104

echo "[$(date -Is)] Deploy started"

# 1. git pull (repo 내에서 실행)
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "[1/4] git pull..."
  git -C "$REPO_DIR" pull origin main || git -C "$REPO_DIR" pull origin master
fi

# 2. rclone_daily.sh 갱신
echo "[2/4] Deploy rclone_daily.sh..."
rsync -az --delete \
  "$REPO_DIR/scripts/rclone_daily.sh" \
  "$HOST:/usr/local/bin/rclone_daily.sh"
# 백업
ssh "$HOST" "pct exec $CT -- cp /usr/local/bin/rclone_daily.sh /usr/local/bin/rclone_daily.sh.bak.\$(date +%s)"

# 3. config.json 갱신
echo "[3/4] Deploy config.json..."
rsync -az --delete \
  "$REPO_DIR/config/config.json" \
  "$HOST:/var/www/rclone-status/config.json"
ssh "$HOST" "pct exec $CT -- chown www-data:www-data /var/www/rclone-status/config.json"

# 4. systemd service / cron 갱신 (변경 시에만)
echo "[4/4] Reload systemd & cron..."
ssh "$HOST" "pct exec $CT -- systemctl daemon-reload"
ssh "$HOST" "pct exec $CT -- systemctl restart rclone-status"

echo "[$(date -Is)] Deploy done"