from __future__ import annotations

import json
import logging
import os
import sqlite3
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from mcp_server.config import COLLECTIONS, normalize_collections, validate_collection_name
from mcp_server.memory.embedder import HashEmbedder, cosine

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class MemoryDocument:
    id: str
    collection: str
    text: str
    metadata: dict[str, Any]
    timestamp: str
    score: float = 0.0


class SQLiteMemoryStore:
    def __init__(
        self,
        db_path: Path,
        embedder: HashEmbedder | None = None,
        collections: tuple[str, ...] = COLLECTIONS,
    ) -> None:
        self.db_path = db_path
        self.embedder = embedder or HashEmbedder()
        self.collection_names = normalize_collections(list(collections))
        self.backend = "sqlite"
        self.mode = "fallback"
        self.location = str(db_path)
        self._init()
        logger.info("BrainDead memory store: SQLite fallback active at %s", db_path)

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
        if collection not in self.collection_names:
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
        selected = tuple(name for name in (collections or list(self.collection_names)) if name in self.collection_names)
        if not selected:
            selected = ("misc",)
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

    def create_collection(self, name: str) -> str:
        collection = validate_collection_name(name)
        if collection not in self.collection_names:
            self.collection_names = (*self.collection_names, collection)
        return collection

    def list_collections(self) -> list[str]:
        return list(self.collection_names)

    def by_path(self, path: str) -> MemoryDocument | None:
        with self._connect() as db:
            db.row_factory = sqlite3.Row
            rows = db.execute("select * from memories where collection = 'filesystem'").fetchall()
        for row in rows:
            metadata = json.loads(row["metadata"])
            if metadata.get("path") == path or metadata.get("source") == path:
                return MemoryDocument(row["id"], row["collection"], row["text"], metadata, row["timestamp"])
        return None

    def list_documents(self, collection: str | None = None, limit: int = 200) -> list[MemoryDocument]:
        with self._connect() as db:
            db.row_factory = sqlite3.Row
            if collection:
                rows = db.execute(
                    "select * from memories where collection = ? order by timestamp desc limit ?",
                    (collection, limit),
                ).fetchall()
            else:
                rows = db.execute(
                    "select * from memories order by timestamp desc limit ?",
                    (limit,),
                ).fetchall()
        return [
            MemoryDocument(row["id"], row["collection"], row["text"], json.loads(row["metadata"]), row["timestamp"])
            for row in rows
        ]

    def get(self, memory_id: str) -> MemoryDocument | None:
        with self._connect() as db:
            db.row_factory = sqlite3.Row
            row = db.execute("select * from memories where id = ?", (memory_id,)).fetchone()
        if not row:
            return None
        return MemoryDocument(row["id"], row["collection"], row["text"], json.loads(row["metadata"]), row["timestamp"])

    def delete(self, memory_id: str) -> bool:
        with self._connect() as db:
            cursor = db.execute("delete from memories where id = ?", (memory_id,))
        return cursor.rowcount > 0

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


