--- nvim-websocket user commands

local ws_mod = require("websocket")

-- Active persistent connection, if any
local _conn = nil

--- Show a notification via fidget (or vim.notify fallback)
local function notify(msg, level, title)
  vim.notify(msg, level or vim.log.levels.INFO, { title = title or "websocket" })
end

--- :WS <url> [message]
---
--- With a message: one-shot — connect, send, show first response, close.
--- Without a message: persistent — connect and show every incoming message.
---   Run :WS again with a new URL to replace the connection.
vim.api.nvim_create_user_command("WS", function(opts)
  local args  = opts.fargs
  local url   = args[1]
  local msg   = #args > 1 and table.concat(args, " ", 2) or nil

  if not url then
    notify("Usage: WS <url> [message]", vim.log.levels.ERROR)
    return
  end

  -- Close any existing persistent connection before opening a new one
  if _conn then
    _conn:close()
    _conn = nil
  end

  if msg then
    -- One-shot mode
    local client
    client = ws_mod.connect(url, {
      on_open = function()
        client:send(msg)
      end,
      on_message = function(data)
        notify(data, vim.log.levels.INFO, url)
        client:close()
      end,
      on_error = function(err)
        notify(err, vim.log.levels.ERROR, url)
      end,
    })
  else
    -- Persistent mode
    _conn = ws_mod.connect(url, {
      on_open = function()
        notify("connected", vim.log.levels.INFO, url)
      end,
      on_message = function(data)
        notify(data, vim.log.levels.INFO, url)
      end,
      on_close = function()
        notify("disconnected", vim.log.levels.WARN, url)
        if _conn and _conn._state == "CLOSED" then
          _conn = nil
        end
      end,
      on_error = function(err)
        notify(err, vim.log.levels.ERROR, url)
        _conn = nil
      end,
    })
  end
end, {
  nargs = "+",
  desc  = "Open a WebSocket connection. WS <url> [message]",
})

--- :WSend <message>  — send a message on the active persistent connection
vim.api.nvim_create_user_command("WSend", function(opts)
  if not _conn then
    notify("No active connection. Use :WS <url> first.", vim.log.levels.ERROR)
    return
  end
  _conn:send(opts.args)
end, {
  nargs = "+",
  desc  = "Send a message on the active WebSocket connection",
})

--- :WSClose  — close the active persistent connection
vim.api.nvim_create_user_command("WSClose", function()
  if not _conn then
    notify("No active connection.", vim.log.levels.WARN)
    return
  end
  _conn:close()
  _conn = nil
end, {
  nargs = 0,
  desc  = "Close the active WebSocket connection",
})
