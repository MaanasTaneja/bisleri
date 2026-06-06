import argparse
import base64
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mcp_server.access_log import AccessLogger
from mcp_server.auth import AuthError, TokenAuth
from mcp_server.config import ServerConfig
from mcp_server.memory.chroma_store import create_store
from mcp_server.ocr import OCRConfigurationError, OCRProcessor, SUPPORTED_IMAGE_TYPES
from mcp_server.tools import ContextKitTools

logger = logging.getLogger(__name__)


def build_tools(config: ServerConfig) -> ContextKitTools:
    config.prepare()
    store = create_store(config.db_path, config.use_chroma, config.chroma_path)
    access_logger = AccessLogger(config.db_path)
    tools = ContextKitTools(config, store, access_logger)
    logger.info("ContextKit server memory status: %s", tools.memory_status())
    return tools


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

    class ScreenshotIngestRequest(BaseModel):
        image_base64: str
        mime_type: str = "image/png"
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
        return {"ok": True, "service": "contextkit", "port": config.port, "memory": tools.memory_status()}

    @app.post("/ingest", dependencies=[Depends(require_auth)])
    def ingest(request: IngestRequest = Body(...)) -> dict[str, Any]:
        return tools.ingest(request.text, request.collection, request.metadata)

    @app.post("/ingest_screenshot", dependencies=[Depends(require_auth)])
    async def ingest_screenshot(request: ScreenshotIngestRequest = Body(...)) -> dict[str, Any]:
        if request.mime_type not in SUPPORTED_IMAGE_TYPES:
            raise HTTPException(status_code=422, detail=f"unsupported image type: {request.mime_type}")
        try:
            image_bytes = base64.b64decode(request.image_base64, validate=True)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail="image_base64 is not valid base64") from exc

        screenshot_path = _write_screenshot(config, image_bytes, request.mime_type)
        try:
            result = await OCRProcessor().process(request.image_base64, request.mime_type)
        except OCRConfigurationError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

        metadata = dict(request.metadata)
        metadata.update(
            {
                "source": metadata.get("source", "screenshot"),
                "summary": result.summary,
                "screenshot_path": str(screenshot_path),
                "timestamp": metadata.get("timestamp", datetime.now(timezone.utc).isoformat()),
            }
        )
        return tools.ingest(result.text, result.collection, metadata)

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


def _write_screenshot(config: ServerConfig, image_bytes: bytes, mime_type: str) -> Path:
    suffix = SUPPORTED_IMAGE_TYPES[mime_type]
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = config.screenshots_dir / f"{timestamp}{suffix}"
    path.write_bytes(image_bytes)
    return path


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
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
