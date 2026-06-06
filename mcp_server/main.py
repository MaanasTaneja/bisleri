import argparse
from typing import Any

from mcp_server.access_log import AccessLogger
from mcp_server.auth import AuthError, TokenAuth
from mcp_server.config import ServerConfig
from mcp_server.memory.chroma_store import create_store
from mcp_server.tools import ContextKitTools


def build_tools(config: ServerConfig) -> ContextKitTools:
    config.prepare()
    store = create_store(config.db_path, config.use_chroma, config.chroma_path)
    access_logger = AccessLogger(config.db_path)
    return ContextKitTools(config, store, access_logger)


def create_app(config: ServerConfig):
    try:
        from fastapi import Body, Depends, FastAPI, Header, HTTPException
        from pydantic import BaseModel, Field
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("Install server dependencies with `pip install -r mcp_server/requirements.txt`.") from exc

    tools = build_tools(config)
    auth = TokenAuth(config.token)
    app = FastAPI(title="ContextKit Local MCP Server")

    class IngestRequest(BaseModel):
        text: str
        collection: str = "misc"
        metadata: dict[str, Any] = Field(default_factory=dict)

    class ToolRequest(BaseModel):
        arguments: dict[str, Any] = Field(default_factory=dict)

    def require_auth(authorization: str | None = Header(default=None)) -> None:
        try:
            auth.validate_header(authorization)
        except AuthError as exc:
            raise HTTPException(status_code=401, detail=str(exc)) from exc

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {"ok": True, "service": "contextkit", "port": config.port}

    @app.post("/ingest", dependencies=[Depends(require_auth)])
    def ingest(request: IngestRequest = Body(...)) -> dict[str, Any]:
        return tools.ingest(request.text, request.collection, request.metadata)

    @app.post("/tools/{tool_name}", dependencies=[Depends(require_auth)])
    def call_tool(tool_name: str, request: ToolRequest = Body(...)) -> Any:
        if not hasattr(tools, tool_name):
            raise HTTPException(status_code=404, detail="unknown tool")
        tool = getattr(tools, tool_name)
        try:
            return tool(**request.arguments)
        except PermissionError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc

    @app.get("/access-log", dependencies=[Depends(require_auth)])
    def access_log(limit: int = 50) -> list[dict[str, Any]]:
        return tools.access_log(limit)

    return app


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the ContextKit local MCP server.")
    parser.add_argument("--port", type=int)
    parser.add_argument("--token")
    args = parser.parse_args()
    config = ServerConfig.from_env(port=args.port, token=args.token)

    try:
        import uvicorn
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("Install server dependencies with `pip install -r mcp_server/requirements.txt`.") from exc

    uvicorn.run(create_app(config), host=config.host, port=config.port)


if __name__ == "__main__":
    main()
