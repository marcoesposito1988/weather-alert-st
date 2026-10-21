local Driver = require("st.driver")
local capabilities = require("st.capabilities")
local log = require("log")

local weather_service = require("weather_service")
local wind_logic = require("wind_logic")
local discovery = require("discovery")

local TIMER_KEY = "weather_poll_timer"

--- Helper to emit an event on a specific component if it exists, falling back to device:emit_event
local function emit_component_event(device, component_id, event)
  if component_id and device.profile and device.profile.components and device.profile.components[component_id] then
    if device.emit_component_event then
      device:emit_component_event(device.profile.components[component_id], event)
      return
    end
  end
  device:emit_event(event)
end

--- Poll weather data and update device capabilities & wind alarm
local function poll_weather(driver, device)
  log.info(string.format("Polling weather data for device [%s]", device.label or device.device_network_id))

  local data, err = weather_service.fetch_weather(device.preferences)
  if not data then
    local failure_count = (device:get_field("consecutive_failures") or 0) + 1
    device:set_field("consecutive_failures", failure_count)
    local threshold = tonumber(device.preferences.failureThreshold) or 1
    if threshold < 1 then threshold = 1 end

    log.error(string.format(
      "Weather fetch failed for [%s] (Failure %d/%d): %s",
      device.label or device.id, failure_count, threshold, tostring(err)
    ))

    if failure_count >= threshold then
      device:set_field("proxy_error_state", true)
      -- Mark main presence as not present (offline/unreachable)
      device:emit_event(capabilities.presenceSensor.presence.not_present())
      -- Update proxy component
      emit_component_event(device, "proxy", capabilities.presenceSensor.presence.not_present())
      emit_component_event(device, "proxy", capabilities.switch.switch.on())
      emit_component_event(device, "proxy", capabilities.contactSensor.contact.open())
      log.warn(string.format(
        "*** PROXY / WEATHER FEED OFFLINE ALERT TRIGGERED *** %d consecutive fetch failures. Last error: %s",
        failure_count, tostring(err)
      ))
    end
    return
  end

  -- Successful fetch: reset failure counter & clear proxy error
  local prev_failure_count = device:get_field("consecutive_failures") or 0
  local prev_proxy_error = device:get_field("proxy_error_state")
  device:set_field("consecutive_failures", 0)
  device:set_field("proxy_error_state", false)

  if prev_proxy_error or prev_failure_count > 0 then
    log.info("Proxy / weather feed connection restored to normal.")
  end

  -- Emit Online / Present status
  device:emit_event(capabilities.presenceSensor.presence.present())
  emit_component_event(device, "proxy", capabilities.presenceSensor.presence.present())
  emit_component_event(device, "proxy", capabilities.switch.switch.off())
  emit_component_event(device, "proxy", capabilities.contactSensor.contact.closed())

  local prev_alert = device:get_field("wind_alert_state")
  local is_alert, effective_wind, threshold_kmh, reset_threshold_kmh = wind_logic.evaluate_alert(
    data.wind_speed_kmh,
    data.wind_gust_kmh,
    device.preferences.windThreshold,
    device.preferences.windUnit,
    device.preferences.useGusts,
    device.preferences.hysteresis,
    prev_alert
  )

  device:set_field("wind_alert_state", is_alert)
  device:set_field("last_weather_data", data)

  -- Emit temperature, humidity, atmospheric pressure
  device:emit_event(capabilities.temperatureMeasurement.temperature({ value = data.temperature, unit = "C" }))
  device:emit_event(capabilities.relativeHumidityMeasurement.humidity({ value = data.humidity }))
  device:emit_event(capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = data.pressure_kpa, unit = "kPa" }))

  -- Emit Wind Alert status:
  -- Contact Sensor: 'open' = High Wind Danger (close blinds), 'closed' = Safe
  -- Switch: 'on' = High Wind Alert active, 'off' = Inactive
  if is_alert then
    device:emit_event(capabilities.contactSensor.contact.open())
    device:emit_event(capabilities.switch.switch.on())
    log.warn(string.format(
      "*** HIGH WIND ALERT TRIGGERED *** Effective wind: %.1f km/h (Gust: %.1f km/h, Sustained: %.1f km/h) >= Threshold: %.1f km/h. Blinds should be CLOSED. Station: %s",
      effective_wind, data.wind_gust_kmh, data.wind_speed_kmh, threshold_kmh, data.station_name
    ))
  else
    device:emit_event(capabilities.contactSensor.contact.closed())
    device:emit_event(capabilities.switch.switch.off())
    log.info(string.format(
      "Wind conditions normal. Effective wind: %.1f km/h (Threshold: %.1f km/h, Reset: %.1f km/h). Station: %s, Temp: %.1f°C, Humidity: %d%%",
      effective_wind, threshold_kmh, reset_threshold_kmh, data.station_name, data.temperature, data.humidity
    ))
  end
