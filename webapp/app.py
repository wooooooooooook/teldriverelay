from flask import Flask, send_from_directory, render_template_string, jsonify, request
import json, os, datetime, requests, subprocess, signal

app = Flask(__name__)

STATUS_DIR = "/var/www/rclone-status"
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
RC_URL = "http://localhost:5572/core/stats"

TEMPLATE = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>rclone 관리 모니터</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    :root {
      --primary: #4361ee;
      --success: #2ec4b6;
      --danger: #e71d36;
      --warning: #ff9f1c;
      --info: #3a86ff;
      --dark: #011627;
      --light: #fdfffc;
      --gray: #8d99ae;
    }
    body { font-family: 'Inter', system-ui, -apple-system, sans-serif; margin: 0; background: #f0f2f5; color: var(--dark); line-height: 1.6; }
    .container { max-width: 1100px; margin: 40px auto; background: white; padding: 40px; border-radius: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.05); }
    
    header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #f0f2f5; margin-bottom: 30px; padding-bottom: 20px; }
    h1 { margin: 0; font-size: 28px; font-weight: 800; background: linear-gradient(45deg, var(--primary), var(--info)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    
    .btn { cursor: pointer; border: none; padding: 8px 16px; border-radius: 8px; font-size: 13px; font-weight: 600; transition: all 0.2s; display: inline-flex; align-items: center; gap: 6px; text-decoration: none; }
    .btn-primary { background: var(--primary); color: white; }
    .btn-primary:hover { background: #3046bc; transform: translateY(-1px); }
    .btn-danger { background: rgba(231, 29, 54, 0.1); color: var(--danger); }
    .btn-danger:hover { background: var(--danger); color: white; transform: translateY(-1px); }
    .btn-outline { border: 1.5px solid #e0e0e0; background: transparent; color: var(--gray); }
    .btn-outline:hover { border-color: var(--primary); color: var(--primary); }
    .btn:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }

    .stats-card { background: #f8fbff; padding: 24px; border-radius: 12px; margin-bottom: 30px; display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 20px; border: 1px solid #e1e9f5; }
    .stat-item { display: flex; flex-direction: column; }
    .stat-label { font-size: 11px; color: var(--gray); text-transform: uppercase; letter-spacing: 1px; margin-bottom: 6px; font-weight: 700; }
    .stat-value { font-size: 20px; font-weight: 800; color: var(--dark); }
    
    .progress-wrapper { background: #edf2f7; border-radius: 20px; height: 12px; margin: 15px 0; overflow: hidden; position: relative; }
    .progress-inner { height: 100%; background: linear-gradient(90deg, var(--primary), var(--info)); transition: width 0.8s cubic-bezier(0.4, 0, 0.2, 1); border-radius: 20px; }
    
    .active-transfers { margin-top: 25px; background: #fff; border-radius: 12px; }
    .transfer-item { font-size: 13px; padding: 12px 16px; background: #f8f9fa; margin-bottom: 10px; border-radius: 10px; border-left: 4px solid var(--info); }
    .transfer-name { font-weight: 700; display: block; margin-bottom: 6px; color: var(--dark); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .transfer-meta { color: var(--gray); font-size: 12px; font-weight: 500; }

    table { width: 100%; border-collapse: separate; border-spacing: 0; margin: 20px 0; border-radius: 12px; overflow: hidden; border: 1px solid #f0f2f5; }
    th { background: #fcfdfe; padding: 16px; font-size: 12px; text-transform: uppercase; letter-spacing: 1px; color: var(--gray); font-weight: 700; text-align: left; border-bottom: 1px solid #f0f2f5; }
    td { padding: 16px; border-bottom: 1px solid #f0f2f5; font-size: 14px; vertical-align: middle; }
    tr:last-child td { border-bottom: none; }
    
    .badge { display: inline-flex; align-items: center; padding: 4px 12px; border-radius: 20px; font-size: 11px; font-weight: 700; text-transform: uppercase; }
    .badge-ok { background: #e6fcf5; color: #0ca678; }
    .badge-err { background: #fff5f5; color: #f03e3e; }
    .badge-info { background: #e7f5ff; color: #1971c2; }
    .badge-running { background: #e7f5ff; color: #1971c2; position: relative; overflow: hidden; }
    .badge-running::after { content: ""; position: absolute; left: -100%; width: 100%; height: 100%; background: linear-gradient(90deg, transparent, rgba(255,255,255,0.6), transparent); animation: sweep 1.5s infinite; }
    @keyframes sweep { 100% { left: 100%; } }

    .actions { display: flex; gap: 8px; }
    
    pre { background: #1a1c23; color: #e1e1e1; padding: 20px; border-radius: 12px; overflow: auto; font-size: 12px; line-height: 1.6; border: 1px solid #2d2f39; margin-top: 10px; }
    h2, h3 { color: var(--dark); margin-top: 40px; margin-bottom: 15px; font-weight: 800; border-left: 4px solid var(--primary); padding-left: 15px; }
    hr { border: 0; height: 1px; background: #eee; margin: 40px 0; }
    
    .toast { position: fixed; bottom: 20px; right: 20px; padding: 16px 24px; border-radius: 10px; background: var(--dark); color: white; display: none; z-index: 1000; box-shadow: 0 10px 30px rgba(0,0,0,0.2); animation: fadeInUp 0.4s; }
    @keyframes fadeInUp { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>rclone 관리 모니터</h1>
      <button class="btn btn-primary" onclick="controlTask('all', 'start')">전체 작업 실행</button>
    </header>
    
    {% if rc_stats and (rc_stats.speed > 0 or rc_stats.transferring) %}
      <div class="stats-card">
        <div class="stat-item">
          <span class="stat-label">현재 상태</span>
          <span class="stat-value" style="color:var(--primary)">파일 전송 중</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">평균 속도</span>
          <span class="stat-value">{{ rc_stats.speed | format_bytes }}/s</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">전체 진행률</span>
          <span class="stat-value">{{ rc_stats.percentage }}%</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">남은 시간</span>
          <span class="stat-value">{{ rc_stats.eta | format_seconds }}</span>
        </div>
      </div>

      <div class="progress-wrapper">
        <div class="progress-inner" style="width: {{ rc_stats.percentage }}%"></div>
      </div>
      
      {% if rc_stats.transferring %}
        <div class="active-transfers">
          {% for t in rc_stats.transferring %}
            <div class="transfer-item">
              <span class="transfer-name">{{ t.name }}</span>
              <div class="progress-wrapper" style="height: 4px; margin: 8px 0;">
                <div class="progress-inner" style="width: {{ t.percentage }}%"></div>
              </div>
              <span class="transfer-meta">{{ t.percentage }}% | {{ t.bytes | format_bytes }} / {{ t.size | format_bytes }} | {{ t.speed | format_bytes }}/s</span>
            </div>
          {% endfor %}
        </div>
      {% endif %}
    {% else %}
      <div class="stats-card">
        <div class="stat-item">
          <span class="stat-label">시스템 상태</span>
          {% set is_any_running = false %}
          {% if data and data.details %}
            {% for d in data.details %}{% if d.status == 'running' %}{% set is_any_running = true %}{% endif %}{% endfor %}
          {% endif %}
          
          {% if is_any_running %}
            <span class="stat-value" style="color:var(--info)">백업 스크립트 실행 중...</span>
          {% else %}
            <span class="stat-value" style="color:var(--gray)">대기 중 (Idle)</span>
          {% endif %}
        </div>
      </div>
    {% endif %}

    <section>
      <h2>백업 작업 리스트</h2>
      <table>
        <thead><tr><th>작업명</th><th>상태</th><th>실행 제어</th><th>로그</th></tr></thead>
        <tbody>
          {% if data and data.details %}
            {% for d in data.details %}
              <tr>
                <td style="font-weight:700">{{ d.task }}</td>
                <td>
                  {% if d.status == 'success' %}
                    <span class="badge badge-ok">SUCCESS</span>
                  {% elif d.status == 'running' %}
                    <span class="badge badge-running">RUNNING</span>
                  {% else %}
                    <span class="badge badge-err">ERROR</span>
                  {% endif %}
                </td>
                <td class="actions">
                  <button class="btn btn-outline" onclick="controlTask('{{ d.task }}', 'start')" {% if d.status == 'running' %}disabled{% endif %}>
                    시작
                  </button>
                  <button class="btn btn-danger" onclick="controlTask('{{ d.task }}', 'stop')" {% if d.status != 'running' %}disabled{% endif %}>
                    중지
                  </button>
                </td>
                <td><code style="font-size:11px; color:var(--gray)">{{ d.log }}</code></td>
              </tr>
            {% endfor %}
          {% else %}
            <tr><td colspan="4" style="text-align:center; color:var(--gray)">기록된 작업이 없습니다.</td></tr>
          {% endif %}
        </tbody>
      </table>
    </section>

    {% if live_mounts %}
      <section>
        <h2>네트워크 마운트 상태</h2>
        <table>
          <thead><tr><th>마운트 경로</th><th>상태</th><th>소스 장치</th><th>파일시스템</th></tr></thead>
          <tbody>
            {% for m in live_mounts %}
              <tr>
                <td><code>{{ m.path }}</code></td>
                <td>
                  {% if m.mounted %}
                    <span class="badge badge-ok">MOUNTED</span>
                  {% else %}
                    <span class="badge badge-err">DISCONNECTED</span>
                  {% endif %}
                </td>
                <td><code style="font-size:12px">{{ m.source or '-' }}</code></td>
                <td><code style="font-size:12px">{{ m.fstype or '-' }}</code></td>
              </tr>
            {% endfor %}
          </tbody>
        </table>
      </section>
    {% endif %}

    <section>
      <h2>최근 작업 로그</h2>
      {% for name, content in tails.items() %}
        <h3>{{ name }}</h3>
        <pre>{{ content }}</pre>
      {% endfor %}
    </section>
  </div>

  <div id="toast" class="toast"></div>

  <script>
    function showToast(msg) {
      const t = document.getElementById('toast');
      t.innerText = msg;
      t.style.display = 'block';
      setTimeout(() => { t.style.display = 'none'; }, 3000);
    }

    async function controlTask(task, action) {
      showToast(`${task} 작업을 ${action == 'start' ? '시작' : '중지'}합니다...`);
      try {
        const res = await fetch(`/api/control/${task}/${action}`, { method: 'POST' });
        const data = await res.json();
        if (data.status === 'ok') {
          showToast(`요청 성공: ${data.message}`);
          setTimeout(() => location.reload(), 2000);
        } else {
          showToast(`오류: ${data.message}`);
        }
      } catch (err) {
        showToast(`네트워크 오류가 발생했습니다.`);
      }
    }
  </script>
</body>
</html>
"""

def _get_live_mounts():
    # status.json의 마운트 정보를 우선으로 하되 실시간 확인 병행
    paths = ["/mnt/nas/woooook/Photos", "/mnt/backups/HA backups", "/mnt/surveillance"]
    mounts = []
    for p in paths:
        mounted = False
        source = ""
        fstype = ""
        try:
            res = subprocess.run(['findmnt', '-no', 'SOURCE,FSTYPE', '--target', p], capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip():
                mounted = True
                parts = res.stdout.strip().split()
                if len(parts) >= 2:
                    source, fstype = parts[0], parts[1]
        except:
            pass
        mounts.append({"path": p, "mounted": mounted, "source": source, "fstype": fstype})
    return mounts

def _read_last_lines(path, lines=50):
    if not os.path.exists(path): return "(로그 파일 없음)"
    try:
        result = subprocess.run(['tail', '-n', str(lines), path], capture_output=True, text=True, errors='ignore')
        return result.stdout
    except: return "(읽기 실패)"

def format_bytes(b):
    if b is None: return "0 B"
    b = float(b)
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if b < 1024: return f"{b:.2f} {unit}"
        b /= 1024
    return f"{b:.2f} PB"

def format_seconds(s):
    if s is None or s == 0: return "대기 중"
    return str(datetime.timedelta(seconds=int(s)))

@app.template_filter('format_bytes')
def _format_bytes_filter(b): return format_bytes(b)

@app.template_filter('format_seconds')
def _format_seconds_filter(s): return format_seconds(s)

@app.route("/")
def index():
    rc_stats = None
    try:
        resp = requests.post(RC_URL, timeout=0.5)
        if resp.status_code == 200:
            rc_stats = resp.json()
            if rc_stats and 'percentage' not in rc_stats:
                total, current = rc_stats.get('totalBytes', 0), rc_stats.get('bytes', 0)
                rc_stats['percentage'] = round((current / total) * 100, 1) if total > 0 else 0
    except: pass

    live_mounts = _get_live_mounts()
    data = None
    stale = False
    hours = None
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            last = data.get("last_run")
            if last:
                dt = datetime.datetime.fromisoformat(last)
                now = datetime.datetime.now(dt.tzinfo) if dt.tzinfo else datetime.datetime.now()
                diff = now - dt
                hours = int(diff.total_seconds() // 3600)
                stale = diff.total_seconds() > 26*3600
        except: pass

    tails = {
        "Photos": _read_last_lines("/var/log/rclone_photos.log"),
        "HA Backups": _read_last_lines("/var/log/rclone_HA_backups.log"),
        "Surveillance": _read_last_lines("/var/log/surveillance.log"),
    }

    return render_template_string(TEMPLATE, rc_stats=rc_stats, live_mounts=live_mounts, data=data, tails=tails, stale=stale, hours=hours)

@app.route("/api/control/<task>/<action>", methods=["POST"])
def control_task(task, action):
    script_path = "/usr/local/bin/rclone_daily.sh"
    
    if action == "start":
        try:
            cmd = ["sudo", script_path]
            if task != "all": cmd.append(task)
            # 백그라운드로 실행
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return jsonify({"status": "ok", "message": f"{task} 작업 시작됨"})
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)})
            
    elif action == "stop":
        try:
            # 1. rclone_daily.sh 스크립트 중지
            if task == "all":
                subprocess.run(["sudo", "pkill", "-f", script_path])
            else:
                pass

            # 2. 관련 rclone 프로세스 중지
            if task == "all":
                subprocess.run(["sudo", "pkill", "-9", "rclone"])
            else:
                search_map = {
                    "photos": "teldrive:/photos",
                    "HA_backups": "teldrive:/HA backups",
                    "surveillance": "teldrive:/surveillance"
                }
                pattern = search_map.get(task, task)
                subprocess.run(["sudo", "pkill", "-9", "-f", f"rclone.*{pattern}"])
            
            # 3. 상태 업데이트 (중지됨 표시)
            log_map = {
                "photos": "/var/log/rclone_photos.log",
                "HA_backups": "/var/log/rclone_HA_backups.log",
                "surveillance": "/var/log/surveillance.log"
            }
            tasks_to_update = [task] if task != "all" else ["photos", "HA_backups", "surveillance"]
            
            for t in tasks_to_update:
                logfile = log_map.get(t, "/var/log/rclone.log")
                subprocess.run(["sudo", script_path, "_update_status", t, "error", logfile])
            
            return jsonify({"status": "ok", "message": f"{task} 작업 중지됨"})
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)})

    return jsonify({"status": "error", "message": "Invalid action"})

@app.route("/api/stats")
def api_stats():
    try:
        resp = requests.post(RC_URL, timeout=0.5)
        return jsonify(resp.json())
    except: return jsonify({"status": "idle"})

@app.route("/status.json")
def status_json(): return send_from_directory(STATUS_DIR, "status.json")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
