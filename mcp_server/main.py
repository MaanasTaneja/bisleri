import argparse
import asyncio
import base64
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

from mcp_server.access_log import AccessLogger
from mcp_server.auth import AuthError, TokenAuth
from mcp_server.config import ServerConfig
from mcp_server.file_processor import (
    MAX_FILE_BYTES,
    FileConfigurationError,
    FileProcessingError,
    extract_text,
    summarize_file,
)
from mcp_server.images import normalize_image_for_openai
from mcp_server.mcp_sse import MemorySharingFlag, mount_mcp_sse
from mcp_server.memory.chroma_store import create_store
from mcp_server.ocr import OCRConfigurationError, OCRProcessor, SUPPORTED_IMAGE_TYPES
from mcp_server.tools import BrainDeadTools

logger = logging.getLogger(__name__)


class _MessagesRateLimitMiddleware:
    """Per-client token-bucket rate limit for /messages/ as raw ASGI middleware.

    Implemented at ASGI level (not via FastAPI's BaseHTTPMiddleware) because
    BaseHTTPMiddleware buffers response bodies, which breaks SSE and the
    streaming responses the MCP transport emits from /sse and /messages/.
    """

    def __init__(self, app, window: float, max_requests: int) -> None:
        self.app = app
        self.window = window
        self.max_requests = max_requests
        self.buckets: dict[str, list[float]] = {}

    async def __call__(self, scope, receive, send) -> None:
        if scope.get("type") != "http" or not scope.get("path", "").startswith("/messages/"):
            await self.app(scope, receive, send)
            return

        from time import monotonic
        client = scope.get("client") or ("unknown", 0)
        key = client[0]
        now = monotonic()
        bucket = self.buckets.setdefault(key, [])
        cutoff = now - self.window
        while bucket and bucket[0] < cutoff:
            bucket.pop(0)
        if len(bucket) >= self.max_requests:
            await send({
                "type": "http.response.start",
                "status": 429,
                "headers": [(b"content-type", b"application/json")],
            })
            await send({
                "type": "http.response.body",
                "body": b'{"error":"rate_limited","detail":"too many MCP requests"}',
            })
            return
        bucket.append(now)
        await self.app(scope, receive, send)


def build_tools(config: ServerConfig) -> BrainDeadTools:
    config.prepare()
    store = create_store(config.db_path, config.use_chroma, config.chroma_path, collections=config.load_collections())
    access_logger = AccessLogger(config.db_path)
    tools = BrainDeadTools(config, store, access_logger)
    logger.info("BrainDead server memory status: %s", tools.memory_status())
    return tools


