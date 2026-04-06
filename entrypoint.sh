#!/bin/bash
set -e

echo "Starting Teldrive Relay Entrypoint..."

# 1. Generate rclone.conf from environment variables
RCLONE_CONF="/root/.config/rclone/rclone.conf"
mkdir -p /root/.config/rclone

if [ -n "$TELDRIVE_ACCESS_TOKEN" ] && [ -n "$TELDRIVE_API_HOST" ]; then
    echo "Configuring rclone for Teldrive..."
    cat <<EOF > "$RCLONE_CONF"
[teldrive]
type = teldrive
access_token = $TELDRIVE_ACCESS_TOKEN
api_host = $TELDRIVE_API_HOST
encrypt_files = ${TELDRIVE_ENCRYPT_FILES:-true}
root_folder_id = ${TELDRIVE_ROOT_FOLDER_ID:-}
EOF
else
    echo "WARNING: TELDRIVE_ACCESS_TOKEN or TELDRIVE_API_HOST is missing."
    echo "rclone will not work until configured."
fi

# 2. Setup Cron Schedule
CRON_FILE="/etc/cron.d/rclone-daily"
# Use provided CRON_SCHEDULE or default to "0 3 * * *"
SCHEDULE="${CRON_SCHEDULE:-0 3 * * *}"

echo "Setting up cron schedule: $SCHEDULE"
echo "$SCHEDULE root /app/scripts/rclone_daily.sh >> /app/status/cron.log 2>&1" > "$CRON_FILE"
chmod 0644 "$CRON_FILE"
crontab "$CRON_FILE"

# 3. Create dummy log files if they don't exist so webapp doesn't complain
touch /app/status/rclone_photos.log
touch /app/status/rclone_HA_backups.log
touch /app/status/surveillance.log
touch /app/status/cron.log

# 4. Start Supervisord to manage Cron and Flask
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
