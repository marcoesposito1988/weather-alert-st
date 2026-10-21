local json = require("json")
local log = pcall(require, "log") and require("log") or {
  info = function(...) print("[INFO]", ...) end,
  warn = function(...) print("[WARN]", ...) end,
  error = function(...) print("[ERROR]", ...) end,
  debug = function(...) print("[DEBUG]", ...) end
}

local weather_service = {}

-- Munich coordinates & DWD stations
local MUNICH_CITY = {
  lat = 48.137154,
  lon = 11.576124,
  station_id = "03379",
  name = "Munich City Center (DWD 03379 / 10865)"
}

local MUNICH_AIRPORT = {
  lat = 48.3537,
  lon = 11.7860,
  station_id = "01262",
  name = "Munich Airport (DWD 01262 / 10870)"
}

--- Resolve location settings from device preferences
function weather_service.resolve_location(preferences)
  preferences = preferences or {}
  local mode = preferences.locationMode or "munich_city"

  if mode == "munich_airport" then
    return MUNICH_AIRPORT
  elseif mode == "coords" then
    local lat = tonumber(preferences.latitude) or MUNICH_CITY.lat
    local lon = tonumber(preferences.longitude) or MUNICH_CITY.lon
    return {
      lat = lat,
      lon = lon,
      name = string.format("Custom (%.4f, %.4f)", lat, lon)
    }
  elseif mode == "station" then
    local st_id = preferences.stationId or MUNICH_CITY.station_id
    return {
      lat = MUNICH_CITY.lat,
      lon = MUNICH_CITY.lon,
      station_id = st_id,
      name = "DWD Station " .. st_id
    }
  else
    return MUNICH_CITY
  end
end

--- Build request URL for weather polling
function weather_service.build_url(location, preferences)
  preferences = preferences or {}
  local custom = preferences.customEndpoint
  if custom and type(custom) == "string" and custom:match("%S") then
    custom = custom:match("^%s*(.-)%s*$")
    if custom:find("?") then
      return custom
    else
      local lat = location.lat or MUNICH_CITY.lat
      local lon = location.lon or MUNICH_CITY.lon
      local separator = custom:sub(-1) == "/" and "" or "/"
      return string.format("%s%scurrent_weather?lat=%.6f&lon=%.6f", custom, separator, lat, lon)
    end
  end

  local source = preferences.weatherSource or "brightsky"

  if source == "openmeteo" then
    local lat = location.lat or MUNICH_CITY.lat
    local lon = location.lon or MUNICH_CITY.lon
    return string.format(
      "http://api.open-meteo.com/v1/dwd-icon?latitude=%.6f&longitude=%.6f&current=temperature_2m,relative_humidity_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m,surface_pressure",
      lat, lon
    )
  else
    -- Default: Bright Sky DWD API
    if location.station_id and preferences.locationMode == "station" then
      return string.format("http://api.brightsky.dev/current_weather?dwd_station_id=%s", location.station_id)
    else
      local lat = location.lat or MUNICH_CITY.lat
      local lon = location.lon or MUNICH_CITY.lon
      return string.format("http://api.brightsky.dev/current_weather?lat=%.6f&lon=%.6f", lat, lon)
    end
  end
end

--- Parse Bright Sky response JSON
function weather_service.parse_brightsky_response(body_str)
  local data, err = json.decode(body_str)
  if not data or not data.weather then
    return nil, err or "Invalid Bright Sky response format"
  end

  local w = data.weather
  local source = (data.sources and data.sources[1]) or {}

  -- Wind speed fallbacks: prefer wind_speed_10, then 30, 60, or general wind_speed
  local wind_speed = w.wind_speed_10 or w.wind_speed_30 or w.wind_speed_60 or w.wind_speed or 0
  local wind_gust = w.wind_gust_speed_10 or w.wind_gust_speed_30 or w.wind_gust_speed_60 or w.wind_gust_speed or wind_speed
  local wind_dir = w.wind_direction_10 or w.wind_direction_30 or w.wind_direction_60 or w.wind_direction or 0
  local pressure_hpa = w.pressure_msl or 1013.25
  local pressure_kpa = pressure_hpa / 10.0 -- 1 kPa = 10 hPa

  return {
    temperature = tonumber(w.temperature) or 0,
    humidity = tonumber(w.relative_humidity) or 0,
    pressure_hpa = pressure_hpa,
    pressure_kpa = pressure_kpa,
    wind_speed_kmh = tonumber(wind_speed) or 0,
    wind_gust_kmh = tonumber(wind_gust) or 0,
    wind_direction = tonumber(wind_dir) or 0,
    condition = w.condition or "unknown",
    icon = w.icon or "unknown",
    timestamp = w.timestamp or os.date("!%Y-%m-%dT%H:%M:%SZ"),
    station_name = source.station_name or "DWD Station",
    station_id = source.dwd_station_id or "unknown",
    provider = "DWD Bright Sky"
  }
end

