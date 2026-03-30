--- WebSocket frame encoder/decoder (RFC 6455).
--- Client frames must be masked; server frames are unmasked.

local bit = require("bit")
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift = bit.lshift, bit.rshift

local M = {}

M.OP_CONTINUATION = 0x0
M.OP_TEXT         = 0x1
M.OP_BINARY       = 0x2
M.OP_CLOSE        = 0x8
M.OP_PING         = 0x9
M.OP_PONG         = 0xA

--- Encode a frame for sending from client to server (masked).
--- @param opcode number
--- @param payload string
--- @param fin boolean|nil  defaults to true
--- @return string
function M.encode(opcode, payload, fin)
  fin = (fin ~= false)
  local plen = #payload

  local mask = {
    math.random(0, 255), math.random(0, 255),
    math.random(0, 255), math.random(0, 255),
  }

  local header = {}
  header[#header+1] = string.char(bor(fin and 0x80 or 0x00, opcode))

  if plen <= 125 then
    header[#header+1] = string.char(bor(0x80, plen))
  elseif plen <= 0xFFFF then
    header[#header+1] = string.char(bor(0x80, 126))
    header[#header+1] = string.char(band(rshift(plen, 8), 0xFF))
    header[#header+1] = string.char(band(plen, 0xFF))
  else
    header[#header+1] = string.char(bor(0x80, 127))
    header[#header+1] = string.char(0, 0, 0, 0)  -- high 32 bits
    header[#header+1] = string.char(
      band(rshift(plen, 24), 0xFF),
      band(rshift(plen, 16), 0xFF),
      band(rshift(plen,  8), 0xFF),
      band(plen, 0xFF)
    )
  end

  header[#header+1] = string.char(mask[1], mask[2], mask[3], mask[4])

  local masked = {}
  for i = 1, plen do
    masked[i] = string.char(bxor(payload:byte(i), mask[((i-1) % 4) + 1]))
  end

  return table.concat(header) .. table.concat(masked)
end

--- Try to decode one frame from the front of buf.
--- Returns frame table + remaining buffer, or nil + original buffer if incomplete.
--- @param buf string
--- @return table|nil, string
function M.decode(buf)
  if #buf < 2 then return nil, buf end

  local b1, b2 = buf:byte(1), buf:byte(2)
  local fin       = band(b1, 0x80) ~= 0
  local opcode    = band(b1, 0x0F)
  local is_masked = band(b2, 0x80) ~= 0
  local plen      = band(b2, 0x7F)
  local offset    = 3  -- 1-indexed next byte

  if plen == 126 then
    if #buf < 4 then return nil, buf end
    plen   = bor(lshift(buf:byte(3), 8), buf:byte(4))
    offset = 5
  elseif plen == 127 then
    if #buf < 10 then return nil, buf end
    -- Ignore the high 4 bytes; use lower 4 only
    plen = bor(bor(bor(
      lshift(buf:byte(7), 24),
      lshift(buf:byte(8), 16)),
      lshift(buf:byte(9),  8)),
               buf:byte(10))
    offset = 11
  end

  local mask_key
  if is_masked then
    if #buf < offset + 3 then return nil, buf end
    mask_key = { buf:byte(offset), buf:byte(offset+1), buf:byte(offset+2), buf:byte(offset+3) }
    offset = offset + 4
  end

  if #buf < offset - 1 + plen then return nil, buf end

  local payload = buf:sub(offset, offset + plen - 1)
  if is_masked then
    local out = {}
    for i = 1, #payload do
      out[i] = string.char(bxor(payload:byte(i), mask_key[((i-1) % 4) + 1]))
    end
    payload = table.concat(out)
  end

  return { fin = fin, opcode = opcode, payload = payload }, buf:sub(offset + plen)
end

return M