end

--- Schedule or reschedule periodic weather polling timer
local function setup_polling_schedule(driver, device)
  local existing_timer = device:get_field(TIMER_KEY)
  if existing_timer then
    device.thread:cancel_timer(existing_timer)
    device:set_field(TIMER_KEY, nil)
  end

  local interval_mins = tonumber(device.preferences.pollInterval) or 10
  if interval_mins < 1 then interval_mins = 1 end
  local interval_secs = interval_mins * 60

  log.info(string.format("Scheduling weather polling every %d minutes (%d seconds)", interval_mins, interval_secs))

  local timer = device.thread:call_on_schedule(interval_secs, function()
    poll_weather(driver, device)
  end, "weather_poll_timer")

  device:set_field(TIMER_KEY, timer)
end

------------------------------------------------------------------------
-- Lifecycle Handlers
------------------------------------------------------------------------

local function device_init(driver, device)
  log.info(string.format("Initializing DWD Weather device [%s]", device.label or device.id))
  setup_polling_schedule(driver, device)
end

local function device_added(driver, device)
  log.info(string.format("DWD Weather device added [%s]", device.label or device.id))
  -- Initialize default state
  device:emit_event(capabilities.contactSensor.contact.closed())
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.presenceSensor.presence.present())
  device:emit_event(capabilities.temperatureMeasurement.temperature({ value = 15.0, unit = "C" }))
  device:emit_event(capabilities.relativeHumidityMeasurement.humidity({ value = 60 }))
  device:emit_event(capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 101.3, unit = "kPa" }))

  -- Initialize proxy component state
  emit_component_event(device, "proxy", capabilities.presenceSensor.presence.present())
  emit_component_event(device, "proxy", capabilities.switch.switch.off())
  emit_component_event(device, "proxy", capabilities.contactSensor.contact.closed())

  -- Perform immediate initial poll
  device.thread:queue_event(function()
    poll_weather(driver, device)
  end)
end

local function device_info_changed(driver, device, event, args)
  log.info(string.format("Device preferences updated for [%s]", device.label or device.id))

  local old_interval = args and args.old_st_store and args.old_st_store.preferences and args.old_st_store.preferences.pollInterval
  local new_interval = device.preferences.pollInterval

  if old_interval ~= new_interval then
    log.info(string.format("Poll interval changed from %s to %s minutes", tostring(old_interval), tostring(new_interval)))
    setup_polling_schedule(driver, device)
  end

  -- Immediately re-fetch and re-evaluate with new location and threshold settings
  device.thread:queue_event(function()
    poll_weather(driver, device)
  end)
end

local function device_deleted(driver, device)
  log.info(string.format("Deleting DWD Weather device [%s]", device.label or device.id))
  local timer = device:get_field(TIMER_KEY)
  if timer then
    device.thread:cancel_timer(timer)
    device:set_field(TIMER_KEY, nil)
  end
end

------------------------------------------------------------------------
-- Capability Handlers
------------------------------------------------------------------------

local function handle_refresh(driver, device, command)
  log.info("Manual refresh requested from SmartThings UI")
  poll_weather(driver, device)
end

local function handle_switch_on(driver, device, command)
  if command and command.component == "proxy" then
    log.info("Manual Proxy Alert test on proxy component: Switch turned ON")
    device:set_field("proxy_error_state", true)
    emit_component_event(device, "proxy", capabilities.switch.switch.on())
    emit_component_event(device, "proxy", capabilities.contactSensor.contact.open())
    emit_component_event(device, "proxy", capabilities.presenceSensor.presence.not_present())
    device:emit_event(capabilities.presenceSensor.presence.not_present())
  else
    log.info("Manual High Wind Alert test: Switch turned ON")
    device:set_field("wind_alert_state", true)
    device:emit_event(capabilities.switch.switch.on())
    device:emit_event(capabilities.contactSensor.contact.open())
  end
end

local function handle_switch_off(driver, device, command)
  if command and command.component == "proxy" then
    log.info("Manual Proxy Alert reset on proxy component: Switch turned OFF")
    device:set_field("proxy_error_state", false)
    device:set_field("consecutive_failures", 0)
    emit_component_event(device, "proxy", capabilities.switch.switch.off())
    emit_component_event(device, "proxy", capabilities.contactSensor.contact.closed())
    emit_component_event(device, "proxy", capabilities.presenceSensor.presence.present())
    device:emit_event(capabilities.presenceSensor.presence.present())
  else
    log.info("Manual High Wind Alert reset: Switch turned OFF")
    device:set_field("wind_alert_state", false)
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.contactSensor.contact.closed())
  end
end

------------------------------------------------------------------------
-- Driver Definition
------------------------------------------------------------------------

local weather_driver = Driver("dwd-weather-alert", {
  discovery = discovery.start,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = device_info_changed,
    deleted = device_deleted
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off
    }
  }
})

weather_driver:run()
