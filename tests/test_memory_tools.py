from __future__ import annotations

import base64
from datetime import datetime, timezone
import sys
from types import SimpleNamespace

import pytest

from mcp_server.auth import AuthError, TokenAuth
from mcp_server.config import COLLECTIONS, ServerConfig
from mcp_server.main import build_tools, create_app
from mcp_server.memory.chroma_store import ChromaMemoryStore, create_store
from mcp_server.ocr import OCRConfigurationError, OCRProcessor, OCRResult


PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
)


@pytest.fixture()
def tools(tmp_path):
    config = ServerConfig(home=tmp_path, token="test-token", allowed_folders=(tmp_path,))
    return build_tools(config)


def test_save_and_search_memory(tools):
    memory_id = tools.save_memory("The lease PDF deadline is Friday", "manual")

    results = tools.search_memory("lease deadline", limit=3)

    assert memory_id
    assert results[0]["text"] == "The lease PDF deadline is Friday"
    assert results[0]["collection"] == "misc"


def test_ingest_routes_collection_and_find_file(tools, tmp_path):
    file_path = tmp_path / "lease.pdf"
    tools.ingest(
        "Lease agreement with renewal clause",
        "filesystem",
        {"path": str(file_path), "summary": "Lease agreement summary", "timestamp": datetime.now(timezone.utc).isoformat()},
    )

    files = tools.find_file("renewal lease")
    summary = tools.summarize_file(str(file_path))

    assert files[0]["collection"] == "filesystem"
    assert summary == "Lease agreement summary"


def test_summarize_file_rejects_disallowed_path(tmp_path):
    config = ServerConfig(home=tmp_path, token="test-token", allowed_folders=(tmp_path / "allowed",))
    local_tools = build_tools(config)

    with pytest.raises(PermissionError):
        local_tools.summarize_file("/private/nope.pdf")


def test_recent_context_and_screenshot_search(tools):
    tools.ingest(
        "Figma wireframe for dashboard",
        "browser",
        {"summary": "Dashboard wireframe", "screenshot_path": "/tmp/screen.jpg"},
    )

    recent = tools.get_recent_context("1h")
    screenshots = tools.find_screenshot("dashboard")

    assert recent
    assert screenshots[0]["screenshot_path"] == "/tmp/screen.jpg"


def test_auth_header_validation():
    auth = TokenAuth("secret")
    auth.validate_header("Bearer secret")

    with pytest.raises(AuthError):
        auth.validate_header("Bearer wrong")


def test_http_app_health_and_auth(tmp_path):
    pytest.importorskip("fastapi")
    from fastapi.testclient import TestClient

    app = create_app(ServerConfig(home=tmp_path, token="http-token"))
    client = TestClient(app)

    health = client.get("/health").json()
    assert health["ok"] is True
    assert health["memory"]["collections"] == list(COLLECTIONS)
    assert client.post("/ingest", json={"text": "blocked"}).status_code == 401
    response = client.post(
        "/ingest",
        headers={"Authorization": "Bearer http-token"},
        json={"text": "ChatGPT tunnel note", "collection": "misc", "metadata": {"source": "test"}},
    )
    assert response.status_code == 200
    search = client.post(
        "/tools/search_memory",
        headers={"Authorization": "Bearer http-token"},
        json={"arguments": {"query": "tunnel", "limit": 1}},
    )
    assert search.json()[0]["text"] == "ChatGPT tunnel note"


