PORT ?= 8765

.PHONY: server

server:
	uv run test/server.py $(PORT)
