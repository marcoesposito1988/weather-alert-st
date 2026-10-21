# DWD Weather & Wind Alert SmartThings Edge Driver

A SmartThings Edge Driver written in Lua that polls real-time weather and wind data from the **Deutscher Wetterdienst (DWD)** to protect window blinds and awnings against high wind damage.

---

## Key Features

- **DWD Weather Integration**: Polls official DWD weather data in real-time via the Bright Sky API (synop & MOSMIX station observations) with fallback to Open-Meteo DWD ICON.
- **Blind & Awning Protection Alert**:
  - Automatically raises an alarm when sustained wind or wind gusts breach your configured safety threshold.
  - Exposes both **Contact Sensor** (`open` = High Wind Danger / Close Blinds, `closed` = Safe) and **Switch** (`on` = High Wind Alert, `off` = Normal) capabilities so you can trigger SmartThings Routines easily.
  - **Hysteresis Anti-Flapping**: Prevents rapid open/close cycles by requiring wind to drop below a customizable percentage of the threshold before clearing the alert.
- **Proxy & Connection Health Monitoring (No Silent Failures)**:
  - Continuously monitors proxy connectivity and DWD weather feed health.
  - Exposes **Presence Sensor** (`present` = Online, `not present` = Offline / Proxy Failure) on the main device.
  - Provides a dedicated **Proxy & Feed Status** component with a **Switch** (`on` = Proxy Error, `off` = Normal) and **Contact Sensor** (`open` = Offline, `closed` = OK) to trigger instant user notifications via Routines.
  - Configurable **Offline Alert Threshold** (1 to 5 consecutive failed polls) to filter temporary glitches.
- **Configurable from SmartThings App UI**:
  - **Location Modes**:
    - Munich City Center (DWD Station `03379` / `10865`) - default
    - Munich Airport (DWD Station `01262` / `10870`)
    - Custom Coordinates (Latitude / Longitude)
    - Custom DWD Station ID
  - **Wind Strength Threshold**: Adjustable value in **km/h**, **m/s**, or **Beaufort Scale (Bft 1–12)**.
  - **Wind Gust Evaluation**: Option to trigger on peak wind gusts (recommended for blind safety) or average sustained wind.
  - **Polling Frequency**: 1 to 60 minutes.
   - **Weather Service Provider**: DWD via Bright Sky API or DWD ICON via Open-Meteo.
   - **LAN Proxy / Custom Endpoint (Optional)**: Configure a local LAN IP (e.g. `http://192.168.1.50:8080`) to route requests through a local gateway when hub WAN DNS is restricted.
- **Full Sensor Readings**: Reports Temperature (°C), Relative Humidity (%), Atmospheric Pressure (kPa/hPa), Sustained Wind Speed (km/h), and Wind Gust Speed (km/h).
- **Custom Wind Capabilities**: Exposes dedicated `windSpeed` and `windGust` measurement capabilities with exact numeric values for clean UI display and automation triggers.
- **Manual Control & Testing**: "Refresh" button for immediate live weather fetch and "Switch" toggle to test blind-closing automations.

---

## Project Structure

```
weather-st/
├── config.yaml                   # Driver metadata & LAN permissions
├── fingerprints.yaml             # LAN discovery profile mapping
├── docker-compose.yml            # Docker Compose configuration for local proxy
├── proxy/
│   ├── Dockerfile                # Hardened unprivileged Nginx proxy image
│   ├── nginx.conf                # Proxy configuration & rate limiting
│   ├── docker-compose.yml        # Proxy standalone compose file
│   ├── run.sh                    # One-command quickstart script
│   └── README.md                 # Proxy documentation & setup guide
├── profiles/
│   └── weather-station.yml       # Device capabilities & UI preference settings
├── src/
│   ├── init.lua                  # Driver lifecycle & capability handlers
│   ├── discovery.lua             # LAN discovery handler
│   ├── weather_service.lua       # DWD Bright Sky & Open-Meteo API client
│   ├── wind_logic.lua            # Beaufort conversions & wind alert hysteresis logic
│   └── json.lua                  # Pure Lua JSON parser
├── tests/
│   ├── test_suite.lua            # Unit test suite
│   └── mock_driver_test.lua      # Lifecycle & capability mock simulation
└── README.md
```

---

## Installation & Deployment

### 1. Prerequisites
Install the official [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli):
```bash
# macOS (Homebrew)
brew install smartthings
```

Log in to your Samsung SmartThings account:
```bash
smartthings edge:channels
```

