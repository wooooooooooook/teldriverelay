# Teldrive Relay (rclone status web)

This project provides a simple web interface for monitoring daily `rclone` backup tasks.
It's designed to run as a Docker container, providing status updates and recent log snippets via a Flask web application, while scheduling backups with cron.

## Components

- **WebApp (`webapp/app.py`)**: A Flask application that reads status from a JSON file and logs to display a web interface.
- **Scripts (`scripts/`)**: Shell scripts that perform the actual `rclone` backup tasks.
- **Docker**: The app is fully containerized using `Dockerfile` and `docker-compose.yml`.

## Installation (Docker)

1. Clone this repository.
2. Edit `docker-compose.yml` to match your environment variables and volume mounts.
    - Set `TELDRIVE_ACCESS_TOKEN`, `TELDRIVE_API_HOST`, etc.
    - Map your local directories to the `SOURCE_PHOTOS`, `SOURCE_HA`, and `SOURCE_SURV` paths.
3. Build and run the container:
   ```bash
   docker-compose up -d --build
   ```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TELDRIVE_ACCESS_TOKEN` | Your Teldrive access token | (Required) |
| `TELDRIVE_API_HOST` | Your Teldrive API host URL | (Required) |
| `TELDRIVE_ENCRYPT_FILES` | Enable file encryption | `true` |
| `TELDRIVE_ROOT_FOLDER_ID` | Specific folder ID for upload | (Optional) |
| `CRON_SCHEDULE` | Cron schedule for backups | `0 3 * * *` |
| `SOURCE_PHOTOS` | Path to Photos inside container | `/mnt/nas/woooook/Photos` |
| `SOURCE_HA` | Path to HA backups inside container | `/mnt/backups/HA backups` |
| `SOURCE_SURV` | Path to Surveillance inside container| `/mnt/surveillance` |

## Usage

- Access the web UI at `http://<IP>:8080`.
- Daily backups are scheduled automatically.
- To trigger a manual backup, use the web UI or run:
  ```bash
  docker exec -it teldrive-relay /app/scripts/rclone_daily.sh
  ```
