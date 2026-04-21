--- Roundtrip test: Lua server <-> Lua client, both directions.
--- Run with: nvim --headless --cmd "set rtp+=." -l test/roundtrip_spec.lua

local ws   = require("websocket")
local PORT = 19876

local results = {}
local server_conn

local server = ws.listen(PORT, {
  on_connect = function(conn)
    server_conn = conn
    conn:send("ping from server")
  end,
  on_message = function(conn, msg)
    results.server_received = msg
  end,
  on_error = function(err)
    results.error = "server error: " .. err
  end,
})

local client  -- declared before the closure so the callback captures the upvalue
client = ws.connect("ws://127.0.0.1:" .. PORT, {
  on_open = function()
    results.client_connected = true
  end,
  on_message = function(msg)
    results.client_received = msg
    client:send("pong from client")
  end,
  on_error = function(err)
    results.error = "client error: " .. err
  end,
})

local ok = vim.wait(3000, function()
  return results.error ~= nil
    or (results.client_received ~= nil and results.server_received ~= nil)
end, 20)

client:close()
server:close()

local function fail(msg)
  io.stderr:write("FAIL: " .. msg .. "\n")
  os.exit(1)
end

if not ok then                             fail("timed out") end
if results.error then                      fail(results.error) end
if not results.client_connected then       fail("on_open never fired") end
if results.client_received ~= "ping from server" then
  fail("client got: " .. tostring(results.client_received))
end
if results.server_received ~= "pong from client" then
  fail("server got: " .. tostring(results.server_received))
end

print("PASS")
os.exit(0)
