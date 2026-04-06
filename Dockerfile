FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    cron \
    supervisor \
    sudo \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Teldrive rclone
RUN curl -sSL instl.vercel.app/rclone | bash

# Set up directories
WORKDIR /app
RUN mkdir -p /app/status /var/www/rclone-status /root/.config/rclone
RUN ln -s /app/status /var/www/rclone-status

# Install Python dependencies
COPY webapp/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt || pip install --no-cache-dir flask requests

# Copy app files
COPY webapp/ /app/webapp/
COPY scripts/ /app/scripts/
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /app/entrypoint.sh

# Ensure scripts are executable
RUN chmod +x /app/scripts/*.sh /app/entrypoint.sh

# Set environment variables
ENV STATUS_DIR="/app/status"
ENV WEB_PORT="8080"
ENV CRON_SCHEDULE="0 3 * * *"

# Expose port
EXPOSE 8080

# Run entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
