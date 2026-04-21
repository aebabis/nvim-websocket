--- nvim-websocket public API

local Client = require("websocket.client")
local Server = require("websocket.server")

local M = {}

--- Open a WebSocket connection.
---
--- @param url   string  ws:// URL to connect to
--- @param opts  table   Callbacks: on_open(), on_message(msg), on_close(), on_error(err)
--- @return table  Client object with :send(msg) and :close() methods
function M.connect(url, opts)
  local client = Client.new(opts or {})
  client:connect(url)
  return client
end

--- Start a WebSocket server.
---
--- @param port  number
--- @param opts  table   Callbacks: on_connect(conn), on_message(conn, msg), on_close(conn), on_error(err)
---                      Optional key: host (string, default "127.0.0.1")
--- @return table  Server object with :close() method
function M.listen(port, opts)
  opts = opts or {}
  local server = Server.new(opts)
  server:listen(port, opts.host)
  return server
end

return M
