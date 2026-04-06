#!/usr/bin/env bash
set -Eeuo pipefail

### ====== 사용자 변경 가능 영역 ======
WEB_PORT="${WEB_PORT:-8080}"          # Flask 서비스 포트
CRON_HOUR="${CRON_HOUR:-3}"           # 매일 시(hour)
CRON_MINUTE="${CRON_MINUTE:-0}"       # 매일 분(minute)
STATUS_DIR="/var/www/rclone-status"   # 상태/테일 로그 저장 위치
APP_DIR="/opt/rclone-status"          # Flask 앱 설치 위치
PY="/usr/bin/python3"                 # 파이썬 실행 파일
### ==================================

echo "[1/8] 패키지 설치"
apt-get update -y
apt-get install -y python3-venv python3-virtualenv curl ca-certificates logrotate

echo "[2/8] 디렉터리 생성 및 권한"
mkdir -p "$STATUS_DIR"
mkdir -p "$APP_DIR"
chown -R www-data:www-data "$STATUS_DIR"
chmod -R 755 "$STATUS_DIR"

echo "[3/8] rclone 백업 스크립트 생성: /usr/local/bin/rclone_daily.sh"
cat > /usr/local/bin/rclone_daily.sh <<'EOF'
#!/bin/bash
set -Eeuo pipefail
umask 022

STATUS_DIR="/var/www/rclone-status"
STATUS_FILE="$STATUS_DIR/status.json"
mkdir -p "$STATUS_DIR"

ts() { date -Is; }

overall="success"
details=()

run_copy () {
  local name="$1"; shift
  local logfile="$2"; shift
  local cmd=("$@")

  echo "[$(ts)] START $name" >> "$logfile"
  if "${cmd[@]}" >> "$logfile" 2>&1; then
    details+=("{\"task\":\"$name\",\"status\":\"success\",\"log\":\"$logfile\"}")
    echo "[$(ts)] DONE  $name (OK)" >> "$logfile"
  else
    details+=("{\"task\":\"$name\",\"status\":\"error\",\"log\":\"$logfile\"}")
    overall="error"
    echo "[$(ts)] FAIL  $name (ERR)" >> "$logfile"
  fi
}

# === 작업 1: Photos
run_copy "photos" "/var/log/rclone_photos.log" \
  /usr/local/bin/rclone copy /mnt/nas/woooook/Photos teldrive:/photos \
    --create-empty-src-dirs \
    --exclude '@*/**' \
    --ignore-existing \
    --log-file=/var/log/rclone_photos.log \
    --log-level=INFO

# === 작업 2: HA backups
run_copy "HA_backups" "/var/log/rclone_HA_backups.log" \
  /usr/local/bin/rclone copy "/mnt/backups/HA backups" "teldrive:/HA backups" \
    --create-empty-src-dirs \
    --exclude '@*/**' \
    --ignore-existing \
    --log-file=/var/log/rclone_HA_backups.log \
    --log-level=INFO

# === 작업 3: surveillance
run_copy "surveillance" "/var/log/surveillance.log" \
  /usr/local/bin/rclone copy "/mnt/surveillance" "teldrive:/surveillance" \
    --create-empty-src-dirs \
    --exclude '@*/**' \
    --ignore-existing \
    --log-file=/var/log/surveillance.log \
    --log-level=INFO

# 상태 JSON 기록
printf '{\n  "last_run":"%s",\n  "overall":"%s",\n  "details":[%s]\n}\n' \
  "$(ts)" "$overall" "$(IFS=,; echo "${details[*]}")" > "$STATUS_FILE"

# 최근 로그 tail 저장
tail -n 100 /var/log/rclone_photos.log      > "$STATUS_DIR/photos.tail" || true
tail -n 100 /var/log/rclone_HA_backups.log  > "$STATUS_DIR/ha_backups.tail" || true
tail -n 100 /var/log/surveillance.log       > "$STATUS_DIR/surveillance.tail" || true

# 권한 정리(웹앱이 읽을 수 있도록)
chown -R www-data:www-data "$STATUS_DIR"
chmod 644 /var/log/rclone_photos.log /var/log/rclone_HA_backups.log /var/log/surveillance.log 2>/dev/null || true
EOF
chmod +x /usr/local/bin/rclone_daily.sh

echo "[4/8] Flask 앱 설치"
cd "$APP_DIR"
if [[ ! -d venv ]]; then
  "$PY" -m venv venv
fi
"$APP_DIR/venv/bin/pip" install --upgrade pip >/dev/null
"$APP_DIR/venv/bin/pip" install flask >/dev/null

cat > "$APP_DIR/app.py" <<EOF
from flask import Flask, send_from_directory, render_template_string
import json, os, datetime

app = Flask(__name__)

STATUS_DIR = "$STATUS_DIR"
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")