class ChromaMemoryStore:
    def __init__(
        self,
        path: Path,
        embedder: HashEmbedder | None = None,
        collections: tuple[str, ...] = COLLECTIONS,
    ) -> None:
        try:
            import chromadb
        except ImportError as exc:
            raise RuntimeError("chromadb is not installed") from exc

        self.path = path
        self.embedder = embedder or HashEmbedder()
        host = os.environ.get("BRAINDEAD_CHROMA_HOST")
        port = os.environ.get("BRAINDEAD_CHROMA_PORT", "8000")
        if host:
            self.mode = "http"
            self.location = f"{host}:{port}"
            logger.info("BrainDead memory store: connecting to Chroma HTTP server at %s", self.location)
            self.client = chromadb.HttpClient(host=host, port=int(port))
        else:
            self.mode = "embedded"
            self.location = str(path.expanduser())
            logger.info("BrainDead memory store: starting embedded Chroma at %s", self.location)
            self.client = chromadb.PersistentClient(path=str(path.expanduser()))
        self.backend = "chroma"
        self.collections = {}
        for name in normalize_collections(list(collections)):
            self.create_collection(name)
        logger.info(
            "BrainDead memory store: Chroma is working in %s mode with collections: %s",
            self.mode,
            ", ".join(self.collections),
        )

    def add(self, text: str, collection: str = "misc", metadata: dict[str, Any] | None = None) -> MemoryDocument:
        collection = self.normalize_collection(collection)
        metadata = self._metadata(collection, metadata)
        memory_id = str(metadata.get("id") or uuid.uuid4())
        timestamp = str(metadata["timestamp"])
        embedding = self.embedder.embed(text)
        self.collections[collection].upsert(
            ids=[memory_id],
            documents=[text],
            embeddings=[embedding],
            metadatas=[metadata],
        )
        return MemoryDocument(memory_id, collection, text, metadata, timestamp)

    def search(self, query: str, limit: int = 10, collections: list[str] | None = None) -> list[MemoryDocument]:
        selected = [self.normalize_collection(name) for name in (collections or list(self.collections))]
        query_embedding = self.embedder.embed(query)
        results: list[MemoryDocument] = []
        per_collection = max(limit, 1)
        for collection_name in dict.fromkeys(selected):
            raw = self.collections[collection_name].query(
                query_embeddings=[query_embedding],
                n_results=per_collection,
                include=["documents", "metadatas", "distances"],
            )
            results.extend(self._query_results(collection_name, raw))
        results.sort(key=lambda item: (item.score, item.timestamp), reverse=True)
        return results[:limit]

    def create_collection(self, name: str) -> str:
        collection = validate_collection_name(name)
        if collection not in self.collections:
            self.collections[collection] = self.client.get_or_create_collection(
                name=collection,
                metadata={"hnsw:space": "cosine", "braindead_collection": collection},
            )
            logger.info("BrainDead memory store: Chroma collection ready: %s", collection)
        return collection

    def list_collections(self) -> list[str]:
        return list(self.collections)

    def recent(self, time_range: str = "1h", limit: int = 20) -> list[MemoryDocument]:
        cutoff = SQLiteMemoryStore._cutoff(time_range).isoformat()
        results: list[MemoryDocument] = []
        for collection_name, collection in self.collections.items():
            raw = collection.get(include=["documents", "metadatas"])
            results.extend(item for item in self._get_results(collection_name, raw) if item.timestamp >= cutoff)
        results.sort(key=lambda item: item.timestamp, reverse=True)
        return results[:limit]

    def by_path(self, path: str) -> MemoryDocument | None:
        collection = self.collections["filesystem"]
        for key in ("path", "source"):
            raw = collection.get(where={key: path}, include=["documents", "metadatas"], limit=1)
            matches = self._get_results("filesystem", raw)
            if matches:
                return matches[0]
        return None

    def list_documents(self, collection: str | None = None, limit: int = 200) -> list[MemoryDocument]:
        names = [collection] if collection and collection in self.collections else list(self.collections.keys())
        results: list[MemoryDocument] = []
        for name in names:
            raw = self.collections[name].get(include=["documents", "metadatas"], limit=limit)
            results.extend(self._get_results(name, raw))
        results.sort(key=lambda item: item.timestamp, reverse=True)
        return results[:limit]

    def get(self, memory_id: str) -> MemoryDocument | None:
        for name, collection in self.collections.items():
            raw = collection.get(ids=[memory_id], include=["documents", "metadatas"])
            results = self._get_results(name, raw)
            if results:
                return results[0]
        return None

    def delete(self, memory_id: str) -> bool:
        deleted = False
        for collection in self.collections.values():
            try:
                existing = collection.get(ids=[memory_id])
                if existing.get("ids"):
                    collection.delete(ids=[memory_id])
                    deleted = True
            except Exception:
                continue
        return deleted

    def normalize_collection(self, collection: str) -> str:
        return collection if collection in self.collections else "misc"

    @staticmethod
    def _metadata(collection: str, metadata: dict[str, Any] | None) -> dict[str, Any]:
        prepared = dict(metadata or {})
        prepared["collection"] = collection
        prepared.setdefault("source", "manual")
        prepared.setdefault("summary", "")
        prepared.setdefault("screenshot_path", "")
        prepared.setdefault("timestamp", datetime.now(timezone.utc).isoformat())
        return {key: ChromaMemoryStore._scalar(value) for key, value in prepared.items() if value is not None}

    @staticmethod
    def _scalar(value: Any) -> str | int | float | bool:
        if isinstance(value, str | int | float | bool):
            return value
        return json.dumps(value, sort_keys=True)

    @staticmethod
    def _query_results(collection: str, raw: dict[str, Any]) -> list[MemoryDocument]:
        ids = raw.get("ids", [[]])[0]
        documents = raw.get("documents", [[]])[0]
        metadatas = raw.get("metadatas", [[]])[0]
        distances = raw.get("distances", [[]])[0]
        results: list[MemoryDocument] = []
        for index, memory_id in enumerate(ids):
            metadata = dict(metadatas[index] or {})
            timestamp = str(metadata.get("timestamp", ""))
            distance = float(distances[index]) if index < len(distances) else 1.0
            score = 1.0 - distance
            results.append(MemoryDocument(memory_id, collection, documents[index], metadata, timestamp, score))
        return results

    @staticmethod
    def _get_results(collection: str, raw: dict[str, Any]) -> list[MemoryDocument]:
        ids = raw.get("ids", [])
        documents = raw.get("documents", [])
        metadatas = raw.get("metadatas", [])
        results: list[MemoryDocument] = []
        for index, memory_id in enumerate(ids):
            metadata = dict(metadatas[index] or {})
            timestamp = str(metadata.get("timestamp", ""))
            results.append(MemoryDocument(memory_id, collection, documents[index], metadata, timestamp))
        return results


def normalize_collection(collection: str) -> str:
    return collection if collection in COLLECTIONS else "misc"


def create_store(
    db_path: Path,
    use_chroma: bool = True,
    chroma_path: Path | None = None,
    collections: tuple[str, ...] = COLLECTIONS,
) -> ChromaMemoryStore | SQLiteMemoryStore:
    if use_chroma:
        try:
            return ChromaMemoryStore(chroma_path or db_path.parent / "chroma", collections=collections)
        except Exception as exc:
            logger.warning("BrainDead memory store: Chroma unavailable, falling back to SQLite: %s", exc)
    else:
        logger.info("BrainDead memory store: Chroma disabled by BRAINDEAD_USE_CHROMA=0")
    return SQLiteMemoryStore(db_path, collections=collections)
