-- Set package path to include src/
package.path = "./src/?.lua;" .. package.path

local json = require("json")
local wind_logic = require("wind_logic")
local weather_service = require("weather_service")

local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, test_name)
  if actual == expected then
    pass_count = pass_count + 1
    print("  [PASS] " .. test_name)
  else
    fail_count = fail_count + 1
    print(string.format("  [FAIL] %s - Expected: %s, Got: %s", test_name, tostring(expected), tostring(actual)))
  end
end

local function assert_almost_eq(actual, expected, eps, test_name)
  eps = eps or 0.01
  if math.abs((actual or 0) - (expected or 0)) < eps then
    pass_count = pass_count + 1
    print("  [PASS] " .. test_name)
  else
    fail_count = fail_count + 1
    print(string.format("  [FAIL] %s - Expected: %s, Got: %s", test_name, tostring(expected), tostring(actual)))
  end
end

print("=== 1. Testing JSON parser ===")
local sample_json = '{"weather":{"temperature":11.5,"relative_humidity":82,"wind_speed_10":9.7,"wind_gust_speed_10":18.0},"sources":[{"station_name":"Muenchen-Stadt","dwd_station_id":"03379"}]}'
local parsed, json_err = json.decode(sample_json)
assert_eq(json_err, nil, "JSON decode error is nil")
assert_eq(parsed ~= nil, true, "JSON parsed successfully")
assert_almost_eq(parsed.weather.temperature, 11.5, 0.01, "Parsed temperature")
assert_eq(parsed.weather.relative_humidity, 82, "Parsed relative_humidity")
assert_eq(parsed.sources[1].station_name, "Muenchen-Stadt", "Parsed station_name")

local encoded = json.encode({ a = 1, b = "test", c = true })
local re_decoded = json.decode(encoded)
assert_eq(re_decoded.a, 1, "Roundtrip JSON encode/decode number")
assert_eq(re_decoded.b, "test", "Roundtrip JSON encode/decode string")
assert_eq(re_decoded.c, true, "Roundtrip JSON encode/decode boolean")

print("\n=== 2. Testing Wind Logic & Beaufort scale ===")
local bft0, _ = wind_logic.kmh_to_beaufort(0.5)
assert_eq(bft0, 0, "0.5 km/h is Bft 0")

local bft5, label5 = wind_logic.kmh_to_beaufort(35)
assert_eq(bft5, 5, "35 km/h is Bft 5")
assert_eq(label5, "Fresh breeze", "Bft 5 label is Fresh breeze")

local bft6, label6 = wind_logic.kmh_to_beaufort(45)
assert_eq(bft6, 6, "45 km/h is Bft 6")
assert_eq(label6, "Strong breeze", "Bft 6 label is Strong breeze")

local bft8, _ = wind_logic.kmh_to_beaufort(70)
assert_eq(bft8, 8, "70 km/h is Bft 8")

assert_almost_eq(wind_logic.to_kmh(10, "ms"), 36.0, 0.01, "10 m/s = 36 km/h")
assert_almost_eq(wind_logic.to_kmh(6, "beaufort"), 39.0, 0.01, "Bft 6 threshold = 39 km/h")
assert_almost_eq(wind_logic.to_kmh(40, "kmh"), 40.0, 0.01, "40 km/h = 40 km/h")

print("\n=== 3. Testing Wind Alert & Hysteresis Evaluation ===")
-- Case A: Low wind (20 km/h), threshold 35 km/h -> Safe (alert false)
local is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(20, 25, 35, "kmh", true, 80, false)
assert_eq(is_alert, false, "25 km/h gust < 35 km/h threshold -> No alert")
assert_almost_eq(eff_wind, 25, 0.01, "Effective wind = max(20, 25)")
assert_almost_eq(thresh, 35, 0.01, "Threshold = 35")
assert_almost_eq(r_thresh, 28, 0.01, "Reset threshold = 35 * 0.8 = 28")

-- Case B: High wind gusts (42 km/h), threshold 35 km/h -> High Wind Alert (true)
is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(25, 42, 35, "kmh", true, 80, false)
assert_eq(is_alert, true, "42 km/h gust >= 35 km/h threshold -> Trigger alert")

-- Case C: Gusts disabled, sustained 30 km/h, gust 45 km/h -> No alert
is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(30, 45, 35, "kmh", false, 80, false)
assert_eq(is_alert, false, "Gusts disabled: sustained 30 km/h < 35 km/h -> No alert")

-- Case D: In hysteresis deadband (30 km/h between 28 and 35) with previous alert = true -> Remains true
is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(30, 30, 35, "kmh", true, 80, true)
assert_eq(is_alert, true, "In deadband (30 km/h) with prev=true -> Stays in alert")

-- Case E: In hysteresis deadband (30 km/h between 28 and 35) with previous alert = false -> Remains false
is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(30, 30, 35, "kmh", true, 80, false)
assert_eq(is_alert, false, "In deadband (30 km/h) with prev=false -> Stays safe")

-- Case F: Dropped below reset threshold (22 km/h < 28 km/h) -> Alert clears
is_alert, eff_wind, thresh, r_thresh = wind_logic.evaluate_alert(22, 22, 35, "kmh", true, 80, true)
assert_eq(is_alert, false, "Dropped below reset threshold (22 < 28) -> Alert clears")

print("\n=== 4. Testing Weather Service Location & URL Building ===")
local munich_loc = weather_service.resolve_location({ locationMode = "munich_city" })
assert_almost_eq(munich_loc.lat, 48.137154, 0.0001, "Munich City latitude")
assert_almost_eq(munich_loc.lon, 11.576124, 0.0001, "Munich City longitude")
assert_eq(munich_loc.station_id, "03379", "Munich DWD station ID")

