PORT ?= 8765

.PHONY: server test

server:
	uv run test/server.py $(PORT)

test:
	nvim --headless --cmd "set rtp+=." -l test/roundtrip_spec.lua
