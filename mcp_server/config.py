from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


COLLECTIONS = ("filesystem", "messages", "browser", "misc")


@dataclass(frozen=True)
class ServerConfig:
    host: str = "127.0.0.1"
    port: int = 3847
    token: str = "dev-token"
    home: Path = field(default_factory=lambda: Path(os.environ.get("CONTEXTKIT_HOME", "~/.contextkit")).expanduser())
    allowed_folders: tuple[Path, ...] = field(default_factory=tuple)
    enabled_collections: tuple[str, ...] = COLLECTIONS
    use_chroma: bool = True

    @property
    def db_path(self) -> Path:
        return self.home / "contextkit.sqlite3"

    @property
    def chroma_path(self) -> Path:
        return self.home / "chroma"

    @property
    def screenshots_dir(self) -> Path:
        return self.home / "screenshots"

    @classmethod
    def from_env(cls, port: int | None = None, token: str | None = None) -> "ServerConfig":
        folders = tuple(
            Path(item).expanduser()
            for item in os.environ.get("CONTEXTKIT_ALLOWED_FOLDERS", "").split(os.pathsep)
            if item
        )
        return cls(
            host=os.environ.get("CONTEXTKIT_HOST", "127.0.0.1"),
            port=port or int(os.environ.get("CONTEXTKIT_PORT", "3847")),
            token=token or os.environ.get("CONTEXTKIT_TOKEN", "dev-token"),
            allowed_folders=folders,
            use_chroma=os.environ.get("CONTEXTKIT_USE_CHROMA", "1") != "0",
        )

    def prepare(self) -> None:
        self.home.mkdir(parents=True, exist_ok=True)
        self.chroma_path.mkdir(parents=True, exist_ok=True)
        self.screenshots_dir.mkdir(parents=True, exist_ok=True)