local bsky_url = weather_service.build_url(munich_loc, { weatherSource = "brightsky" })
assert_eq(string.find(bsky_url, "http://api.brightsky.dev", 1, true) ~= nil, true, "Bright Sky URL contains HTTP scheme and domain")
assert_eq(string.find(bsky_url, "lat=48.137154", 1, true) ~= nil, true, "Bright Sky URL contains lat")

local openmeteo_url = weather_service.build_url(munich_loc, { weatherSource = "openmeteo" })
assert_eq(string.find(openmeteo_url, "http://api.open-meteo.com/v1/dwd-icon", 1, true) ~= nil, true, "Open-Meteo DWD ICON URL contains HTTP endpoint")

local custom_proxy_url = weather_service.build_url(munich_loc, { customEndpoint = "http://192.168.1.50:8080" })
assert_eq(string.find(custom_proxy_url, "http://192.168.1.50:8080/current_weather?lat=48.137154", 1, true) ~= nil, true, "Custom LAN Proxy URL formatted properly")

local custom_full_url = weather_service.build_url(munich_loc, { customEndpoint = "http://192.168.1.50:8080/myweather?city=munich" })
assert_eq(custom_full_url, "http://192.168.1.50:8080/myweather?city=munich", "Direct query custom URL preserved exactly")

print("\n=== 5. Testing Weather Service Response Parsers ===")
local brightsky_payload = [[{
  "weather": {
    "source_id": 18377,
    "timestamp": "2026-10-21T09:30:00+00:00",
    "cloud_cover": 100,
    "condition": "dry",
    "pressure_msl": 1009.2,
    "relative_humidity": 82,
    "temperature": 11.5,
    "wind_direction_10": 300,
    "wind_speed_10": 9.7,
    "wind_gust_speed_10": 18.0,
    "icon": "cloudy"
  },
  "sources": [{
    "id": 18377,
    "dwd_station_id": "03379",
    "station_name": "Muenchen-Stadt"
  }]
}]]

local bsky_parsed, bsky_err = weather_service.parse_brightsky_response(brightsky_payload)
assert_eq(bsky_err, nil, "Bright Sky parse error is nil")
assert_almost_eq(bsky_parsed.temperature, 11.5, 0.01, "Parsed temperature = 11.5")
assert_eq(bsky_parsed.humidity, 82, "Parsed humidity = 82")
assert_almost_eq(bsky_parsed.pressure_kpa, 100.92, 0.01, "Parsed pressure_kpa = 100.92")
assert_almost_eq(bsky_parsed.wind_speed_kmh, 9.7, 0.01, "Parsed wind_speed = 9.7")
assert_almost_eq(bsky_parsed.wind_gust_kmh, 18.0, 0.01, "Parsed wind_gust = 18.0")
assert_eq(bsky_parsed.wind_direction, 300, "Parsed wind_direction = 300")
assert_eq(bsky_parsed.station_name, "Muenchen-Stadt", "Parsed station_name")
assert_eq(bsky_parsed.station_id, "03379", "Parsed station_id")

local openmeteo_payload = [[{
  "latitude": 48.12743,
  "longitude": 11.576928,
  "current": {
    "time": "2026-10-21T10:00",
    "temperature_2m": 11.0,
    "relative_humidity_2m": 84,
    "wind_speed_10m": 6.9,
    "wind_gusts_10m": 19.8,
    "wind_direction_10m": 298,
    "surface_pressure": 948.9
  }
}]]

local om_parsed, om_err = weather_service.parse_openmeteo_response(openmeteo_payload)
assert_eq(om_err, nil, "Open-Meteo parse error is nil")
assert_almost_eq(om_parsed.temperature, 11.0, 0.01, "Open-Meteo temperature = 11.0")
assert_eq(om_parsed.humidity, 84, "Open-Meteo humidity = 84")
assert_almost_eq(om_parsed.wind_speed_kmh, 6.9, 0.01, "Open-Meteo wind speed = 6.9")
assert_almost_eq(om_parsed.wind_gust_kmh, 19.8, 0.01, "Open-Meteo wind gust = 19.8")

print("\n=== 6. Testing HTTP GET Client Dispatching & Error Handling ===")
-- Test real or mocked http_get with HTTP url
local test_body, test_code = weather_service.http_get("http://api.brightsky.dev/current_weather?lat=48.137154&lon=11.576124")
if test_body then
  assert_eq(test_code, 200, "Live HTTP GET returned 200")
  local parsed_live, live_err = weather_service.parse_brightsky_response(test_body)
  assert_eq(live_err, nil, "Parsed live payload without error")
  assert_eq(type(parsed_live.temperature), "number", "Live payload has numeric temperature")
else
  print("  [SKIP] Live network fetch skipped or offline: " .. tostring(test_code))
end

-- Test error cases: invalid JSON / 404 / 500 error payload handling
local bad_json_res, bad_json_err = weather_service.parse_brightsky_response("<html>502 Bad Gateway</html>")
assert_eq(bad_json_res, nil, "Bad JSON returns nil result")
assert_eq(bad_json_err ~= nil, true, "Bad JSON returns descriptive error")

local empty_weather_res, empty_weather_err = weather_service.parse_brightsky_response('{"error": "not found"}')
assert_eq(empty_weather_res, nil, "Missing weather key returns nil result")
assert_eq(empty_weather_err ~= nil, true, "Missing weather key returns error")

print(string.format("\n=========================================="))
print(string.format("TEST RESULTS: %d Passed, %d Failed", pass_count, fail_count))
print(string.format("=========================================="))

if fail_count > 0 then
  os.exit(1)
end
