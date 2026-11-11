-- A small, strict JSON reader in plain Lua (the data stage has no helpers.json_to_table).
-- Planet codes are shared between players, so they are only ever read as data: this never runs code.
-- Objects become tables with string keys, arrays become lists (1, 2, 3...), null becomes nil.

local M = {}

M.MAX_DEPTH = 40

local byte, sub, char, find = string.byte, string.sub, string.char, string.find
local floor = math.floor

local ESCAPES = {[34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t"}

local function fail(pos, what)
  error("the planet data is broken (" .. what .. " at " .. pos .. ")", 0)
end

local function skip(s, pos)
  local _, e = find(s, "^[ \t\r\n]*", pos)
  return e + 1
end

local function utf8(code)
  if code < 0x80 then return char(code) end
  if code < 0x800 then return char(0xC0 + floor(code / 64), 0x80 + code % 64) end
  if code < 0x10000 then
    return char(0xE0 + floor(code / 4096), 0x80 + floor(code / 64) % 64, 0x80 + code % 64)
  end
  return char(0xF0 + floor(code / 262144), 0x80 + floor(code / 4096) % 64, 0x80 + floor(code / 64) % 64, 0x80 + code % 64)
end

local value -- forward declaration

local function read_string(s, pos)
  -- pos is just after the opening quote
  local parts = {}
  while true do
    local a, b = find(s, '^[^"\\%c]+', pos)
    if a then
      parts[#parts + 1] = sub(s, a, b)
      pos = b + 1
    end
    local c = byte(s, pos)
    if c == 34 then
      return table.concat(parts), pos + 1
    elseif c == 92 then
      local e = byte(s, pos + 1)
      if e == 117 then -- \uXXXX
        local hex = sub(s, pos + 2, pos + 5)
        if not find(hex, "^%x%x%x%x$") then fail(pos, "bad \\u escape") end
        local code = tonumber(hex, 16)
        pos = pos + 6
        if code >= 0xD800 and code <= 0xDBFF and sub(s, pos, pos + 1) == "\\u" then
          local low = tonumber(sub(s, pos + 2, pos + 5), 16)
          if low and low >= 0xDC00 and low <= 0xDFFF then
            code = 0x10000 + (code - 0xD800) * 1024 + (low - 0xDC00)
            pos = pos + 6
          end
        end
        parts[#parts + 1] = utf8(code)
      elseif e and ESCAPES[e] then
        parts[#parts + 1] = ESCAPES[e]
        pos = pos + 2
      else
        fail(pos, "bad escape")
      end
    else
      fail(pos, "unfinished text")
    end
  end
end

local function read_number(s, pos)
  local a, b = find(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
  if not a then fail(pos, "bad number") end
  local n = tonumber(sub(s, a, b))
  if not n or n ~= n or n == math.huge or n == -math.huge then fail(pos, "bad number") end
  return n, b + 1
end

value = function(s, pos, depth)
  if depth > M.MAX_DEPTH then fail(pos, "too deeply nested") end
  pos = skip(s, pos)
  local c = byte(s, pos)
  if c == 123 then -- {
    local obj = {}
    pos = skip(s, pos + 1)
    if byte(s, pos) == 125 then return obj, pos + 1 end
    while true do
      if byte(s, pos) ~= 34 then fail(pos, "expected a name") end
      local key
      key, pos = read_string(s, pos + 1)
      pos = skip(s, pos)
      if byte(s, pos) ~= 58 then fail(pos, "expected ':'") end
      local v
      v, pos = value(s, pos + 1, depth + 1)
      obj[key] = v
      pos = skip(s, pos)
      c = byte(s, pos)
      if c == 125 then return obj, pos + 1 end
      if c ~= 44 then fail(pos, "expected ',' or '}'") end
      pos = skip(s, pos + 1)
    end
  elseif c == 91 then -- [
    local arr, n = {}, 0
    pos = skip(s, pos + 1)
    if byte(s, pos) == 93 then return arr, pos + 1 end
    while true do
      local v
      v, pos = value(s, pos, depth + 1)
      n = n + 1
      arr[n] = v
      pos = skip(s, pos)
      c = byte(s, pos)
      if c == 93 then return arr, pos + 1 end
      if c ~= 44 then fail(pos, "expected ',' or ']'") end
      pos = pos + 1
    end
  elseif c == 34 then
    return read_string(s, pos + 1)
  elseif c == 116 and sub(s, pos, pos + 3) == "true" then
    return true, pos + 4
  elseif c == 102 and sub(s, pos, pos + 4) == "false" then
    return false, pos + 5
  elseif c == 110 and sub(s, pos, pos + 3) == "null" then
    return nil, pos + 4
  elseif c == 45 or (c and c >= 48 and c <= 57) then
    return read_number(s, pos)
  end
  fail(pos, "unexpected character")
end

--- Reads JSON text into a Lua value. Errors (with a short message) on anything that isn't valid JSON.
function M.decode(s)
  if type(s) ~= "string" then error("the planet data is missing", 0) end
  local v, pos = value(s, 1, 0)
  pos = skip(s, pos)
  if pos <= #s then fail(pos, "extra text after the data") end
  return v
end

return M
