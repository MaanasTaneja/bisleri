from __future__ import annotations

from datetime import datetime, timezone

import pytest

from mcp_server.auth import AuthError, TokenAuth
from mcp_server.config import ServerConfig
from mcp_server.main import build_tools, create_app


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

    assert client.get("/health").json()["ok"] is True
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