### 2. (Optional One-Time Setup) Register Custom Wind Capabilities
To display dedicated **Wind Speed** and **Wind Gust** cards in the SmartThings UI:
```bash
# Create capability definitions
smartthings capabilities:create -i capabilities/windSpeed.json
smartthings capabilities:create -i capabilities/windGust.json

# Create presentations (replace <CAPABILITY_ID> with the ID returned above, e.g. <namespace>.windSpeed)
smartthings capabilities:presentation:create <WIND_SPEED_CAP_ID> -i capabilities/windSpeed-presentation.json
smartthings capabilities:presentation:create <WIND_GUST_CAP_ID> -i capabilities/windGust-presentation.json
```

### 3. Package and Publish Driver
From the project root:
```bash
# Package the driver
smartthings edge:drivers:package .

# Assign the driver to your personal channel
smartthings edge:channels:assign <DRIVER_ID> --channel <CHANNEL_ID>

# Install the driver onto your SmartThings Hub
smartthings edge:drivers:install <DRIVER_ID> --channel <CHANNEL_ID> --hub <HUB_ID>
```

> **Tip:** You can also package, assign, and install in a single step:
> ```bash
> smartthings edge:drivers:package --channel <CHANNEL_ID> --hub <HUB_ID>
> ```

### 3. Add the Device in SmartThings
1. Open the **SmartThings App** on your phone.
2. Tap **Devices** -> **+** (Add) -> **Add device** -> **Scan for nearby devices**.
3. The **"DWD Weather & Blind Guard"** device will appear and be added to your room.

---

## Hosting a Local LAN Proxy (Docker)

If your SmartThings Hub's Edge environment cannot resolve external WAN domain names or make direct outbound HTTPS connections (e.g. `[string "socket"]:98: host or service not provided, or not known`), you can host a lightweight, secure local proxy on any local machine (Raspberry Pi, NAS, server) using Docker:

### Quick Start
```bash
# Option A: One-line start script
./proxy/run.sh

# Option B: Docker Compose
docker compose up -d
```

### In SmartThings App
1. Open your **DWD Weather & Blind Guard** device settings in the SmartThings app.
2. In **LAN Proxy / Custom Endpoint (Optional)**, enter your proxy machine's local IP:
   ```
   http://192.168.1.50:8080
   ```
3. Tap **Save** and test via the **Refresh** button.

*For complete details, security features, and manual Docker commands, see [`proxy/README.md`](proxy/README.md).*

---

## Configuring Settings in the UI

In the SmartThings App:
1. Open the **DWD Weather & Blind Guard** device card.
2. Tap the **Three Dots (⋮)** in the top-right corner -> **Settings**.
3. Configure your preferences:
   - **Location Mode**: Select *Munich City Center*, *Munich Airport*, or enter *Custom Coordinates / Station ID*.
   - **Wind Threshold (Blind Protection)**: Set the threshold (e.g. `35` km/h or `6` Beaufort).
   - **Wind Speed Unit**: `km/h`, `m/s`, or `Beaufort Scale`.
   - **Trigger on Wind Gusts**: `On` (recommended so sudden gusts close blinds before damage occurs).
   - **Polling Interval**: e.g., `10` minutes.
   - **Hysteresis Reset**: e.g., `80%` (alert clears only when wind drops below 80% of threshold).

---

## Setting Up SmartThings Routine to Close Blinds

To automatically close your window blinds when the wind becomes too strong:

1. Open the **SmartThings App** -> **Routines** -> **+** (Create Routine).
2. **If (Condition)**:
   - Tap **Device status** -> Select **DWD Weather & Blind Guard**.
   - Select **Contact Sensor** -> **Open** (or **Switch** -> **On**).
3. **Then (Action)**:
   - Tap **Control devices** -> Select your **Window Blinds / Shades**.
   - Set action to **Close** (or Set Position to `0%`).
4. Save the routine as **"Close Blinds on High Wind"**.

*(Optional)* You can create a second routine to re-open the blinds once the wind subsides (**If Contact Sensor = Closed -> Open Blinds**).

---

## Setting Up SmartThings Routine for Proxy / Connection Failure Alerts

To ensure you are immediately notified if your local proxy container stops running or weather fetching fails:

1. Open the **SmartThings App** -> **Routines** -> **+** (Create Routine).
2. **If (Condition)**:
   - Tap **Device status** -> Select **DWD Weather & Blind Guard**.
   - Choose either:
     - **Presence sensor** -> **Not present**
     - OR **Proxy & Feed Status (Switch)** -> **On**
     - OR **Proxy & Feed Status (Contact sensor)** -> **Open**
3. **Then (Action)**:
   - Tap **Notify someone** -> **Send notification to members** (or Send text message / audio notification).
   - Enter message: `"Warning: DWD Weather Proxy is offline or unreachable. Blinds automated wind protection may be suspended."`
4. Save the routine as **"Weather Proxy Offline Alert"**.

---

## Running Tests

To run the automated test suite locally:
```bash
lua tests/test_suite.lua
lua tests/mock_driver_test.lua
```
