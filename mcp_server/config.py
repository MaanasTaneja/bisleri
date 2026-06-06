from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path


DEFAULT_COLLECTIONS = ("filesystem", "messages", "browser", "misc")
COLLECTIONS = DEFAULT_COLLECTIONS
COLLECTION_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]{1,61}[a-z0-9]$")


@dataclass(frozen=True)
class ServerConfig:
    host: str = "127.0.0.1"
    port: int = 3847
    token: str = "dev-token"
    home: Path = field(default_factory=lambda: Path(os.environ.get("BRAINDEAD_HOME", "~/.braindead")).expanduser())
    allowed_folders: tuple[Path, ...] = field(default_factory=tuple)
    enabled_collections: tuple[str, ...] = COLLECTIONS
    use_chroma: bool = True

    @property
    def db_path(self) -> Path:
        return self.home / "braindead.sqlite3"

    @property
    def chroma_path(self) -> Path:
        return self.home / "chroma"

    @property
    def screenshots_dir(self) -> Path:
        return self.home / "screenshots"

    @property
    def collections_path(self) -> Path:
        return self.home / "collections.json"

    @classmethod
    def from_env(cls, port: int | None = None, token: str | None = None) -> "ServerConfig":
        folders = tuple(
            Path(item).expanduser()
            for item in os.environ.get("BRAINDEAD_ALLOWED_FOLDERS", "").split(os.pathsep)
            if item
        )
        return cls(
            host=os.environ.get("BRAINDEAD_HOST", "127.0.0.1"),
            port=port or int(os.environ.get("BRAINDEAD_PORT", "3847")),
            token=token or os.environ.get("BRAINDEAD_TOKEN", "dev-token"),
            allowed_folders=folders,
            use_chroma=os.environ.get("BRAINDEAD_USE_CHROMA", "1") != "0",
        )

    def prepare(self) -> None:
        self.home.mkdir(parents=True, exist_ok=True)
        self.chroma_path.mkdir(parents=True, exist_ok=True)
        self.screenshots_dir.mkdir(parents=True, exist_ok=True)

    def load_collections(self) -> tuple[str, ...]:
        custom: list[str] = []
        if self.collections_path.exists():
            try:
                payload = json.loads(self.collections_path.read_text())
                if isinstance(payload, list):
                    custom = [str(item) for item in payload]
                elif isinstance(payload, dict) and isinstance(payload.get("collections"), list):
                    custom = [str(item) for item in payload["collections"]]
            except (OSError, json.JSONDecodeError):
                custom = []
        return normalize_collections((*DEFAULT_COLLECTIONS, *custom))

    def save_custom_collections(self, collections: tuple[str, ...]) -> None:
        custom = [name for name in normalize_collections(collections) if name not in DEFAULT_COLLECTIONS]
        self.collections_path.write_text(json.dumps({"collections": custom}, indent=2, sort_keys=True))


def normalize_collection_name(name: str) -> str:
    normalized = name.strip().lower().replace(" ", "_")
    normalized = re.sub(r"[^a-z0-9_-]+", "_", normalized)
    normalized = re.sub(r"[_-]{2,}", "_", normalized).strip("_-")
    return normalized


def validate_collection_name(name: str) -> str:
    normalized = normalize_collection_name(name)
    if normalized in DEFAULT_COLLECTIONS:
        return normalized
    if not COLLECTION_NAME_PATTERN.match(normalized):
        raise ValueError("collection names must be 3-63 lowercase letters, numbers, underscores, or hyphens")
    return normalized


def normalize_collections(collections: tuple[str, ...] | list[str]) -> tuple[str, ...]:
    names: list[str] = []
    for collection in collections:
        try:
            normalized = validate_collection_name(collection)
        except ValueError:
            continue
        if normalized not in names:
            names.append(normalized)
    return tuple(names)