def create_app(config: ServerConfig):
    try:
        from fastapi import Body, Depends, FastAPI, Header, HTTPException
        from pydantic import BaseModel, Field
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("Install server dependencies with `pip install -r mcp_server/requirements.txt`.") from exc

    tools = build_tools(config)
    auth = TokenAuth(config.token)
    sharing_flag = MemorySharingFlag()
    app = FastAPI(title="BrainDead Local MCP Server")
    screenshot_jobs: dict[str, dict[str, Any]] = {}
    active_screenshot_job_id: str | None = None

    rate_limit_window = float(os.environ.get("BRAINDEAD_MCP_RATE_WINDOW", "1.0"))
    rate_limit_max = int(os.environ.get("BRAINDEAD_MCP_RATE_MAX", "30"))

    app.add_middleware(
        _MessagesRateLimitMiddleware,
        window=rate_limit_window,
        max_requests=rate_limit_max,
    )

    class IngestRequest(BaseModel):
        text: str
        collection: str = "misc"
        metadata: dict[str, Any] = Field(default_factory=dict)

    class ScreenshotIngestRequest(BaseModel):
        image_base64: str
        mime_type: str = "image/png"
        metadata: dict[str, Any] = Field(default_factory=dict)

    class FileIngestRequest(BaseModel):
        filename: str
        mime_type: str = "application/octet-stream"
        content_base64: str
        metadata: dict[str, Any] = Field(default_factory=dict)

    class ToolRequest(BaseModel):
        arguments: dict[str, Any] = Field(default_factory=dict)

    def require_auth(authorization: str | None = Header(default=None)) -> None:
        try:
            auth.validate_header(authorization)
        except AuthError as exc:
            raise HTTPException(status_code=401, detail=str(exc)) from exc

    async def process_screenshot_request(request: ScreenshotIngestRequest) -> dict[str, Any]:
        if request.mime_type not in SUPPORTED_IMAGE_TYPES:
            raise HTTPException(status_code=422, detail=f"unsupported image type: {request.mime_type}")
        try:
            image_bytes = base64.b64decode(request.image_base64, validate=True)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail="image_base64 is not valid base64") from exc
        try:
            normalized = normalize_image_for_openai(image_bytes, request.mime_type)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

        normalized_base64 = base64.b64encode(normalized.data).decode("ascii")
        screenshot_path = _write_screenshot(config, normalized.data, normalized.mime_type)
        try:
            result = await OCRProcessor(collections=tuple(tools.list_collections())).process(
                normalized_base64,
                normalized.base64_mime_type,
            )
        except OCRConfigurationError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except Exception as exc:
            logger.warning("Screenshot OCR failed after image was accepted; storing fallback memory: %s", exc)
            result = OCRProcessor.fallback_result(f"Screenshot captured, but OCR failed: {exc}")

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

    async def run_screenshot_job(job_id: str, request: ScreenshotIngestRequest) -> None:
        nonlocal active_screenshot_job_id
        try:
            result = await process_screenshot_request(request)
        except HTTPException as exc:
            screenshot_jobs[job_id].update(
                {
                    "status": "failed",
                    "error": str(exc.detail),
                    "status_code": exc.status_code,
                    "completed_at": datetime.now(timezone.utc).isoformat(),
                }
            )
        except Exception as exc:
            logger.exception("Screenshot job %s failed", job_id)
            screenshot_jobs[job_id].update(
                {
                    "status": "failed",
                    "error": str(exc),
                    "status_code": 500,
                    "completed_at": datetime.now(timezone.utc).isoformat(),
                }
            )
        else:
            screenshot_jobs[job_id].update(
                {
                    "status": "completed",
                    "result": result,
                    "completed_at": datetime.now(timezone.utc).isoformat(),
                }
            )
        finally:
            if active_screenshot_job_id == job_id:
                active_screenshot_job_id = None

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {"ok": True, "service": "braindead", "port": config.port, "memory": tools.memory_status()}

    @app.get("/collections", dependencies=[Depends(require_auth)])
    def list_collections() -> list[str]:
        return tools.list_collections()

    @app.post("/collections", dependencies=[Depends(require_auth)], status_code=201)
    def create_collection(request: ToolRequest = Body(...)) -> dict[str, Any]:
        name = str(request.arguments.get("name", ""))
        try:
            return tools.create_collection(name)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

    @app.post("/ingest", dependencies=[Depends(require_auth)])
    def ingest(request: IngestRequest = Body(...)) -> dict[str, Any]:
        return tools.ingest(request.text, request.collection, request.metadata)

    @app.post("/ingest_screenshot", dependencies=[Depends(require_auth)])
    async def ingest_screenshot(request: ScreenshotIngestRequest = Body(...)) -> dict[str, Any]:
        return await process_screenshot_request(request)

    @app.post("/ingest_file", dependencies=[Depends(require_auth)])
    async def ingest_file(request: FileIngestRequest = Body(...)) -> dict[str, Any]:
        try:
            file_bytes = base64.b64decode(request.content_base64, validate=True)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail="content_base64 is not valid base64") from exc
        if len(file_bytes) > MAX_FILE_BYTES:
            raise HTTPException(
                status_code=413,
                detail=f"file exceeds {MAX_FILE_BYTES} byte limit",
            )
        try:
            text = extract_text(request.filename, request.mime_type, file_bytes)
        except FileProcessingError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        try:
            result = await summarize_file(
                request.filename,
                text,
                collections=tuple(tools.list_collections()),
            )
        except FileConfigurationError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc

        metadata = dict(request.metadata)
        metadata.update(
            {
                "source": metadata.get("source", "file_upload"),
                "filename": request.filename,
                "mime_type": request.mime_type,
                "file_size": len(file_bytes),
                "summary": result.summary,
                "timestamp": metadata.get("timestamp", datetime.now(timezone.utc).isoformat()),
            }
        )
        return tools.ingest(result.text, result.collection, metadata)

    @app.post("/screenshot_jobs", dependencies=[Depends(require_auth)], status_code=202)
    async def create_screenshot_job(request: ScreenshotIngestRequest = Body(...)) -> dict[str, Any]:
        nonlocal active_screenshot_job_id
        if active_screenshot_job_id:
            raise HTTPException(status_code=409, detail="screenshot processing already in progress")
        job_id = uuid4().hex
        now = datetime.now(timezone.utc).isoformat()
        screenshot_jobs[job_id] = {"id": job_id, "status": "processing", "created_at": now}
        active_screenshot_job_id = job_id
        asyncio.create_task(run_screenshot_job(job_id, request))
        return screenshot_jobs[job_id]

    @app.get("/screenshot_jobs/{job_id}", dependencies=[Depends(require_auth)])
    def screenshot_job(job_id: str) -> dict[str, Any]:
        job = screenshot_jobs.get(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="unknown screenshot job")
        return job

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

    @app.get("/mcp/status")
    def mcp_status() -> dict[str, Any]:
        return {"paused": sharing_flag.paused, "sse_url": f"http://{config.host}:{config.port}/sse"}

    mount_mcp_sse(app, tools, sharing_flag)
    return app


def _write_screenshot(config: ServerConfig, image_bytes: bytes, mime_type: str) -> Path:
    suffix = SUPPORTED_IMAGE_TYPES[mime_type]
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = config.screenshots_dir / f"{timestamp}{suffix}"
    path.write_bytes(image_bytes)
    return path


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    parser = argparse.ArgumentParser(description="Run the BrainDead local MCP server.")
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