--- Parse Open-Meteo DWD ICON response JSON
function weather_service.parse_openmeteo_response(body_str)
  local data, err = json.decode(body_str)
  if not data or not data.current then
    return nil, err or "Invalid Open-Meteo response format"
  end

  local c = data.current
  local pressure_hpa = c.surface_pressure or 1013.25
  local pressure_kpa = pressure_hpa / 10.0
  local wind_speed = c.wind_speed_10m or 0
  local wind_gust = c.wind_gusts_10m or wind_speed

  return {
    temperature = tonumber(c.temperature_2m) or 0,
    humidity = tonumber(c.relative_humidity_2m) or 0,
    pressure_hpa = pressure_hpa,
    pressure_kpa = pressure_kpa,
    wind_speed_kmh = tonumber(wind_speed) or 0,
    wind_gust_kmh = tonumber(wind_gust) or 0,
    wind_direction = tonumber(c.wind_direction_10m) or 0,
    condition = "dwd_icon",
    icon = "weather",
    timestamp = c.time or os.date("!%Y-%m-%dT%H:%M:%SZ"),
    station_name = string.format("DWD ICON (%.2f, %.2f)", data.latitude or 0, data.longitude or 0),
    station_id = "DWD-ICON",
    provider = "Open-Meteo DWD ICON"
  }
end

--- Execute HTTP GET request using cosock / socket.http / ssl.https
function weather_service.http_get(url)
  local has_cosock, cosock = pcall(require, "cosock")
  local https
  local http
  local ltn12 = require("ltn12")

  if has_cosock and cosock then
    if cosock.asyncify then
      local ok_http, a_http = pcall(cosock.asyncify, "socket.http")
      if ok_http and a_http then
        http = a_http
      end
      local ok_ssl, a_ssl = pcall(cosock.asyncify, "ssl.https")
      if ok_ssl and a_ssl then
        https = a_ssl
      end
    end
    if not http and cosock.require then
      local has_http, cosock_http = pcall(cosock.require, "socket.http")
      if has_http and cosock_http then
        http = cosock_http
      end
    end
    if not https and cosock.require then
      local has_ssl, cosock_ssl = pcall(cosock.require, "ssl.https")
      if has_ssl and cosock_ssl then
        https = cosock_ssl
      end
    end
  end

  if not http then
    local has_raw_http, raw_http = pcall(require, "socket.http")
    if has_raw_http and raw_http then
      http = raw_http
    end
  end

  if not https then
    local has_ssl, raw_ssl = pcall(require, "ssl.https")
    if has_ssl and raw_ssl then
      https = raw_ssl
    end
  end

  if not http and not https then
    return nil, "No HTTP/HTTPS client available"
  end

  local is_https = url:match("^https://") ~= nil

  -- Helper to perform a single request safely wrapped in pcall
  local function do_request(client_module, target_url)
    local response_chunks = {}
    local req = {
      url = target_url,
      method = "GET",
      headers = {
        ["User-Agent"] = "SmartThings-Edge-DWD-Weather/1.0",
        ["Accept"] = "application/json"
      },
      sink = ltn12.sink.table(response_chunks),
      timeout = 15,
      create = function()
        if has_cosock and cosock and cosock.socket and cosock.socket.tcp then
          local sock = cosock.socket.tcp()
          if sock and sock.settimeout then
            sock:settimeout(15)
          end
          return sock
        end
        local has_socket, socket = pcall(require, "socket")
        if has_socket and socket and socket.tcp then
          local sock = socket.tcp()
          if sock and sock.settimeout then
            sock:settimeout(15)
          end
          return sock
        end
      end
    }

    local ok, code, status_or_headers, headers = pcall(client_module.request, req)
    if not ok then
      return nil, tostring(code) -- code contains error message when pcall fails
    end

    if not code then
      return nil, tostring(status_or_headers or "Connection failed")
    end

    local status_code = tonumber(status_or_headers) or tonumber(code) or 0
    local body = table.concat(response_chunks)
    return body, status_code
  end

  local body, status_or_err
  if is_https then
    if https then
      body, status_or_err = do_request(https, url)
    end
    -- Fallback to plain HTTP if HTTPS failed or ssl client was unavailable
    if not body and http then
      local fallback_url = url:gsub("^https://", "http://")
      body, status_or_err = do_request(http, fallback_url)
    end
  else
    -- Plain HTTP request: always use socket.http
    if http then
      body, status_or_err = do_request(http, url)
    elseif https then
      -- Fallback only if socket.http was completely absent
      body, status_or_err = do_request(https, url)
    end
  end

  if not body then
    return nil, string.format("Network/socket error: %s", tostring(status_or_err or "Unknown error"))
  end

  local status_code = tonumber(status_or_err) or 0
  if status_code >= 200 and status_code < 300 then
    return body, status_code
  else
    return nil, string.format("HTTP error %s: %s", tostring(status_code), body:sub(1, 100))
  end
end

--- Fetch weather data based on current preferences
-- @param preferences table: device preferences
-- @return table weather_data, or nil, error_message
function weather_service.fetch_weather(preferences)
  local location = weather_service.resolve_location(preferences)
  local url = weather_service.build_url(location, preferences)
  local source = (preferences and preferences.weatherSource) or "brightsky"

  log.info(string.format("Fetching weather from %s for %s (%s)", source, location.name, url))

  local body, err = weather_service.http_get(url)
  if not body then
    log.error(string.format("Weather fetch failed: %s", tostring(err)))
    return nil, err
  end

  local result, parse_err
  if source == "openmeteo" then
    result, parse_err = weather_service.parse_openmeteo_response(body)
  else
    result, parse_err = weather_service.parse_brightsky_response(body)
  end

  if not result then
    log.error(string.format("Failed to parse weather payload: %s", tostring(parse_err)))
    return nil, parse_err
  end

  return result, nil
end

return weather_service
