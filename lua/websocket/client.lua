--- WebSocket client built on vim.uv (libuv) TCP.
--- No external dependencies beyond the sha1 and frame submodules.

local uv    = vim.uv or vim.loop
local frame = require("websocket.frame")
local sha1  = require("websocket.sha1")

local Client = {}
Client.__index = Client

local MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

--- Parse a ws:// or wss:// URL.
--- @return table|nil, string|nil
local function parse_url(url)
  local scheme, host, port, path = url:match("^(wss?)://([^:/]+):?(%d*)(/?.*)")
  if not scheme then
    return nil, "invalid WebSocket URL: " .. url
  end
  if scheme == "wss" then
    return nil, "wss:// (TLS) is not yet supported"
  end
  return {
    host = host,
    port = tonumber(port) or 80,
    path = path ~= "" and path or "/",
  }
end

--- Generate a random 16-byte WebSocket handshake key (base64-encoded).
local function new_ws_key()
  local bytes = {}
  for i = 1, 16 do bytes[i] = string.char(math.random(0, 255)) end
  return sha1.base64(table.concat(bytes))
end

--- Compute the expected Sec-WebSocket-Accept value for a given key.
local function expected_accept(key)
  return sha1.base64(sha1.sha1(key .. MAGIC))
end

--- Create a new WebSocket client.
--- @param opts table  Keys: on_open, on_message, on_close, on_error (all optional callbacks)
--- @return table
function Client.new(opts)
  return setmetatable({
    _state    = "CLOSED",
    _buf      = "",
    _tcp      = nil,
    _key      = nil,
    on_open    = opts.on_open,
    on_message = opts.on_message,
    on_close   = opts.on_close,
    on_error   = opts.on_error,
  }, Client)
end

--- Connect to a WebSocket server.
--- @param url string  e.g. "ws://localhost:8765"
function Client:connect(url)
  if self._state ~= "CLOSED" then return end

  local parsed, err = parse_url(url)
  if not parsed then
    self:_on_error(err)
    return
  end

  self._state = "CONNECTING"
  self._tcp   = uv.new_tcp()

  uv.getaddrinfo(parsed.host, nil, { family = "inet", socktype = "stream" }, function(err, res)
    if err or not res or #res == 0 then
      self:_on_error("DNS lookup failed for " .. parsed.host .. ": " .. tostring(err))
      return
    end

    self._tcp:connect(res[1].addr, parsed.port, function(err)
      if err then
        self:_on_error("TCP connect failed: " .. err)
        return
      end
      self:_handshake(parsed)
    end)
  end)
end

function Client:_handshake(parsed)
  self._key = new_ws_key()

  local req = table.concat({
    "GET " .. parsed.path .. " HTTP/1.1",
    "Host: " .. parsed.host .. (parsed.port ~= 80 and (":" .. parsed.port) or ""),
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Key: " .. self._key,
    "Sec-WebSocket-Version: 13",
    "", "",
  }, "\r\n")

  self._tcp:write(req)
  self._buf = ""

  self._tcp:read_start(function(err, data)
    if err then
      self:_on_error("read error: " .. err)
      return
    end
    if data == nil then
      self:_on_remote_close()
      return
    end
    self._buf = self._buf .. data
    self:_process()
  end)
end

function Client:_process()
  -- Consume the HTTP upgrade response first
  if self._state == "CONNECTING" then
    local header_end = self._buf:find("\r\n\r\n", 1, true)
    if not header_end then return end

    local headers = self._buf:sub(1, header_end - 1)
    self._buf     = self._buf:sub(header_end + 4)

    if not headers:find("^HTTP/1%.1 101") then
      self:_on_error("unexpected HTTP response: " .. (headers:match("^[^\r\n]+") or "?"))
      return
    end

    local accept = headers:match("Sec%-WebSocket%-Accept: ([^\r\n]+)")
    if accept ~= expected_accept(self._key) then
      self:_on_error("Sec-WebSocket-Accept mismatch (not a valid WebSocket server?)")
      return
    end

    self._state = "OPEN"
    if self.on_open then
      vim.schedule(function() self.on_open() end)
    end
    -- fall through: _buf may already contain frames
  end

  -- Parse as many complete frames as are buffered
  while true do
    local f, rest = frame.decode(self._buf)
    if not f then break end
    self._buf = rest
    self:_dispatch(f)
  end
end

function Client:_dispatch(f)
  local op = f.opcode
  if op == frame.OP_TEXT or op == frame.OP_BINARY then
    if self.on_message then
      local payload = f.payload
      vim.schedule(function() self.on_message(payload) end)
    end
  elseif op == frame.OP_PING then
    self:_write(frame.encode(frame.OP_PONG, f.payload))
  elseif op == frame.OP_PONG then
    -- no-op
  elseif op == frame.OP_CLOSE then
    -- Echo the close frame then shut down
    self:_write(frame.encode(frame.OP_CLOSE, f.payload))
    self:_shutdown()
  end
end

--- Send a text message. No-op if not OPEN.
--- @param msg string
function Client:send(msg)
  if self._state ~= "OPEN" then return end
  self:_write(frame.encode(frame.OP_TEXT, msg))
end

--- Initiate a clean close.
function Client:close()
  if self._state ~= "OPEN" then return end
  self._state = "CLOSING"
  self:_write(frame.encode(frame.OP_CLOSE, ""))
  self:_shutdown()
end

function Client:_write(data)
  if self._tcp then
    self._tcp:write(data)
  end
end

function Client:_shutdown()
  if self._state == "CLOSED" then return end
  self._state = "CLOSED"
  if self._tcp then
    self._tcp:read_stop()
    if not self._tcp:is_closing() then
      self._tcp:close()
    end
    self._tcp = nil
  end
  if self.on_close then
    vim.schedule(function() self.on_close() end)
  end
end

function Client:_on_remote_close()
  self:_shutdown()
end

function Client:_on_error(msg)
  local was_closed = (self._state == "CLOSED")
  self._state = "CLOSED"
  if self._tcp then
    pcall(function()
      self._tcp:read_stop()
      if not self._tcp:is_closing() then self._tcp:close() end
    end)
    self._tcp = nil
  end
  if not was_closed and self.on_error then
    vim.schedule(function() self.on_error(msg) end)
  end
end

return Client
