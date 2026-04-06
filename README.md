# Teldrive Relay (rclone status web)

This project provides a simple web interface for monitoring daily `rclone` backup tasks.
It's designed to run on a Linux environment (like an LXC container) and provides status updates and recent log snippets via a Flask web application.

## Components

- **WebApp (`webapp/app.py`)**: A Flask application that reads status from a JSON file and logs to display a web interface.
- **Scripts (`scripts/`)**: Shell scripts that perform the actual `rclone` backup tasks.
- **Config (`config/`)**: Configuration for `systemd`, `cron`, and `logrotate`.
- **Installer (`install.sh`)**: A script to automate the setup of all components.

## Installation

1. Clone this repository.
2. Run the installer:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

## Usage

- Access the web UI at `http://<IP>:8080`.
- Daily backups are scheduled via `cron`.
- Manual backup: `/usr/local/bin/rclone_daily.sh`
