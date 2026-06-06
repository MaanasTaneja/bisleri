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
python3 -m venv .venv
source .venv/bin/activate
pip install -r mcp_server/requirements.txt
python -m mcp_server.main --port 3847 --token dev-token
```

By default, memory uses ChromaDB and creates the planned collections:

- `filesystem`
- `messages`
- `browser`
- `misc`

Embedded Chroma persists under `~/.contextkit/chroma`. To point at a local Chroma daemon running in Docker instead:

```bash
export CONTEXTKIT_CHROMA_HOST=127.0.0.1
export CONTEXTKIT_CHROMA_PORT=8000
python -m mcp_server.main --port 3847 --token dev-token
```

Set `CONTEXTKIT_USE_CHROMA=0` only when you intentionally want the SQLite fallback for lightweight testing.

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

The tests cover the Chroma collection creation/routing path with a fake Chroma client and the SQLite fallback path for fast local verification.

## Privacy defaults

- Server binds to `127.0.0.1` by default.
- Bearer token auth is required for all ingest and tool endpoints.
- Chroma memory, metadata, screenshots, and access logs live under `~/.contextkit` unless `CONTEXTKIT_HOME` is set.
- The Swift app owns server lifecycle and can stop the process from the menu bar.