TEMPLATE = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>rclone 백업 상태</title>
  <meta http-equiv="refresh" content="60">
  <style>
    body { font-family: system-ui, sans-serif; margin: 24px; }
    .ok { color: #0a0; font-weight: 700; }
    .err { color: #c00; font-weight: 700; }
    .warn { color: #a60; font-weight: 700; }
    code, pre { background:#f5f5f5; padding:8px; border-radius:6px; overflow:auto; }
    table { border-collapse: collapse; width: 100%; margin-top: 12px; }
    th, td { border-bottom: 1px solid #ddd; padding: 8px; text-align: left; }
    .badge { display:inline-block; padding:2px 8px; border-radius:10px; font-size:12px; }
    .badge-ok { background:#e6ffe6; color:#0a0; }
    .badge-err { background:#ffe6e6; color:#c00; }
    .badge-warn{ background:#fff4e6; color:#a60; }
  </style>
</head>
<body>
  <h1>rclone 백업 상태</h1>
  {% if data %}
    <p>마지막 실행: <strong>{{ data.last_run }}</strong>
      {% if stale %}
        <span class="badge badge-warn">오래됨({{ hours }}h)</span>
      {% endif %}
    </p>
    <p>전체 상태:
      {% if data.overall == 'success' %}
        <span class="badge badge-ok">success</span>
      {% else %}
        <span class="badge badge-err">error</span>
      {% endif %}
    </p>

    <table>
      <thead><tr><th>작업</th><th>상태</th><th>로그</th></tr></thead>
      <tbody>
        {% for d in data.details %}
          <tr>
            <td>{{ d.task }}</td>
            <td>
              {% if d.status == 'success' %}
                <span class="badge badge-ok">success</span>
              {% else %}
                <span class="badge badge-err">error</span>
              {% endif %}
            </td>
            <td><code>{{ d.log }}</code></td>
          </tr>
        {% endfor %}
      </tbody>
    </table>

    <h2>최근 로그 (각 100줄)</h2>
    <h3>Photos</h3>
    <pre>{{ tails.photos }}</pre>
    <h3>HA backups</h3>
    <pre>{{ tails.ha }}</pre>
    <h3>Surveillance</h3>
    <pre>{{ tails.surv }}</pre>

  {% else %}
    <p class="warn">상태 파일을 찾을 수 없습니다: <code>{{ status_file }}</code><br>
    크론이 아직 실행되지 않았거나 권한 문제일 수 있습니다.</p>
  {% endif %}
</body>
</html>
"""

def _read(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()
    except:
        return "(읽기 실패)"

@app.route("/")
def index():
    data = None
    stale = False
    hours = None

    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            last = data.get("last_run")
            dt = None
            try:
                dt = datetime.datetime.fromisoformat(last) if last else None
            except Exception:
                dt = None
            if dt:
                now = datetime.datetime.now(dt.tzinfo) if dt.tzinfo else datetime.datetime.now()
                diff = now - dt
                hours = int(diff.total_seconds() // 3600)
                stale = diff.total_seconds() > 26*3600
        except Exception:
            data = None

    tails = {
        "photos": _read(os.path.join(STATUS_DIR, "photos.tail")),
        "ha":     _read(os.path.join(STATUS_DIR, "ha_backups.tail")),
        "surv":   _read(os.path.join(STATUS_DIR, "surveillance.tail")),
    }

    return render_template_string(TEMPLATE,
                                  data=data, tails=tails,
                                  status_file=STATUS_FILE,
                                  stale=stale, hours=hours)

@app.route("/status.json")
def status_json():
    return send_from_directory(STATUS_DIR, "status.json")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=$WEB_PORT)
EOF

chown -R www-data:www-data "$APP_DIR"
chmod -R 755 "$APP_DIR"
find "$APP_DIR" -type f -name "*.py" -exec chmod 644 {} \;

echo "[5/8] systemd 서비스 등록 (웹)"
cat > /etc/systemd/system/rclone-status.service <<EOF
[Unit]
Description=rclone status web (Flask)
After=network-online.target
Wants=network-online.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/app.py
Restart=always
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now rclone-status.service

echo "[6/8] 크론 잡 생성 (매일 ${CRON_HOUR}:${CRON_MINUTE})"
/bin/sh -c "cat > /etc/cron.d/rclone-daily <<CRON
# rclone daily backup
${CRON_MINUTE} ${CRON_HOUR} * * * root /usr/local/bin/rclone_daily.sh
CRON"
chmod 644 /etc/cron.d/rclone-daily

echo "[7/8] logrotate 설정"
cat > /etc/logrotate.d/rclone-status <<'EOF'
/var/log/rclone_photos.log
/var/log/rclone_HA_backups.log
/var/log/surveillance.log {
    rotate 7
    daily
    missingok
    notifempty
    compress
    delaycompress
    create 0644 root root
    sharedscripts
    postrotate
        # nothing
    endscript
}
EOF

echo "[8/8] 1회 수동 실행 테스트 (선택적): /usr/local/bin/rclone_daily.sh"
echo "설치 완료!"
echo
echo "▶ 상태 페이지:  http://<LXC_IP>:$WEB_PORT"
echo "   (LXC에서: ip a 로 IP 확인)"
echo
echo "자주 쓰는 점검 명령:"
echo "  systemctl status rclone-status.service   # 웹 서비스 상태"
echo "  journalctl -u rclone-status -e          # 웹 서비스 로그"
echo "  tail -f /var/log/rclone_photos.log      # rclone 로그"
echo "  tail -f /var/log/rclone_HA_backups.log"
echo "  tail -f /var/log/surveillance.log"
