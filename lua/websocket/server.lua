--- WebSocket server built on vim.uv (libuv) TCP.
--- No external dependencies beyond the sha1 and frame submodules.

local uv    = vim.uv or vim.loop
local frame = require("websocket.frame")
local sha1  = require("websocket.sha1")

local MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

--- Represents one accepted WebSocket connection.
local Conn = {}
Conn.__index = Conn

local function new_conn(tcp, server)
  return setmetatable({
    _tcp    = tcp,
    _buf    = "",
    _state  = "HANDSHAKING",
    _server = server,
  }, Conn)
end

function Conn:_start()
  self._tcp:read_start(function(err, data)
    if err or data == nil then
      self:_shutdown()
      return
    end
    self._buf = self._buf .. data
    self:_process()
  end)
end

function Conn:_process()
  if self._state == "HANDSHAKING" then
    local header_end = self._buf:find("\r\n\r\n", 1, true)
    if not header_end then return end

    local headers = self._buf:sub(1, header_end - 1)
    self._buf     = self._buf:sub(header_end + 4)

    local key = headers:match("Sec%-WebSocket%-Key:%s*([^\r\n]+)")
    if not key then
      self._tcp:close()
      return
    end
    key = key:match("^%s*(.-)%s*$")  -- trim whitespace

    local accept   = sha1.base64(sha1.sha1(key .. MAGIC))
    local response = table.concat({
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Accept: " .. accept,
      "", "",
    }, "\r\n")

    self._tcp:write(response)
    self._state = "OPEN"

    local server = self._server
    if server.on_connect then
      vim.schedule(function() server.on_connect(self) end)
    end
  end

  while true do
    local f, rest = frame.decode(self._buf)
    if not f then break end
    self._buf = rest
    self:_dispatch(f)
  end
end

function Conn:_dispatch(f)
  local op = f.opcode
  if op == frame.OP_TEXT or op == frame.OP_BINARY then
    local server  = self._server
    local payload = f.payload
    if server.on_message then
      vim.schedule(function() server.on_message(self, payload) end)
    end
  elseif op == frame.OP_PING then
    self:_write(frame.encode_server(frame.OP_PONG, f.payload))
  elseif op == frame.OP_PONG then
    -- no-op
  elseif op == frame.OP_CLOSE then
    self:_write(frame.encode_server(frame.OP_CLOSE, f.payload))
    self:_shutdown()
  end
end

--- Send a text message to this client. No-op if not OPEN.
--- @param msg string
function Conn:send(msg)
  if self._state ~= "OPEN" then return end
  self:_write(frame.encode_server(frame.OP_TEXT, msg))
end

--- Initiate a clean close of this connection.
function Conn:close()
  if self._state ~= "OPEN" then return end
  self._state = "CLOSING"
  self:_write(frame.encode_server(frame.OP_CLOSE, ""))
  self:_shutdown()
end

function Conn:_write(data)
  if self._tcp then self._tcp:write(data) end
end

function Conn:_shutdown()
  if self._state == "CLOSED" then return end
  self._state = "CLOSED"
  if self._tcp then
    self._tcp:read_stop()
    if not self._tcp:is_closing() then self._tcp:close() end
    self._tcp = nil
  end
  local server = self._server
  if server.on_close then
    vim.schedule(function() server.on_close(self) end)
  end
end

--- WebSocket server.
local Server = {}
Server.__index = Server

--- Create a new WebSocket server.
--- @param opts table  Keys: on_connect(conn), on_message(conn, msg), on_close(conn), on_error(err)
--- @return table
function Server.new(opts)
  return setmetatable({
    _tcp       = nil,
    _state     = "CLOSED",
    on_connect = opts.on_connect,
    on_message = opts.on_message,
    on_close   = opts.on_close,
    on_error   = opts.on_error,
  }, Server)
end

--- Start listening for WebSocket connections.
--- @param port   number
--- @param host   string|nil  defaults to "127.0.0.1"
function Server:listen(port, host)
  host = host or "127.0.0.1"
  self._tcp  = uv.new_tcp()

  local ok, err = self._tcp:bind(host, port)
  if ok == nil then
    self:_on_error("bind failed on " .. host .. ":" .. port .. ": " .. tostring(err))
    return
  end

  self._tcp:listen(128, function(err)
    if err then
      self:_on_error("listen error: " .. err)
      return
    end
    local client_tcp = uv.new_tcp()
    self._tcp:accept(client_tcp)
    new_conn(client_tcp, self):_start()
  end)

  self._state = "LISTENING"
end

--- Stop accepting new connections (does not close existing ones).
function Server:close()
  if self._state == "CLOSED" then return end
  self._state = "CLOSED"
  if self._tcp then
    if not self._tcp:is_closing() then self._tcp:close() end
    self._tcp = nil
  end
end

function Server:_on_error(msg)
  self._state = "CLOSED"
  if self._tcp then
    pcall(function()
      if not self._tcp:is_closing() then self._tcp:close() end
    end)
    self._tcp = nil
  end
  if self.on_error then
    vim.schedule(function() self.on_error(msg) end)
  end
end

return Server
