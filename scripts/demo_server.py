from __future__ import annotations

from tempfile import TemporaryDirectory

from mcp_server.config import ServerConfig
from mcp_server.main import build_tools


def main() -> None:
    with TemporaryDirectory() as tmp:
        config = ServerConfig(home=tmp, token="demo")
        tools = build_tools(config)
        tools.ingest(
            "Q3 lease agreement PDF is due Friday and lives in Downloads.",
            "filesystem",
            {"source": "demo", "path": "/tmp/lease.pdf", "summary": "Lease PDF deadline note"},
        )
        print(tools.search_memory("lease due Friday", 3))


if __name__ == "__main__":
    main()
