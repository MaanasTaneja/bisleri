from __future__ import annotations

import json
import sqlite3
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from mcp_server.config import COLLECTIONS
from mcp_server.memory.embedder import HashEmbedder, cosine


@dataclass(frozen=True)
class MemoryDocument:
    id: str
    collection: str
    text: str
    metadata: dict[str, Any]
    timestamp: str
    score: float = 0.0


class SQLiteMemoryStore:
    def __init__(self, db_path: Path, embedder: HashEmbedder | None = None) -> None:
        self.db_path = db_path
        self.embedder = embedder or HashEmbedder()
        self._init()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _init(self) -> None:
        with self._connect() as db:
            db.execute(
                """
                create table if not exists memories (
                    id text primary key,
                    collection text not null,
                    text text not null,
                    metadata text not null,
                    embedding text not null,
                    timestamp text not null
                )
                """
            )
            db.execute("create index if not exists memories_collection_idx on memories(collection)")
            db.execute("create index if not exists memories_timestamp_idx on memories(timestamp)")

    def add(self, text: str, collection: str = "misc", metadata: dict[str, Any] | None = None) -> MemoryDocument:
        if collection not in COLLECTIONS:
            collection = "misc"
        metadata = dict(metadata or {})
        timestamp = metadata.get("timestamp") or datetime.now(timezone.utc).isoformat()
        metadata["collection"] = collection
        memory_id = metadata.get("id") or str(uuid.uuid4())
        embedding = self.embedder.embed(text)
        with self._connect() as db:
            db.execute(
                """
                insert or replace into memories(id, collection, text, metadata, embedding, timestamp)
                values (?, ?, ?, ?, ?, ?)
                """,
                (memory_id, collection, text, json.dumps(metadata), json.dumps(embedding), timestamp),
            )
        return MemoryDocument(memory_id, collection, text, metadata, timestamp)

    def search(self, query: str, limit: int = 10, collections: list[str] | None = None) -> list[MemoryDocument]:
        query_embedding = self.embedder.embed(query)
        selected = tuple(collections or COLLECTIONS)
        placeholders = ",".join("?" for _ in selected)
        with self._connect() as db:
            db.row_factory = sqlite3.Row
            rows = db.execute(
                f"select * from memories where collection in ({placeholders})",
                selected,
            ).fetchall()

        results: list[MemoryDocument] = []
        for row in rows:
            embedding = json.loads(row["embedding"])
            score = cosine(query_embedding, embedding)
            metadata = json.loads(row["metadata"])
            results.append(
                MemoryDocument(row["id"], row["collection"], row["text"], metadata, row["timestamp"], score)
            )
        results.sort(key=lambda item: (item.score, item.timestamp), reverse=True)
        return results[:limit]

    def recent(self, time_range: str = "1h", limit: int = 20) -> list[MemoryDocument]:
        cutoff = self._cutoff(time_range)
        with self._connect() as db:
            db.row_factory = sqlite3.Row
            rows = db.execute(
                "select * from memories where timestamp >= ? order by timestamp desc limit ?",
                (cutoff.isoformat(), limit),
            ).fetchall()
        return [
            MemoryDocument(row["id"], row["collection"], row["text"], json.loads(row["metadata"]), row["timestamp"])
            for row in rows
        ]

    def by_path(self, path: str) -> MemoryDocument | None:
        with self._connect() as db:
            db.row_factory = sqlite3.Row
            rows = db.execute("select * from memories where collection = 'filesystem'").fetchall()
        for row in rows:
            metadata = json.loads(row["metadata"])
            if metadata.get("path") == path or metadata.get("source") == path:
                return MemoryDocument(row["id"], row["collection"], row["text"], metadata, row["timestamp"])
        return None

    @staticmethod
    def _cutoff(time_range: str) -> datetime:
        now = datetime.now(timezone.utc)
        normalized = time_range.strip().lower()
        if normalized == "today":
            return now.replace(hour=0, minute=0, second=0, microsecond=0)
        if normalized.endswith("h") and normalized[:-1].isdigit():
            return now - timedelta(hours=int(normalized[:-1]))
        if normalized.endswith("d") and normalized[:-1].isdigit():
            return now - timedelta(days=int(normalized[:-1]))
        return now - timedelta(hours=1)


def create_store(db_path: Path, use_chroma: bool = False) -> SQLiteMemoryStore:
    # ChromaDB can be introduced behind this factory without changing tool code.
    # The SQLite implementation is intentionally kept as the dependable local fallback.
    return SQLiteMemoryStore(db_path)
