-- Inflate (zlib / DEFLATE decompression) in plain Lua, after Mark Adler's public-domain "puff.c".
-- The data stage has no helpers.decode_string, and planet codes are made at runtime with
-- helpers.encode_string (zlib + base64), so the loader unpacks them with this.
-- Every failure is an error() with a short message; callers wrap it in pcall.

local band, bor, lshift, rshift = bit32.band, bit32.bor, bit32.lshift, bit32.rshift
local byte, char, concat = string.byte, string.char, table.concat

local M = {}

local WINDOW, FLUSH_AT, flush -- (set below, before the decoders that use them)

--- Largest output allowed, so a broken or hostile code can't eat all memory.
M.MAX_OUTPUT = 8 * 1024 * 1024

local LBASE = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258}
local LEXT = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0}
local DBASE = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
  4097, 6145, 8193, 12289, 16385, 24577}
local DEXT = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13}
local ORDER = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}

-- A bit reader over the byte string (bits come least significant first).
local function reader(s, pos)
  return {s = s, pos = pos, len = #s, buf = 0, cnt = 0}
end

local function bits(r, n)
  if n == 0 then return 0 end
  local buf, cnt = r.buf, r.cnt
  while cnt < n do
    if r.pos > r.len then error("the code is cut short", 0) end
    buf = bor(buf, lshift(byte(r.s, r.pos), cnt))
    r.pos = r.pos + 1
    cnt = cnt + 8
  end
  r.buf = rshift(buf, n)
  r.cnt = cnt - n
  return band(buf, lshift(1, n) - 1)
end

-- Codes up to FAST bits long are found with one table lookup; longer (rare) codes are read bit by bit.
local FAST = 9
local FAST_MASK = 2 ^ FAST - 1

local function reverse(code, len)
  local r = 0
  for _ = 1, len do
    r = r * 2 + code % 2
    code = (code - code % 2) / 2
  end
  return r
end

-- Builds a canonical Huffman table from code lengths (lengths[0 .. n-1]).
-- count/symbol are for the bit-by-bit decoder; fast[peeked bits] = symbol * 16 + code length.
local function huffman(lengths, n)
  local count = {}
  for len = 0, 15 do count[len] = 0 end
  for s = 0, n - 1 do
    local len = lengths[s] or 0
    count[len] = count[len] + 1
  end
  local left = 1
  for len = 1, 15 do
    left = left * 2 - count[len]
    if left < 0 then error("the code is damaged (bad table)", 0) end
  end
  local offs = {[1] = 0}
  for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
  local symbol = {}
  for s = 0, n - 1 do
    local len = lengths[s] or 0
    if len ~= 0 then
      symbol[offs[len]] = s
      offs[len] = offs[len] + 1
    end
  end
  local next_code, code = {}, 0
  for len = 1, 15 do
    code = (code + (len > 1 and count[len - 1] or 0)) * 2
    next_code[len] = code
  end
  local fast = {}
  for s = 0, n - 1 do
    local len = lengths[s] or 0
    if len ~= 0 then
      local c = next_code[len] -- codes of one length count up from next_code (RFC 1951, 3.2.2)
      next_code[len] = c + 1
      if len <= FAST then
        local step = 2 ^ len
        for k = reverse(c, len), FAST_MASK, step do
          fast[k] = s * 16 + len
        end
      end
    end
  end
  return {count = count, symbol = symbol, fast = fast}
end

-- The bit-by-bit decoder (for codes longer than FAST bits, and near the end of the data).
local function decode(r, h)
  local code, first, index = 0, 0, 0
  local count = h.count
  for len = 1, 15 do
    code = bor(code, bits(r, 1))
    local c = count[len]
    if code - c < first then
      local s = h.symbol[index + (code - first)]
      if s == nil then break end
      return s
    end
    index = index + c
    first = (first + c) * 2
    code = code * 2
  end
  error("the code is damaged (bad symbol)", 0)
end

-- The output is kept in a small table: DEFLATE only ever copies from the last 32 KB, and Factorio's Lua
-- gets much slower with very big tables (filling one 1.5-million-entry table took 3.2 s, the same bytes in
-- 64K tables 0.25 s). When the table reaches FLUSH_AT, everything but the last WINDOW bytes becomes text.
WINDOW = 32768
FLUSH_AT = WINDOW + 65536

--- Turns out[1 .. upto] into text (adding it to the checksum) and moves the rest down to the start.
flush = function(out, upto)
  if upto <= 0 then return end
  local a, b = out.a, out.b
  local i = 1
  while i <= upto do
    local stop = math.min(i + 3799, upto) -- small enough that the sums can't lose precision
    for j = i, stop do
      a = a + out[j]
      b = b + a
    end
    a, b = a % 65521, b % 65521
    i = stop + 1
  end
  out.a, out.b = a, b
  local parts = out.parts
  for k = 1, upto, 4096 do
    parts[#parts + 1] = char(table.unpack(out, k, math.min(k + 4095, upto)))
  end
  local n = out.n
  for k = upto + 1, n do
    out[k - upto] = out[k]
  end
  out.n = n - upto
  out.flushed = out.flushed + upto
end

-- Decodes one compressed block. The bit reader's state is kept in locals here, because this loop does
-- nearly all the work.
local function emit_codes(r, out, lencode, distcode)
  local s, pos, last = r.s, r.pos, r.len
  local buf, cnt = r.buf, r.cnt
  local n = out.n
  local lfast, dfast = lencode.fast, distcode.fast
  local max = M.MAX_OUTPUT
  while true do
    while cnt < 16 and pos <= last do
      buf = buf + lshift(byte(s, pos), cnt)
      pos = pos + 1
      cnt = cnt + 8
    end
    local sym
    local e = lfast[band(buf, FAST_MASK)]
    if e and band(e, 15) <= cnt then
      local l = band(e, 15)
      buf = rshift(buf, l)
      cnt = cnt - l
      sym = rshift(e, 4)
    else
      r.pos, r.buf, r.cnt = pos, buf, cnt
      sym = decode(r, lencode)
      pos, buf, cnt = r.pos, r.buf, r.cnt
    end
    if sym < 256 then
      n = n + 1
      out[n] = sym
    elseif sym == 256 then
      break
    else
      sym = sym - 256
      if sym > 29 then error("the code is damaged (bad length)", 0) end
      local extra = LEXT[sym]
      while cnt < 16 and pos <= last do
        buf = buf + lshift(byte(s, pos), cnt)
        pos = pos + 1
        cnt = cnt + 8
      end
      if cnt < extra then error("the code is cut short", 0) end
      local len = LBASE[sym] + band(buf, lshift(1, extra) - 1)
      buf = rshift(buf, extra)
      cnt = cnt - extra
      while cnt < 16 and pos <= last do
        buf = buf + lshift(byte(s, pos), cnt)
        pos = pos + 1
        cnt = cnt + 8
      end
      local dsym
      e = dfast[band(buf, FAST_MASK)]
      if e and band(e, 15) <= cnt then
        local l = band(e, 15)
        buf = rshift(buf, l)
        cnt = cnt - l
        dsym = rshift(e, 4)
      else
        r.pos, r.buf, r.cnt = pos, buf, cnt
        dsym = decode(r, distcode)
        pos, buf, cnt = r.pos, r.buf, r.cnt
      end
      if dsym >= 30 then error("the code is damaged (bad distance)", 0) end
      extra = DEXT[dsym + 1]
      while cnt < 16 and pos <= last do
        buf = buf + lshift(byte(s, pos), cnt)
        pos = pos + 1
        cnt = cnt + 8
      end
      if cnt < extra then error("the code is cut short", 0) end
      local dist = DBASE[dsym + 1] + band(buf, lshift(1, extra) - 1)
      buf = rshift(buf, extra)
      cnt = cnt - extra
      if dist > n then error("the code is damaged (distance too far)", 0) end
      for i = n + 1, n + len do
        out[i] = out[i - dist]
      end
      n = n + len
    end
    if n >= FLUSH_AT then
      out.n = n
      flush(out, n - WINDOW)
      n = out.n
      if out.flushed + n > max then error("the code is too big", 0) end
    end
  end
  -- Give back whole bytes that were read ahead but not used (the next block or the checksum starts there).
  local unused = (cnt - cnt % 8) / 8
  pos = pos - unused
  cnt = cnt - unused * 8
  buf = band(buf, lshift(1, cnt) - 1)
  r.pos, r.buf, r.cnt = pos, buf, cnt
  out.n = n
end

local fixed_len, fixed_dist
local function fixed_tables()
  if not fixed_len then
    local l = {}
    for s = 0, 143 do l[s] = 8 end
    for s = 144, 255 do l[s] = 9 end
    for s = 256, 279 do l[s] = 7 end
    for s = 280, 287 do l[s] = 8 end
    fixed_len = huffman(l, 288)
    local d = {}
    for s = 0, 29 do d[s] = 5 end
    fixed_dist = huffman(d, 30)
  end
  return fixed_len, fixed_dist
end

local function dynamic_tables(r)
  local nlen = bits(r, 5) + 257
  local ndist = bits(r, 5) + 1
  local ncode = bits(r, 4) + 4
  if nlen > 286 or ndist > 30 then error("the code is damaged (bad counts)", 0) end
  local lengths = {}
  for i = 1, 19 do lengths[ORDER[i]] = 0 end
  for i = 1, ncode do lengths[ORDER[i]] = bits(r, 3) end
  local lencode = huffman(lengths, 19)
  local all = {}
  local index = 0
  while index < nlen + ndist do
    local sym = decode(r, lencode)
    if sym < 16 then
      all[index] = sym
      index = index + 1
    else
      local len, rep = 0, 0
      if sym == 16 then
        if index == 0 then error("the code is damaged (repeat at start)", 0) end
        len = all[index - 1]
        rep = 3 + bits(r, 2)
      elseif sym == 17 then
        rep = 3 + bits(r, 3)
      else
        rep = 11 + bits(r, 7)
      end
      if index + rep > nlen + ndist then error("the code is damaged (too many lengths)", 0) end
      for _ = 1, rep do
        all[index] = len
        index = index + 1
      end
    end
  end
  if (all[256] or 0) == 0 then error("the code is damaged (no end code)", 0) end
  local litlen = {}
  for i = 0, nlen - 1 do litlen[i] = all[i] end
  local dist = {}
  for i = 0, ndist - 1 do dist[i] = all[nlen + i] end
  return huffman(litlen, nlen), huffman(dist, ndist)
end

local function stored(r, out)
  r.buf, r.cnt = 0, 0 -- skip to the next whole byte
  local s, pos = r.s, r.pos
  if pos + 3 > r.len then error("the code is cut short", 0) end
  local a, b, c, d = byte(s, pos, pos + 3)
  local len = a + b * 256
  if bit32.bxor(len, c + d * 256) ~= 0xFFFF then error("the code is damaged (stored block)", 0) end
  pos = pos + 4
  if pos + len - 1 > r.len then error("the code is cut short", 0) end
  if out.flushed + out.n + len > M.MAX_OUTPUT then error("the code is too big", 0) end
  for i = 0, len - 1 do
    local n = out.n + 1
    out[n] = byte(s, pos + i)
    out.n = n
    if n >= FLUSH_AT then flush(out, n - WINDOW) end
  end
  r.pos = pos + len
end

--- Inflates raw DEFLATE data starting at byte `pos`. Returns the output string, its Adler-32 and the reader.
local function inflate_raw(s, pos)
  local r = reader(s, pos)
  local out = {n = 0, flushed = 0, parts = {}, a = 1, b = 0}
  repeat
    local last = bits(r, 1)
    local kind = bits(r, 2)
    if kind == 0 then
      stored(r, out)
    elseif kind == 1 then
      emit_codes(r, out, fixed_tables())
    elseif kind == 2 then
      emit_codes(r, out, dynamic_tables(r))
    else
      error("the code is damaged (bad block)", 0)
    end
  until last == 1
  flush(out, out.n)
  return concat(out.parts), out.b * 65536 + out.a, r
end

--- Inflates zlib data (what helpers.encode_string makes), checking its checksum. Returns a string.
function M.zlib(s)
  if #s < 6 then error("the code is cut short", 0) end
  local cmf, flg = byte(s, 1, 2)
  if band(cmf, 0x0F) ~= 8 or (cmf * 256 + flg) % 31 ~= 0 or band(flg, 0x20) ~= 0 then
    error("not a valid code (bad header)", 0)
  end
  local text, checksum, r = inflate_raw(s, 3)
  local pos = r.pos -- the checksum starts at the next whole byte
  if pos + 3 > #s then error("the code is cut short (no checksum)", 0) end
  local a, b, c, d = byte(s, pos, pos + 3)
  if ((a * 256 + b) * 256 + c) * 256 + d ~= checksum then
    error("the code is damaged (checksum)", 0)
  end
  return text
end

return M