def test_ingest_screenshot_runs_python_ocr_and_routes_collection(monkeypatch, tmp_path):
    pytest.importorskip("fastapi")
    from fastapi.testclient import TestClient

    async def fake_process(self, image_base64: str, mime_type: str):
        assert mime_type == "image/png"
        assert base64.b64decode(image_base64).startswith(b"\x89PNG")
        return OCRResult(
            text="Slack screenshot says launch review is Monday",
            collection="messages",
            summary="Launch review Slack screenshot",
        )

    monkeypatch.setattr("mcp_server.main.OCRProcessor.process", fake_process)
    app = create_app(ServerConfig(home=tmp_path, token="http-token"))
    client = TestClient(app)

    response = client.post(
        "/ingest_screenshot",
        headers={"Authorization": "Bearer http-token"},
        json={
            "image_base64": base64.b64encode(PNG_1X1).decode("ascii"),
            "mime_type": "image/png",
            "metadata": {"source": "manual-test"},
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["collection"] == "messages"
    assert body["metadata"]["summary"] == "Launch review Slack screenshot"
    screenshot_path = body["metadata"]["screenshot_path"]
    assert screenshot_path.endswith(".png")
    assert (tmp_path / "screenshots").exists()


def test_ingest_screenshot_requires_openai_key(monkeypatch, tmp_path):
    pytest.importorskip("fastapi")
    from fastapi.testclient import TestClient

    async def fake_process(self, image_base64: str, mime_type: str):
        raise OCRConfigurationError("OPENAI_API_KEY is not set")

    monkeypatch.setattr("mcp_server.main.OCRProcessor.process", fake_process)
    app = create_app(ServerConfig(home=tmp_path, token="http-token"))
    client = TestClient(app)

    response = client.post(
        "/ingest_screenshot",
        headers={"Authorization": "Bearer http-token"},
        json={"image_base64": base64.b64encode(PNG_1X1).decode("ascii"), "mime_type": "image/png"},
    )

    assert response.status_code == 503
    assert response.json()["detail"] == "OPENAI_API_KEY is not set"


def test_ingest_screenshot_stores_fallback_when_ocr_parse_fails(monkeypatch, tmp_path):
    pytest.importorskip("fastapi")
    from fastapi.testclient import TestClient

    async def fake_process(self, image_base64: str, mime_type: str):
        raise ValueError("OpenAI OCR response did not include output text")

    monkeypatch.setattr("mcp_server.main.OCRProcessor.process", fake_process)
    app = create_app(ServerConfig(home=tmp_path, token="http-token"))
    client = TestClient(app)

    response = client.post(
        "/ingest_screenshot",
        headers={"Authorization": "Bearer http-token"},
        json={"image_base64": base64.b64encode(PNG_1X1).decode("ascii"), "mime_type": "image/png"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["collection"] == "misc"
    assert "OCR failed" in body["text"]
    assert body["metadata"]["screenshot_path"].endswith(".png")


def test_ingest_screenshot_rejects_undecodable_image(tmp_path):
    pytest.importorskip("fastapi")
    from fastapi.testclient import TestClient

    app = create_app(ServerConfig(home=tmp_path, token="http-token"))
    client = TestClient(app)

    response = client.post(
        "/ingest_screenshot",
        headers={"Authorization": "Bearer http-token"},
        json={"image_base64": "aGVsbG8=", "mime_type": "image/png"},
    )

    assert response.status_code == 422
    assert response.json()["detail"] == "image data could not be decoded"


def test_ocr_parser_accepts_fenced_json():
    result = OCRProcessor._parse_response(
        {
            "output_text": (
                "```json\n"
                '{"text":"Slack launch note","collection":"messages","summary":"Launch note"}'
                "\n```"
            )
        }
    )

    assert result.text == "Slack launch note"
    assert result.collection == "messages"


def test_ocr_parser_falls_back_to_misc_for_plain_text(caplog):
    with caplog.at_level("WARNING"):
        result = OCRProcessor._parse_response({"output_text": "The screenshot shows a terminal error."})

    assert result.collection == "misc"
    assert result.text == "The screenshot shows a terminal error."
    assert "OpenAI OCR response was not JSON" in caplog.text


def test_ocr_parser_falls_back_when_output_text_missing(caplog):
    with caplog.at_level("WARNING"):
        result = OCRProcessor._parse_response({"output": [{"content": []}]})

    assert result.collection == "misc"
    assert "returned no OCR text" in result.text
    assert "did not include output text" in caplog.text


def test_chroma_store_creates_and_routes_required_collections(monkeypatch, tmp_path):
    created: dict[str, FakeChromaCollection] = {}

    class FakePersistentClient:
        def __init__(self, path: str):
            self.path = path

        def get_or_create_collection(self, name: str, metadata: dict):
            collection = FakeChromaCollection(name, metadata)
            created[name] = collection
            return collection

    monkeypatch.setitem(sys.modules, "chromadb", SimpleNamespace(PersistentClient=FakePersistentClient))

    store = ChromaMemoryStore(tmp_path / "chroma")
    store.add(
        "Slack message about launch",
        "messages",
        {"source": "slack", "summary": "Launch message", "screenshot_path": "/tmp/slack.jpg"},
    )
    store.add("Finder showed lease.pdf", "filesystem", {"source": "/tmp/lease.pdf", "path": "/tmp/lease.pdf"})
    store.add("Unknown content", "unknown", {"source": "manual"})

    assert set(created) == set(COLLECTIONS)
    assert created["messages"].documents[0] == "Slack message about launch"
    assert created["messages"].metadatas[0]["collection"] == "messages"
    assert created["filesystem"].metadatas[0]["path"] == "/tmp/lease.pdf"
    assert created["misc"].metadatas[0]["collection"] == "misc"


def test_chroma_store_logs_ready_collections(monkeypatch, tmp_path, caplog):
    class FakePersistentClient:
        def __init__(self, path: str):
            self.path = path

        def get_or_create_collection(self, name: str, metadata: dict):
            return FakeChromaCollection(name, metadata)

    monkeypatch.setitem(sys.modules, "chromadb", SimpleNamespace(PersistentClient=FakePersistentClient))

    with caplog.at_level("INFO"):
        store = ChromaMemoryStore(tmp_path / "chroma")

    assert store.backend == "chroma"
    assert store.mode == "embedded"
    assert "Chroma is working in embedded mode" in caplog.text
    for collection in COLLECTIONS:
        assert f"Chroma collection ready: {collection}" in caplog.text


def test_create_store_logs_sqlite_fallback(monkeypatch, tmp_path, caplog):
    monkeypatch.setitem(sys.modules, "chromadb", None)

    with caplog.at_level("INFO"):
        store = create_store(tmp_path / "contextkit.sqlite3", use_chroma=True, chroma_path=tmp_path / "chroma")

    assert store.backend == "sqlite"
    assert "Chroma unavailable, falling back to SQLite" in caplog.text


class FakeChromaCollection:
    def __init__(self, name: str, metadata: dict):
        self.name = name
        self.metadata = metadata
        self.ids: list[str] = []
        self.documents: list[str] = []
        self.metadatas: list[dict] = []
        self.embeddings: list[list[float]] = []

    def upsert(self, ids, documents, embeddings, metadatas):
        self.ids.extend(ids)
        self.documents.extend(documents)
        self.embeddings.extend(embeddings)
        self.metadatas.extend(metadatas)
