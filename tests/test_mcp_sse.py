"""Tests for the MCP SSE tool surface.

We test the dispatch layer directly because the SSE transport is an
implementation detail of the mcp SDK — the contract worth pinning is
the tool names, schemas, and the pause/permission semantics.
"""
from __future__ import annotations

import pytest

from mcp_server.config import ServerConfig
from mcp_server.main import build_tools
from mcp_server.mcp_sse import MemorySharingFlag, dispatch_tool, tool_specs


EXPECTED_TOOL_NAMES = {
    "search_memory",
    "get_memory_item",
    "save_memory",
    "list_sources",
    "get_recent_context",
    "delete_memory",
    "pause_memory_sharing",
}


@pytest.fixture()
def tools(tmp_path):
    config = ServerConfig(home=tmp_path, token="test-token", allowed_folders=(tmp_path,))
    return build_tools(config)


@pytest.fixture()
def flag():
    return MemorySharingFlag()


def test_tool_specs_match_plan():
    specs = tool_specs()
    names = {spec["name"] for spec in specs}
    assert names == EXPECTED_TOOL_NAMES

    for spec in specs:
        assert "description" in spec
        schema = spec["inputSchema"]
        assert schema["type"] == "object"
        assert "properties" in schema


def test_dispatch_save_and_search(tools, flag):
    saved = dispatch_tool(tools, flag, "save_memory", {"text": "ship the docs", "source": "test"})
    assert "id" in saved

    results = dispatch_tool(tools, flag, "search_memory", {"query": "ship docs", "limit": 3})
    assert any("ship the docs" in item["text"] for item in results)


def test_dispatch_get_and_delete(tools, flag):
    saved = dispatch_tool(tools, flag, "save_memory", {"text": "deletable note"})
    memory_id = saved["id"]

    fetched = dispatch_tool(tools, flag, "get_memory_item", {"id": memory_id})
    assert fetched and fetched["id"] == memory_id

    deleted = dispatch_tool(tools, flag, "delete_memory", {"id": memory_id})
    assert deleted["deleted"] is True

    missing = dispatch_tool(tools, flag, "get_memory_item", {"id": memory_id})
    assert missing is None


def test_pause_blocks_other_tools(tools, flag):
    paused = dispatch_tool(tools, flag, "pause_memory_sharing", {"paused": True})
    assert paused == {"paused": True}

    with pytest.raises(PermissionError):
        dispatch_tool(tools, flag, "search_memory", {"query": "anything"})

    resumed = dispatch_tool(tools, flag, "pause_memory_sharing", {"paused": False})
    assert resumed == {"paused": False}

    # Resumes cleanly.
    dispatch_tool(tools, flag, "search_memory", {"query": "anything"})


def test_unknown_tool_raises(tools, flag):
    with pytest.raises(ValueError):
        dispatch_tool(tools, flag, "bogus_tool", {})


def test_list_sources_returns_folders_and_collections(tools, flag):
    result = dispatch_tool(tools, flag, "list_sources", {})
    kinds = {entry["type"] for entry in result}
    assert kinds == {"folder", "collection"}
