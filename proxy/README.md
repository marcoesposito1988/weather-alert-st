# DWD Weather Local LAN Proxy

A lightweight, secure Nginx reverse proxy designed to run in your local network (e.g. Raspberry Pi, NAS, Home Assistant host, or home server).

## Why is this needed?

SmartThings Hub Edge drivers run inside a local hardware sandbox with the `lan` permission. On many hubs, firmware restrictions isolate the driver from resolving external WAN DNS domains (e.g., `api.brightsky.dev`) or establishing outbound TLS handshakes.

By running this local proxy on a machine in your LAN, your SmartThings Hub only needs to communicate with your local machine's IP (e.g., `http://192.168.1.50:8080`), which then securely fetches and relays live DWD weather data over HTTPS.

---

## Security Features

This proxy is designed with **defense-in-depth**:
- **Non-Root Execution**: Runs as unprivileged user `nginx` (`nginxinc/nginx-unprivileged:alpine-slim`).
- **Read-Only Root Filesystem**: Container root filesystem is mounted `read_only: true` with ephemeral `/tmp` and `/var/run` tmpfs.
- **Dropped Capabilities**: Drops all Linux capabilities (`cap_drop: ALL`), adding only `NET_BIND_SERVICE`.
- **Privilege Escalation Prevention**: `no-new-privileges: true`.
- **Method Restriction**: Rejects `POST`, `PUT`, `DELETE`, etc., permitting only safe `GET` and `HEAD` requests.
- **Rate Limiting**: Built-in LAN rate limiting (10 req/sec with burst) to prevent request flooding.
- **Dedicated Scope**: Proxies solely to `https://api.brightsky.dev` (not an open proxy).

---

## Quick Start

### Option 1: Quick Start Script

From the project root:
```bash
./proxy/run.sh
```
This script will build and launch the container on port `8080`, and display your machine's local LAN IP.

### Option 2: Docker Compose

```bash
docker compose up -d
```
*(Or `docker compose -f proxy/docker-compose.yml up -d`)*

### Option 3: Standard Docker CLI

```bash
# Build the image
docker build -t dwd-weather-proxy:latest ./proxy

# Run the container
docker run -d \
  --name dwd-weather-proxy \
  --restart unless-stopped \
  -p 8080:8080 \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  --read-only \
  --tmpfs /tmp --tmpfs /var/run \
  dwd-weather-proxy:latest
```

---

## Verification

Test that the proxy is operational:

```bash
# Health Check
curl http://localhost:8080/health

# Weather Query Test
curl "http://localhost:8080/current_weather?lat=48.137154&lon=11.576124"
```

---

## SmartThings Configuration

1. Find your host machine's LAN IP address (e.g. `192.168.1.50`).
2. Open the **SmartThings App** on your phone.
3. Open your **DWD Weather & Blind Guard** device -> **Settings (⋮)**.
4. Set **LAN Proxy / Custom Endpoint (Optional)** to:
   ```
   http://192.168.1.50:8080
   ```
5. Save settings and tap **Refresh** in the device tile.
