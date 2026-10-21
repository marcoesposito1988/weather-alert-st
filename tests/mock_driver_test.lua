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

print("All mock lifecycle and state simulations passed successfully!")
