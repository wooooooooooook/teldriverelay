# Teldrive Relay — LXC rclone backup monitor

LXC 컨테이너(ct104) 기반 rclone 백업 스케줄러 + Flask 웹 모니터.

## 디렉토리 구조

```
/
├── webapp/
│   └── app.py              # Flask 웹 UI (port 8080, www-data)
├── scripts/
│   └── rclone_daily.sh     # rclone 백업 코어 + _tick cron 스케줄러
├── config/
│   ├── config.json         # 태스크 정의 (schedule, source, dest)
│   ├── rclone-daily.cron   # /etc/cron.d/rclone-daily 원본 백업
│   └── rclone-status.service # systemd 유닛 원본 백업
└── deploy.sh               # git pull → CT104 배포 스크립트
```

## 배포

```bash
cd ~/workspace/teldriverelay
git pull
./deploy.sh
```

`deploy.sh`이 하는 일:
1. `git pull`
2. `scripts/rclone_daily.sh` → CT104 `/usr/local/bin/`
3. `config/config.json` → CT104 `/var/www/rclone-status/`
4. `systemctl daemon-reload && restart rclone-status`

## CT104 내부 구성

| 경로 | 용도 |
|------|------|
| `/opt/rclone-status/app.py` | Flask 웹앱 |
| `/opt/rclone-status/venv/` | Python venv |
| `/usr/local/bin/rclone_daily.sh` | 백업 실행 스크립트 |
| `/var/www/rclone-status/config.json` | 태스크 설정 |
| `/var/www/rclone-status/status.json` | 실행 결과 JSON |
| `/var/www/rclone-status/*.tail` | 태스크별 로그 tail |
| `/etc/systemd/system/rclone-status.service` | systemd 유닛 |
| `/etc/cron.d/rclone-daily` | 매분 _tick 실행 |
| `/root/.config/rclone/rclone.conf` | rclone 원격 설정 (secrets — repo에 미포함) |

## 태스크 추가/수정

```bash
# CT104에서 직접 편집
ssh root@192.168.0.99 "pct exec 104 -- vim /var/www/rclone-status/config.json"

# repo에 반영 (로컬에서)
# config/config.json을 편집 후 push
```

## rclone copy 플래그

`config.json`의 `rclone_flags` 필드로 조정 가능. 기본값:
```
--create-empty-src-dirs --exclude @*/** --ignore-existing --transfers 1 --checkers 2 --tpslimit 3
```

## 타스크 schedule

cron 표현식. 예: `0 3 * * *` = 매일 03:00 KST.