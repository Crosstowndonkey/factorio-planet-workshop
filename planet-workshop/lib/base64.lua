-- Base64 decoding (and encoding, for tests) in plain Lua.
-- The data stage has no helpers.decode_string, so planet codes are unpacked by hand.
-- Characters outside the base64 alphabet (spaces, line breaks) are skipped.

local M = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #ALPHABET do
  VALUE[ALPHABET:byte(i)] = i - 1
end

local floor, char, byte, concat = math.floor, string.char, string.byte, table.concat

--- Decodes base64 text into a byte string. Errors on text that can't be base64.
function M.decode(text)
  local out, n = {}, 0
  local acc, bits = 0, 0
  for i = 1, #text do
    local b = byte(text, i)
    local v = VALUE[b]
    if v then
      acc = acc * 64 + v
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        local p = 2 ^ bits
        local octet = floor(acc / p)
        acc = acc - octet * p
        n = n + 1
        out[n] = octet
      end
    elseif b == 61 then -- "=" padding: the end
      break
    elseif b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13 then
      error("not a valid code (bad character)", 0)
    end
  end
  local parts = {}
  for i = 1, n, 4096 do
    parts[#parts + 1] = char(table.unpack(out, i, math.min(i + 4095, n)))
  end
  return concat(parts)
end

--- Encodes a byte string as base64 (only used by the tests).
function M.encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = byte(data, i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = floor(v / 262144) % 64
    local c2 = floor(v / 4096) % 64
    local c3 = floor(v / 64) % 64
    local c4 = v % 64
    out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1) ..
      (b and ALPHABET:sub(c3 + 1, c3 + 1) or "=") .. (c and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
  end
  return concat(out)
end

return M
