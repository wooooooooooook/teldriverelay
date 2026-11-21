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
│   ├── config.json         # 태스크 정의 (schedule, source, dest) — 로컬 전용, git 미추적
│   ├── config.example.json # config.json 템플릿
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
1. `git pull` (로컬 `config/config.json`이 사라지지 않도록 백업 후 복원)
2. `scripts/rclone_daily.sh` → CT104 `/usr/local/bin/`
3. `config/config.json` → CT104 `/var/www/rclone-status/` (로컬 파일이 있을 때만, 교체 전 타임스탬프 백업)
4. `systemctl daemon-reload && restart rclone-status`

## config/config.json (로컬 전용)

`config/config.json`은 **git에서 추적하지 않는다**(`.gitignore` 등록). 장비마다 다른
로컬 설정이라 저장소에 두면 라이브 설정과 어긋나기 쉽다.

- 처음 받은 클론에서는 템플릿을 복사해서 만든다: `cp config/config.example.json config/config.json`
- 이후 수정은 로컬에서만 하고, 커밋/푸시하지 않는다.
- `deploy.sh`는 이 로컬 파일을 CT104로 복사한다. 파일이 없으면 설정 배포를 건너뛰고
  CT104의 라이브 설정을 그대로 둔다.
- 실제 동작 중인 설정은 CT104의 `/var/www/rclone-status/config.json`이며, 그쪽에서 직접
  수정하는 편이 안전하다(수정 후 로컬 파일도 같은 내용으로 맞춰 두면 이후 배포에서 되돌아가지 않는다).

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
# CT104에서 직접 편집 (실제 동작하는 설정)
ssh root@192.168.0.99 "pct exec 104 -- vim /var/www/rclone-status/config.json"

# 로컬 사본도 같은 내용으로 맞춰 둔다 (git 커밋하지 않음)
vim config/config.json
```

## rclone copy 플래그

`config.json`의 `rclone_flags` 필드로 조정 가능. 기본값:
```
--create-empty-src-dirs --exclude @*/** --ignore-existing --transfers 1 --checkers 2 --tpslimit 3
```

## 타스크 schedule

cron 표현식. 예: `0 3 * * *` = 매일 03:00 KST.