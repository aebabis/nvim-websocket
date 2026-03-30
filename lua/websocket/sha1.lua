--- Pure Lua SHA-1 and base64 using LuaJIT bit library.
--- Handles messages up to ~512MB (sufficient for any WebSocket frame).

local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift = bit.lshift, bit.rshift

local M = {}

local function rotl32(x, n)
  return bor(lshift(x, n), rshift(x, 32 - n))
end

-- Wrapping 32-bit addition of any number of operands
local function add32(...)
  local s = 0
  for _, v in ipairs({...}) do s = s + v end
  return bit.tobit(s)
end

--- Returns the 20-byte raw SHA-1 digest of msg.
function M.sha1(msg)
  local msg_len = #msg

  -- Padding: append 0x80, then zeros, then 64-bit big-endian bit length
  msg = msg .. "\x80"
  while #msg % 64 ~= 56 do
    msg = msg .. "\x00"
  end
  local bit_len = msg_len * 8
  msg = msg .. string.char(
    0, 0, 0, 0,
    band(rshift(bit.tobit(bit_len), 24), 0xFF),
    band(rshift(bit.tobit(bit_len), 16), 0xFF),
    band(rshift(bit.tobit(bit_len),  8), 0xFF),
    band(bit.tobit(bit_len), 0xFF)
  )

  local h0 = bit.tobit(0x67452301)
  local h1 = bit.tobit(0xEFCDAB89)
  local h2 = bit.tobit(0x98BADCFE)
  local h3 = bit.tobit(0x10325476)
  local h4 = bit.tobit(0xC3D2E1F0)

  local w = {}
  for i = 1, #msg, 64 do
    for j = 0, 15 do
      local o = i + j * 4
      w[j] = bor(bor(bor(
        lshift(msg:byte(o),   24),
        lshift(msg:byte(o+1), 16)),
        lshift(msg:byte(o+2),  8)),
               msg:byte(o+3))
    end
    for j = 16, 79 do
      w[j] = rotl32(bxor(bxor(bxor(w[j-3], w[j-8]), w[j-14]), w[j-16]), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4

    for j = 0, 79 do
      local f, k
      if j < 20 then
        f = bor(band(b, c), band(bnot(b), d))
        k = bit.tobit(0x5A827999)
      elseif j < 40 then
        f = bxor(bxor(b, c), d)
        k = bit.tobit(0x6ED9EBA1)
      elseif j < 60 then
        f = bor(bor(band(b, c), band(b, d)), band(c, d))
        k = bit.tobit(0x8F1BBCDC)
      else
        f = bxor(bxor(b, c), d)
        k = bit.tobit(0xCA62C1D6)
      end
      local temp = add32(rotl32(a, 5), f, e, k, w[j])
      e = d; d = c; c = rotl32(b, 30); b = a; a = temp
    end

    h0 = add32(h0, a)
    h1 = add32(h1, b)
    h2 = add32(h2, c)
    h3 = add32(h3, d)
    h4 = add32(h4, e)
  end

  local function h2bytes(h)
    return string.char(
      band(rshift(h, 24), 0xFF),
      band(rshift(h, 16), 0xFF),
      band(rshift(h,  8), 0xFF),
      band(h, 0xFF)
    )
  end
  return h2bytes(h0) .. h2bytes(h1) .. h2bytes(h2) .. h2bytes(h3) .. h2bytes(h4)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

--- Base64-encodes arbitrary binary data.
function M.base64(data)
  local out = {}
  local pad = ""
  local rem = #data % 3
  if rem == 1 then
    data, pad = data .. "\x00\x00", "=="
  elseif rem == 2 then
    data, pad = data .. "\x00", "="
  end
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i), data:byte(i+1), data:byte(i+2)
    local n = bor(bor(lshift(a, 16), lshift(b, 8)), c)
    out[#out+1] = B64:sub(band(rshift(n, 18), 0x3F) + 1, band(rshift(n, 18), 0x3F) + 1)
    out[#out+1] = B64:sub(band(rshift(n, 12), 0x3F) + 1, band(rshift(n, 12), 0x3F) + 1)
    out[#out+1] = B64:sub(band(rshift(n,  6), 0x3F) + 1, band(rshift(n,  6), 0x3F) + 1)
    out[#out+1] = B64:sub(band(n,             0x3F) + 1, band(n,             0x3F) + 1)
  end
  local result = table.concat(out)
  return result:sub(1, #result - #pad) .. pad
end

return M
