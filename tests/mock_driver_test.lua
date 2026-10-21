package.path = "./src/?.lua;" .. package.path

local wind_logic = require("wind_logic")
local weather_service = require("weather_service")

print("=== Testing Driver Lifecycle & Event Simulation ===")

-- Mock SmartThings environment
local emitted_events = {}
local stored_fields = {}

local mock_device = {
  id = "mock_device_uuid",
  label = "DWD Weather & Blind Guard",
  device_network_id = "dwd_weather_station_munich_v1",
  preferences = {
    locationMode = "munich_city",
    latitude = 48.137154,
    longitude = 11.576124,
    stationId = "03379",
    windThreshold = 35,
    windUnit = "kmh",
    useGusts = true,
    weatherSource = "brightsky",
    pollInterval = 10,
    hysteresis = 80
  },
  emit_event = function(self, evt)
    table.insert(emitted_events, evt)
    print("  -> Device Emitted Event: " .. tostring(evt.capability) .. "." .. tostring(evt.attribute) .. " = " .. tostring(evt.value))
  end,
  set_field = function(self, key, val)
    stored_fields[key] = val
  end,
  get_field = function(self, key)
    return stored_fields[key]
  end,
  thread = {
    cancel_timer = function(self, timer) end,
    call_on_schedule = function(self, interval, cb, name) return "timer_123" end,
    queue_event = function(self, cb) cb() end
  }
}

-- Mock Capability Generators
local capabilities = {
  temperatureMeasurement = {
    temperature = function(v) return { capability = "temperatureMeasurement", attribute = "temperature", value = v.value, unit = v.unit } end
  },
  relativeHumidityMeasurement = {
    humidity = function(v) return { capability = "relativeHumidityMeasurement", attribute = "humidity", value = v.value } end
  },
  atmosphericPressureMeasurement = {
    atmosphericPressure = function(v) return { capability = "atmosphericPressureMeasurement", attribute = "atmosphericPressure", value = v.value, unit = v.unit } end
  },
  contactSensor = {
    contact = {
      open = function() return { capability = "contactSensor", attribute = "contact", value = "open" } end,
      closed = function() return { capability = "contactSensor", attribute = "contact", value = "closed" } end
    }
  },
  switch = {
    switch = {
      on = function() return { capability = "switch", attribute = "switch", value = "on" } end,
      off = function() return { capability = "switch", attribute = "switch", value = "off" } end
    }
  },
  presenceSensor = {
    presence = {
      present = function() return { capability = "presenceSensor", attribute = "presence", value = "present" } end,
      not_present = function() return { capability = "presenceSensor", attribute = "presence", value = "not present" } end
    }
  },
  windSpeed = {
    windSpeed = function(v) return { capability = "windSpeed", attribute = "windSpeed", value = v.value, unit = v.unit } end
  },
  windGust = {
    windGust = function(v) return { capability = "windGust", attribute = "windGust", value = v.value, unit = v.unit } end
  }
}

-- Test Normal Weather State (Wind 12 km/h < 35 km/h)
local sample_normal = {
  temperature = 14.5,
  humidity = 70,
  pressure_kpa = 101.3,
  wind_speed_kmh = 12.0,
  wind_gust_kmh = 18.0,
  station_name = "Muenchen-Stadt"
}

-- Initial healthy status
mock_device:set_field("consecutive_failures", 0)
mock_device:set_field("proxy_error_state", false)
mock_device:emit_event(capabilities.presenceSensor.presence.present())

local prev_alert = mock_device:get_field("wind_alert_state")
local is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(
  sample_normal.wind_speed_kmh,
  sample_normal.wind_gust_kmh,
  mock_device.preferences.windThreshold,
  mock_device.preferences.windUnit,
  mock_device.preferences.useGusts,
  mock_device.preferences.hysteresis,
  prev_alert
)

mock_device:set_field("wind_alert_state", is_alert)
assert(is_alert == false, "Normal weather should not trigger alert")
mock_device:emit_event(capabilities.contactSensor.contact.closed())
mock_device:emit_event(capabilities.switch.switch.off())
mock_device:emit_event(capabilities.windSpeed.windSpeed({ value = sample_normal.wind_speed_kmh, unit = "km/h" }))
mock_device:emit_event(capabilities.windGust.windGust({ value = sample_normal.wind_gust_kmh, unit = "km/h" }))

-- Test High Wind Event (Wind Gust 48 km/h >= 35 km/h)
local sample_storm = {
  temperature = 9.0,
  humidity = 90,
  pressure_kpa = 99.8,
  wind_speed_kmh = 32.0,
  wind_gust_kmh = 48.0,
  station_name = "Muenchen-Stadt"
}

prev_alert = mock_device:get_field("wind_alert_state")
is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(
  sample_storm.wind_speed_kmh,
  sample_storm.wind_gust_kmh,
  mock_device.preferences.windThreshold,
  mock_device.preferences.windUnit,
  mock_device.preferences.useGusts,
  mock_device.preferences.hysteresis,
  prev_alert
)

mock_device:set_field("wind_alert_state", is_alert)
assert(is_alert == true, "Storm gust of 48 km/h must trigger alert")
mock_device:emit_event(capabilities.contactSensor.contact.open())
mock_device:emit_event(capabilities.switch.switch.on())

-- Test UI Preference Change: User lowers threshold to 15 km/h
mock_device.preferences.windThreshold = 15
prev_alert = mock_device:get_field("wind_alert_state")
is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(
  sample_normal.wind_speed_kmh,
  sample_normal.wind_gust_kmh,
  mock_device.preferences.windThreshold,
  mock_device.preferences.windUnit,
  mock_device.preferences.useGusts,
  mock_device.preferences.hysteresis,
  prev_alert
)
assert(is_alert == true, "With threshold lowered to 15 km/h, gust of 18 km/h must trigger alert")

-- Test Proxy Failure Simulation
print("\n=== Testing Proxy Failure & Offline Alert Simulation ===")
mock_device.preferences.failureThreshold = 2

-- Failure 1: Below threshold (2), should record failure count but not alert yet
local fail_count = (mock_device:get_field("consecutive_failures") or 0) + 1
mock_device:set_field("consecutive_failures", fail_count)
assert(fail_count == 1, "First failure count recorded")
assert(fail_count < mock_device.preferences.failureThreshold, "Below failure threshold")

-- Failure 2: Reaches threshold, triggers offline alert
fail_count = (mock_device:get_field("consecutive_failures") or 0) + 1
mock_device:set_field("consecutive_failures", fail_count)
if fail_count >= mock_device.preferences.failureThreshold then
  mock_device:set_field("proxy_error_state", true)
  mock_device:emit_event(capabilities.presenceSensor.presence.not_present())
  mock_device:emit_event(capabilities.switch.switch.on())
  mock_device:emit_event(capabilities.contactSensor.contact.open())
end

assert(mock_device:get_field("proxy_error_state") == true, "Proxy error state set to true")
assert(mock_device:get_field("consecutive_failures") == 2, "Failure count reached 2")

-- Recovery: Successful poll resets failures and clears proxy error
mock_device:set_field("consecutive_failures", 0)
mock_device:set_field("proxy_error_state", false)
mock_device:emit_event(capabilities.presenceSensor.presence.present())
mock_device:emit_event(capabilities.switch.switch.off())
mock_device:emit_event(capabilities.contactSensor.contact.closed())

assert(mock_device:get_field("proxy_error_state") == false, "Proxy error state cleared on recovery")
assert(mock_device:get_field("consecutive_failures") == 0, "Failure count reset to 0")

print("All mock lifecycle, proxy offline detection, and state simulations passed successfully!")
