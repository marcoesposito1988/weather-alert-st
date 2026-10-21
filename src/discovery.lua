local log = pcall(require, "log") and require("log") or {
  info = function(...) print("[INFO]", ...) end,
  warn = function(...) print("[WARN]", ...) end,
  error = function(...) print("[ERROR]", ...) end,
  debug = function(...) print("[DEBUG]", ...) end
}

local discovery = {}

function discovery.start(driver, opts, on_complete)
  log.info("Starting DWD Weather Station discovery scan...")

  local device_metadata = {
    type = "LAN",
    device_network_id = "dwd_weather_station_munich_v1",
    label = "DWD Weather and Blind Guard",
    profile = "weather-station",
    manufacturer = "Deutscher Wetterdienst (DWD)",
    model = "DWD-BrightSky-v1",
    vendor_provided_label = "DWD Weather Station"
  }

  local ok, err = driver:try_create_device(device_metadata)
  if not ok then
    log.warn(string.format("Discovery try_create_device: %s", tostring(err)))
  else
    log.info("Successfully requested creation of DWD Weather Station device")
  end

  if on_complete then
    on_complete()
  end
end

return discovery
