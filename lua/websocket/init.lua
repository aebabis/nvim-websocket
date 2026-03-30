--- nvim-websocket public API

local Client = require("websocket.client")

local M = {}

--- Open a WebSocket connection.
---
--- @param url     string   ws:// URL to connect to
--- @param opts    table    Callbacks:
---                           on_open()
---                           on_message(msg: string)
---                           on_close()
---                           on_error(err: string)
--- @return table  Client object with :send(msg) and :close() methods
function M.connect(url, opts)
  local client = Client.new(opts or {})
  client:connect(url)
  return client
end

return M
