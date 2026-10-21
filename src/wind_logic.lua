local wind_logic = {}

-- Beaufort scale conversion table (DWD / WMO standard in km/h)
local BEAUFORT_TABLE = {
  { bft = 0,  min_kmh = 0.0,   max_kmh = 1.0,   label = "Calm",             de = "Windstille" },
  { bft = 1,  min_kmh = 1.1,   max_kmh = 5.5,   label = "Light air",         de = "Leiser Zug" },
  { bft = 2,  min_kmh = 5.6,   max_kmh = 11.9,  label = "Light breeze",      de = "Leichte Brise" },
  { bft = 3,  min_kmh = 12.0,  max_kmh = 19.9,  label = "Gentle breeze",     de = "Schwache Brise" },
  { bft = 4,  min_kmh = 20.0,  max_kmh = 28.9,  label = "Moderate breeze",   de = "Mäßige Brise" },
  { bft = 5,  min_kmh = 29.0,  max_kmh = 38.9,  label = "Fresh breeze",      de = "Frische Brise" },
  { bft = 6,  min_kmh = 39.0,  max_kmh = 49.9,  label = "Strong breeze",     de = "Starker Wind" },
  { bft = 7,  min_kmh = 50.0,  max_kmh = 61.9,  label = "Near gale",         de = "Steifer Wind" },
  { bft = 8,  min_kmh = 62.0,  max_kmh = 74.9,  label = "Gale",              de = "Stürmischer Wind" },
  { bft = 9,  min_kmh = 75.0,  max_kmh = 88.9,  label = "Strong gale",       de = "Sturm" },
  { bft = 10, min_kmh = 89.0,  max_kmh = 102.9, label = "Storm",             de = "Schwerer Sturm" },
  { bft = 11, min_kmh = 103.0, max_kmh = 117.9, label = "Violent storm",     de = "Orkanartiger Sturm" },
  { bft = 12, min_kmh = 118.0, max_kmh = 999.0, label = "Hurricane force",   de = "Orkan" },
}

--- Convert km/h to Beaufort number
function wind_logic.kmh_to_beaufort(kmh)
  if not kmh or kmh < 0 then return 0 end
  for _, item in ipairs(BEAUFORT_TABLE) do
    if kmh <= item.max_kmh then
      return item.bft, item.label, item.de
    end
  end
  return 12, "Hurricane force", "Orkan"
end

--- Convert Beaufort level (0-12) to minimum km/h threshold
function wind_logic.beaufort_to_kmh(bft)
  bft = tonumber(bft) or 0
  if bft <= 0 then return 0.0 end
  if bft >= 12 then return 118.0 end
  for _, item in ipairs(BEAUFORT_TABLE) do
    if item.bft == bft then
      return item.min_kmh
    end
  end
  return 39.0 -- default to Bft 6
end

--- Convert value from specified unit to km/h
-- @param value number: the threshold or wind value
-- @param unit string: "kmh", "ms", or "beaufort"
-- @return number: value in km/h
function wind_logic.to_kmh(value, unit)
  value = tonumber(value) or 0
  unit = unit or "kmh"
  if unit == "ms" then
    return value * 3.6
  elseif unit == "beaufort" or unit == "bft" then
    return wind_logic.beaufort_to_kmh(value)
  else
    return value
  end
end

--- Convert km/h to m/s
function wind_logic.kmh_to_ms(kmh)
  return (tonumber(kmh) or 0) / 3.6
end

--- Evaluate wind threshold alert
-- @param current_wind_kmh number: sustained wind speed in km/h
-- @param gust_kmh number: wind gust speed in km/h (optional)
-- @param threshold_val number: threshold configured by user
-- @param threshold_unit string: unit of threshold ("kmh", "ms", "beaufort")
-- @param use_gusts boolean: whether to consider wind gusts for alerting
-- @param hysteresis_pct number: percentage of threshold (e.g. 80) below which alert clears
-- @param previous_alert_state boolean: last alert status (true = alert active / blinds closed)
-- @return boolean is_alert, number effective_wind_kmh, number threshold_kmh, number reset_threshold_kmh
function wind_logic.evaluate_alert(current_wind_kmh, gust_kmh, threshold_val, threshold_unit, use_gusts, hysteresis_pct, previous_alert_state)
  current_wind_kmh = tonumber(current_wind_kmh) or 0
  gust_kmh = tonumber(gust_kmh) or 0
  hysteresis_pct = tonumber(hysteresis_pct) or 80
  if hysteresis_pct < 50 then hysteresis_pct = 50 end
  if hysteresis_pct > 100 then hysteresis_pct = 100 end

  local threshold_kmh = wind_logic.to_kmh(threshold_val or 35, threshold_unit)
  local reset_threshold_kmh = threshold_kmh * (hysteresis_pct / 100.0)

  local effective_wind_kmh = current_wind_kmh
  if use_gusts and gust_kmh > current_wind_kmh then
    effective_wind_kmh = gust_kmh
  end

  local is_alert
  if effective_wind_kmh >= threshold_kmh then
    is_alert = true
  elseif effective_wind_kmh < reset_threshold_kmh then
    is_alert = false
  else
    -- In hysteresis deadband: maintain previous state
    is_alert = (previous_alert_state == true)
  end

  return is_alert, effective_wind_kmh, threshold_kmh, reset_threshold_kmh
end

return wind_logic
