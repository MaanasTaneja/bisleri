from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class AccessLogEntry:
    tool: str
    client: str
    query: str
    timestamp: str


class AccessLogger:
    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self._init()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _init(self) -> None:
        with self._connect() as db:
            db.execute(
                """
                create table if not exists access_log (
                    id integer primary key autoincrement,
                    timestamp text not null,
                    client text not null,
                    tool text not null,
                    query text not null
                )
                """
            )

    def record(self, tool: str, query: str = "", client: str = "local") -> None:
        timestamp = datetime.now(timezone.utc).isoformat()
        with self._connect() as db:
            db.execute(
                "insert into access_log(timestamp, client, tool, query) values (?, ?, ?, ?)",
                (timestamp, client, tool, query),
            )

    def recent(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._connect() as db:
            db.row_factory = sqlite3.Row
            rows = db.execute(
                "select timestamp, client, tool, query from access_log order by id desc limit ?",
                (limit,),
            ).fetchall()
        return [dict(row) for row in rows]
