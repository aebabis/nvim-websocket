#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["websockets"]
# ///
"""
Simple WebSocket test server for nvim-websocket development.

Usage:
    uv run test/server.py [port]          (recommended, no venv needed)
    python3 test/server.py [port]         (with websockets already installed)
    make server                           (convenience wrapper)
    make server PORT=8766                 (custom port)

Default port: 8765

Behavior:
    - Echoes every text message back prefixed with "echo: "
    - Sends a greeting on connect
    - Broadcasts a periodic ping every 10 seconds (optional, see --ping)
"""

import asyncio
import sys
import websockets

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
CLIENTS = set()


async def handler(websocket):
    CLIENTS.add(websocket)
    remote = websocket.remote_address
    print(f"[+] connected: {remote}")
    try:
        await websocket.send('{"type":"hello","server":"nvim-websocket test server"}')
        async for message in websocket:
            print(f"[{remote}] recv: {message!r}")
            reply = f"echo: {message}"
            await websocket.send(reply)
            print(f"[{remote}] sent: {reply!r}")
    except websockets.exceptions.ConnectionClosedOK:
        pass
    except websockets.exceptions.ConnectionClosedError as e:
        print(f"[{remote}] closed with error: {e}")
    finally:
        CLIENTS.discard(websocket)
        print(f"[-] disconnected: {remote}")


async def main():
    print(f"WebSocket test server listening on ws://localhost:{PORT}")
    async with websockets.serve(handler, "localhost", PORT):
        await asyncio.Future()  # run forever


asyncio.run(main())
