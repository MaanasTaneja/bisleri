from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from mcp_server.access_log import AccessLogger
from mcp_server.config import ServerConfig
from mcp_server.memory.chroma_store import SQLiteMemoryStore


@dataclass(frozen=True)
class ToolResult:
    id: str
    collection: str
    text: str
    metadata: dict[str, Any]
    timestamp: str
    score: float = 0.0


class ContextKitTools:
    def __init__(self, config: ServerConfig, store: SQLiteMemoryStore, access_logger: AccessLogger) -> None:
        self.config = config
        self.store = store
        self.access_logger = access_logger

    def save_memory(self, text: str, source: str = "manual") -> str:
        self.access_logger.record("save_memory", source)
        item = self.store.add(text, "misc", {"source": source})
        return item.id

    def ingest(self, text: str, collection: str = "misc", metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        self.access_logger.record("ingest", collection)
        item = self.store.add(text, collection, metadata or {})
        return asdict(ToolResult(item.id, item.collection, item.text, item.metadata, item.timestamp))

    def search_memory(self, query: str, limit: int = 10) -> list[dict[str, Any]]:
        self.access_logger.record("search_memory", query)
        return [self._to_result(item) for item in self.store.search(query, limit)]

    def find_file(self, query: str, limit: int = 10) -> list[dict[str, Any]]:
        self.access_logger.record("find_file", query)
        return [self._to_result(item) for item in self.store.search(query, limit, ["filesystem"])]

    def summarize_file(self, path: str) -> str:
        self.access_logger.record("summarize_file", path)
        resolved = str(Path(path).expanduser())
        if not self._path_allowed(resolved):
            raise PermissionError("path is outside allowed folders")
        item = self.store.by_path(resolved)
        if not item:
            return ""
        return str(item.metadata.get("summary") or item.text[:500])

    def find_screenshot(self, query: str, limit: int = 10) -> list[dict[str, Any]]:
        self.access_logger.record("find_screenshot", query)
        matches = self.store.search(query, limit)
        return [
            {
                "summary": item.metadata.get("summary", item.text[:160]),
                "screenshot_path": item.metadata.get("screenshot_path"),
                "timestamp": item.timestamp,
                "collection": item.collection,
                "score": item.score,
            }
            for item in matches
            if item.metadata.get("screenshot_path")
        ]

    def get_recent_context(self, time_range: str = "1h", limit: int = 20) -> list[dict[str, Any]]:
        self.access_logger.record("get_recent_context", time_range)
        return [self._to_result(item) for item in self.store.recent(time_range, limit)]

    def get_context_pack(self, name: str) -> dict[str, Any]:
        self.access_logger.record("get_context_pack", name)
        return {"name": name, "items": [], "status": "not_configured"}

    def list_allowed_sources(self) -> list[dict[str, Any]]:
        self.access_logger.record("list_allowed_sources")
        folders = [{"path": str(path), "enabled": True} for path in self.config.allowed_folders]
        return [
            {"type": "folder", "sources": folders},
            {"type": "collection", "sources": [{"name": name, "enabled": True} for name in self.config.enabled_collections]},
        ]

    def memory_status(self) -> dict[str, Any]:
        return {
            "backend": getattr(self.store, "backend", type(self.store).__name__),
            "mode": getattr(self.store, "mode", "unknown"),
            "location": getattr(self.store, "location", ""),
            "collections": list(self.config.enabled_collections),
        }

    def access_log(self, limit: int = 50) -> list[dict[str, Any]]:
        return self.access_logger.recent(limit)

    def _path_allowed(self, path: str) -> bool:
        if not self.config.allowed_folders:
            return True
        target = Path(path).expanduser().resolve()
        for folder in self.config.allowed_folders:
            try:
                target.relative_to(folder.expanduser().resolve())
                return True
            except ValueError:
                continue
        return False

    @staticmethod
    def _to_result(item: Any) -> dict[str, Any]:
        return asdict(ToolResult(item.id, item.collection, item.text, item.metadata, item.timestamp, item.score))
