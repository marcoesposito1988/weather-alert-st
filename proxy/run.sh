#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== DWD Weather LAN Proxy ==="
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    echo "Starting proxy with Docker Compose on port 8080..."
    docker compose up -d --build
    echo "Proxy running! Accessible at http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):8080"
elif command -v docker &>/dev/null; then
    echo "Building Docker image..."
    docker build -t dwd-weather-proxy:latest .
    echo "Starting Docker container..."
    docker run -d \
        --name dwd-weather-proxy \
        --restart unless-stopped \
        -p 8080:8080 \
        --security-opt no-new-privileges:true \
        --cap-drop ALL \
        --cap-add NET_BIND_SERVICE \
        --read-only \
        --tmpfs /tmp --tmpfs /var/run --tmpfs /var/cache/nginx \
        dwd-weather-proxy:latest
    echo "Proxy running! Accessible at http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):8080"
else
    echo "Error: Docker is required to run the proxy." >&2
    exit 1
fi
