# ContextKit

One context, everywhere. Your memory stays on your Mac.

ContextKit is a macOS menu bar app plus a local MCP server. It captures selected context from your Mac, stores it locally, and exposes only relevant snippets to AI clients through authenticated localhost tools.

## What is in this repo

- `ContextKit/`: macOS SwiftUI source scaffold for the menu bar app, capture flows, privacy controls, and server process management.
- `mcp_server/`: Python local MCP/HTTP server, memory storage, auth, access logging, and tool implementations.
- `tests/`: Python verification for the local memory server behavior.
- `docs/tickets.md`: the implementation ticket breakdown mirrored to GitHub issues.

## Local server quick start

```bash
cd mcp_server
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m mcp_server.main --port 3847 --token dev-token
```

Health check:

```bash
curl http://127.0.0.1:3847/health
```

Ingest memory:

```bash
curl -X POST http://127.0.0.1:3847/ingest \
  -H 'Authorization: Bearer dev-token' \
  -H 'Content-Type: application/json' \
  -d '{"text":"Q3 lease PDF due Friday","collection":"filesystem","metadata":{"source":"demo"}}'
```

## Tests

```bash
python -m pytest
```

The tests use the SQLite fallback store and do not require ChromaDB or sentence-transformers.

## Privacy defaults

- Server binds to `127.0.0.1` by default.
- Bearer token auth is required for all ingest and tool endpoints.
- Memory, metadata, and access logs live under `~/.contextkit` unless `CONTEXTKIT_HOME` is set.
- The Swift app owns server lifecycle and can stop the process from the menu bar.
