"""MCP server over SSE, mounted alongside the FastAPI REST surface.

Exposes the ContextKit tool surface to standard MCP clients (Claude Desktop,
ChatGPT via Secure MCP Tunnel) by translating JSON-RPC tool calls into the
existing ContextKitTools methods. The transport follows the MCP SDK pattern:

  GET  /sse        — SSE stream for server-to-client messages
  POST /messages/  — client-to-server JSON-RPC payloads

A shared mutable flag lets the menu bar app pause memory sharing without
restarting the server.
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any

from mcp_server.tools import ContextKitTools

logger = logging.getLogger(__name__)


@dataclass
class MemorySharingFlag:
    """Mutable container so callers can flip the paused state at runtime."""
    paused: bool = False


_TOOL_SPECS: list[dict[str, Any]] = [
    {
        "name": "search_memory",
        "description": "Semantic search across all enabled memory collections.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "The query text."},
                "limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 10},
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_memory_item",
        "description": "Fetch a single memory item by id.",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string"}},
            "required": ["id"],
        },
    },
    {
        "name": "save_memory",
        "description": "Save a piece of text to the misc memory collection.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "source": {"type": "string", "default": "manual"},
            },
            "required": ["text"],
        },
    },
    {
        "name": "list_sources",
        "description": "List the user's allowed folders and active memory collections.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_recent_context",
        "description": "Return memory items from a recent time window.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "time_range": {
                    "type": "string",
                    "description": "Window such as '1h', '24h', '7d', or 'today'.",
                    "default": "1h",
                },
                "limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 20},
            },
        },
    },
    {
        "name": "delete_memory",
        "description": "Delete a memory item by id.",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string"}},
            "required": ["id"],
        },
    },
    {
        "name": "pause_memory_sharing",
        "description": "Pause or resume MCP tool access to the user's memory.",
        "inputSchema": {
            "type": "object",
            "properties": {"paused": {"type": "boolean"}},
            "required": ["paused"],
        },
    },
]


def tool_specs() -> list[dict[str, Any]]:
    """Plain-dict tool descriptors, useful for tests and introspection."""
    return [dict(spec) for spec in _TOOL_SPECS]


def dispatch_tool(
    tools: ContextKitTools,
    flag: MemorySharingFlag,
    name: str,
    arguments: dict[str, Any] | None,
) -> Any:
    """Translate an MCP tool call into a ContextKitTools method.

    Centralised so the SSE handler and the test suite share the same
    permission/pause logic.
    """
    arguments = dict(arguments or {})

    if name == "pause_memory_sharing":
        flag.paused = bool(arguments.get("paused", False))
        return {"paused": flag.paused}

    if flag.paused:
        raise PermissionError("memory sharing is paused")

    if name == "search_memory":
        return tools.search_memory(str(arguments["query"]), int(arguments.get("limit", 10)))
    if name == "get_memory_item":
        return tools.get_memory_item(str(arguments["id"]))
    if name == "save_memory":
        new_id = tools.save_memory(str(arguments["text"]), str(arguments.get("source", "manual")))
        return {"id": new_id}
    if name == "list_sources":
        return tools.list_allowed_sources()
    if name == "get_recent_context":
        return tools.get_recent_context(
            str(arguments.get("time_range", "1h")),
            int(arguments.get("limit", 20)),
        )
    if name == "delete_memory":
        return tools.delete_memory(str(arguments["id"]))
    raise ValueError(f"unknown tool: {name}")


def mount_mcp_sse(app, tools: ContextKitTools, flag: MemorySharingFlag) -> None:
    """Attach MCP SSE + /messages/ routes to an existing FastAPI app.

    Soft-imports the mcp SDK so the rest of the server still boots if it
    is not installed yet (the wizard's backend setup step pip-installs
    it on first launch).
    """
    try:
        from mcp.server.lowlevel import Server
        from mcp.server.sse import SseServerTransport
        from mcp.types import TextContent, Tool
    except ImportError as exc:  # pragma: no cover - exercised only when sdk missing
        logger.warning("mcp SDK not installed; /sse and /messages/ disabled: %s", exc)
        return

    server = Server("contextkit")

    @server.list_tools()
    async def _list_tools() -> list[Tool]:
        return [
            Tool(
                name=spec["name"],
                description=spec["description"],
                inputSchema=spec["inputSchema"],
            )
            for spec in _TOOL_SPECS
        ]

    @server.call_tool()
    async def _call_tool(name: str, arguments: dict[str, Any] | None) -> list[TextContent]:
        try:
            result = dispatch_tool(tools, flag, name, arguments)
        except PermissionError as exc:
            payload = {"error": "forbidden", "detail": str(exc)}
        except ValueError as exc:
            payload = {"error": "bad_request", "detail": str(exc)}
        except Exception as exc:  # pragma: no cover - defensive
            logger.exception("MCP tool %s failed", name)
            payload = {"error": "internal", "detail": str(exc)}
        else:
            payload = result
        return [TextContent(type="text", text=json.dumps(payload, default=str))]

    transport = SseServerTransport("/messages/")

    from starlette.responses import Response
    from starlette.routing import Mount, Route

    async def sse_endpoint(request):
        async with transport.connect_sse(
            request.scope,
            request.receive,
            request._send,
        ) as streams:
            await server.run(
                streams[0],
                streams[1],
                server.create_initialization_options(),
            )
        return Response()

    app.router.routes.append(Route("/sse", endpoint=sse_endpoint, methods=["GET"]))
    app.router.routes.append(Mount("/messages/", app=transport.handle_post_message))
    logger.info("ContextKit MCP SSE routes mounted at /sse and /messages/")
