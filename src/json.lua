local json = {}

local has_st_json, st_json = pcall(require, "st.json")
if has_st_json and st_json and st_json.decode then
  return st_json
end

local has_dkjson, dkjson = pcall(require, "dkjson")
if has_dkjson and dkjson and dkjson.decode then
  return dkjson
end

local has_lunajson, lunajson = pcall(require, "lunajson")
if has_lunajson and lunajson and lunajson.decode then
  return lunajson
end

-- Pure Lua JSON Parser Fallback
local function kind_of(obj)
  if type(obj) ~= "table" then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then i = i + 1 else return "table" end
  end
  if i == 1 then return "table" else return "array" end
end

local function escape_str(s)
  local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
  local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
  for i, c in ipairs(in_char) do
    s = s:gsub(c, '\\' .. out_char[i])
  end
  return s
end

local function skip_whitespace(str, pos)
  while pos <= #str do
    local c = str:sub(pos, pos)
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      pos = pos + 1
    else
      break
    end
  end
  return pos
end

local parse_value

local function parse_string(str, pos)
  pos = pos + 1 -- skip opening quote
  local result = {}
  while pos <= #str do
    local c = str:sub(pos, pos)
    if c == '"' then
      return table.concat(result), pos + 1
    elseif c == '\\' then
      local n = str:sub(pos + 1, pos + 1)
      if n == '"' or n == '\\' or n == '/' then
        table.insert(result, n)
        pos = pos + 2
      elseif n == 'b' then table.insert(result, '\b'); pos = pos + 2
      elseif n == 'f' then table.insert(result, '\f'); pos = pos + 2
      elseif n == 'n' then table.insert(result, '\n'); pos = pos + 2
      elseif n == 'r' then table.insert(result, '\r'); pos = pos + 2
      elseif n == 't' then table.insert(result, '\t'); pos = pos + 2
      elseif n == 'u' then
        local hex = str:sub(pos + 2, pos + 5)
        local code = tonumber(hex, 16) or 63
        if code < 128 then
          table.insert(result, string.char(code))
        else
          table.insert(result, "?")
        end
        pos = pos + 6
      else
        table.insert(result, n)
        pos = pos + 2
      end
    else
      table.insert(result, c)
      pos = pos + 1
    end
  end
  error("Unterminated string in JSON at " .. pos)
end

local function parse_number(str, pos)
  local num_str = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
  if not num_str or num_str == "" then
    error("Invalid number in JSON at " .. pos)
  end
  return tonumber(num_str), pos + #num_str
end

local function parse_array(str, pos)
  pos = pos + 1 -- skip '['
  local arr = {}
  pos = skip_whitespace(str, pos)
  if str:sub(pos, pos) == ']' then
    return arr, pos + 1
  end
  while pos <= #str do
    local val
    val, pos = parse_value(str, pos)
    table.insert(arr, val)
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == ']' then
      return arr, pos + 1
    elseif c == ',' then
      pos = skip_whitespace(str, pos + 1)
    else
      error("Expected ']' or ',' in array at " .. pos)
    end
  end
  error("Unterminated array at " .. pos)
end

local function parse_object(str, pos)
  pos = pos + 1 -- skip '{'
  local obj = {}
  pos = skip_whitespace(str, pos)
  if str:sub(pos, pos) == '}' then
    return obj, pos + 1
  end
  while pos <= #str do
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) ~= '"' then
      error("Expected string key in object at " .. pos)
    end
    local key
    key, pos = parse_string(str, pos)
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) ~= ':' then
      error("Expected ':' after key in object at " .. pos)
    end
    pos = skip_whitespace(str, pos + 1)
    local val
    val, pos = parse_value(str, pos)
    obj[key] = val
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == '}' then
      return obj, pos + 1
    elseif c == ',' then
      pos = skip_whitespace(str, pos + 1)
    else
      error("Expected '}' or ',' in object at " .. pos)
    end
  end
  error("Unterminated object at " .. pos)
end

parse_value = function(str, pos)
  pos = skip_whitespace(str, pos)
  local c = str:sub(pos, pos)
  if c == '{' then
    return parse_object(str, pos)
  elseif c == '[' then
    return parse_array(str, pos)
  elseif c == '"' then
    return parse_string(str, pos)
  elseif c == 't' and str:sub(pos, pos + 3) == "true" then
    return true, pos + 4
  elseif c == 'f' and str:sub(pos, pos + 4) == "false" then
    return false, pos + 5
  elseif c == 'n' and str:sub(pos, pos + 3) == "null" then
    return nil, pos + 4
  elseif c:match("[%-%d]") then
    return parse_number(str, pos)
  else
    error("Unexpected character '" .. c .. "' in JSON at " .. pos)
  end
end

function json.decode(str)
  if not str or type(str) ~= "string" then return nil, "Invalid input" end
  local ok, res = pcall(function()
    local val, _ = parse_value(str, 1)
    return val
  end)
  if ok then
    return res, nil
  else
    return nil, res
  end
end

function json.encode(val)
  local t = type(val)
  if t == "nil" then
    return "null"
  elseif t == "boolean" or t == "number" then
    return tostring(val)
  elseif t == "string" then
    return '"' .. escape_str(val) .. '"'
  elseif t == "table" then
    local k = kind_of(val)
    local parts = {}
    if k == "array" then
      for _, v in ipairs(val) do
        table.insert(parts, json.encode(v))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k2, v in pairs(val) do
        table.insert(parts, '"' .. escape_str(tostring(k2)) .. '":' .. json.encode(v))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    return '"' .. tostring(val) .. '"'
  end
end

return json
