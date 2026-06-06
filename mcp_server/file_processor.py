from __future__ import annotations

import io
import json
import logging
import os
import re
from dataclasses import dataclass
from typing import Any

from mcp_server.config import COLLECTIONS, normalize_collections

logger = logging.getLogger(__name__)

MAX_FILE_BYTES = 10 * 1024 * 1024
SUMMARY_PROMPT_TEXT_LIMIT = 60_000


class FileProcessingError(RuntimeError):
    pass


class FileConfigurationError(RuntimeError):
    pass


@dataclass(frozen=True)
class FileSummary:
    text: str
    collection: str
    summary: str


def extract_text(filename: str, mime_type: str, data: bytes) -> str:
    name = (filename or "").lower()
    mt = (mime_type or "").lower()

    if mt == "application/pdf" or name.endswith(".pdf"):
        return _extract_pdf(data)

    if mt.startswith("text/") or _looks_textual(name, mt):
        return _decode_text(data)

    try:
        return _decode_text(data)
    except FileProcessingError:
        raise FileProcessingError(f"unsupported file type: {mime_type or name or 'unknown'}")


def _looks_textual(name: str, mime_type: str) -> bool:
    if mime_type in {
        "application/json",
        "application/xml",
        "application/javascript",
        "application/x-yaml",
        "application/yaml",
        "application/sql",
        "application/x-sh",
    }:
        return True
    text_exts = (
        ".txt", ".md", ".markdown", ".rst", ".log", ".csv", ".tsv",
        ".json", ".jsonl", ".yaml", ".yml", ".xml", ".html", ".htm",
        ".py", ".js", ".ts", ".tsx", ".jsx", ".swift", ".go", ".rs",
        ".java", ".kt", ".rb", ".php", ".c", ".h", ".cpp", ".hpp",
        ".cs", ".sh", ".bash", ".zsh", ".sql", ".toml", ".ini", ".cfg", ".env",
    )
    return name.endswith(text_exts)


def _decode_text(data: bytes) -> str:
    for encoding in ("utf-8", "utf-16", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise FileProcessingError("unable to decode file as text")


def _extract_pdf(data: bytes) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise FileProcessingError(
            "PDF support requires pypdf; add it to requirements.txt"
        ) from exc
    reader = PdfReader(io.BytesIO(data))
    pages = []
    for page in reader.pages:
        try:
            pages.append(page.extract_text() or "")
        except Exception as exc:
            logger.warning("PDF page extraction failed: %s", exc)
    text = "\n".join(p for p in pages if p).strip()
    if not text:
        raise FileProcessingError("PDF contained no extractable text")
    return text


def _summary_schema(collections: tuple[str, ...]) -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "collection": {
                "type": "string",
                "enum": list(normalize_collections(list(collections))),
                "description": "ContextKit memory collection this file belongs in.",
            },
            "summary": {
                "type": "string",
                "description": "One or two sentence description of what the file contains.",
            },
        },
        "required": ["collection", "summary"],
    }


async def summarize_file(
    filename: str,
    text: str,
    collections: tuple[str, ...] = COLLECTIONS,
    api_key: str | None = None,
    model: str | None = None,
) -> FileSummary:
    allowed = normalize_collections(list(collections))
    if not text.strip():
        return FileSummary(text=text, collection="misc", summary=f"Empty file: {filename}")

    key = api_key or os.environ.get("OPENAI_API_KEY")
    if not key:
        return _heuristic_summary(filename, text, allowed)

    chosen_model = model or os.environ.get("OPENAI_FILE_MODEL") or os.environ.get("OPENAI_OCR_MODEL", "gpt-4o-mini")

    try:
        import httpx
    except ImportError as exc:
        raise FileConfigurationError("httpx is required for file summarization") from exc

    truncated = text[:SUMMARY_PROMPT_TEXT_LIMIT]
    payload = {
        "model": chosen_model,
        "text": {
            "format": {
                "type": "json_schema",
                "name": "contextkit_file_summary",
                "strict": True,
                "schema": _summary_schema(allowed),
            }
        },
        "input": [
            {
                "role": "system",
                "content": [
                    {
                        "type": "input_text",
                        "text": (
                            "You are ContextKit's local file ingestor. "
                            "Read the file contents, produce a concise one or two sentence summary, "
                            "and classify the file into a memory collection."
                        ),
                    }
                ],
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": (
                            f"Filename: {filename}\n"
                            "Classify into a collection: "
                            "'filesystem' for code, documents, PDFs, configs, notes; "
                            "'messages' for chat/email transcripts; "
                            "'browser' for web pages or HTML captures; "
                            "'misc' if unclear. "
                            "Custom collections may also appear; only pick one if the file clearly fits.\n\n"
                            "File contents:\n" + truncated
                        ),
                    }
                ],
            },
        ],
    }
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post("https://api.openai.com/v1/responses", headers=headers, json=payload)
            response.raise_for_status()
            data = response.json()
    except Exception as exc:
        logger.warning("File summarization via OpenAI failed; using heuristic: %s", exc)
        return _heuristic_summary(filename, text, allowed)

    raw_text = data.get("output_text") or _extract_output_text(data)
    if not raw_text:
        return _heuristic_summary(filename, text, allowed)

    try:
        parsed = json.loads(_json_candidate(raw_text))
    except json.JSONDecodeError:
        return _heuristic_summary(filename, text, allowed)

    collection = str(parsed.get("collection", "misc"))
    if collection not in allowed:
        collection = "misc"
    summary = str(parsed.get("summary", "")).strip() or f"File: {filename}"
    return FileSummary(text=text, collection=collection, summary=summary)


def _heuristic_summary(filename: str, text: str, allowed: tuple[str, ...]) -> FileSummary:
    collection = "filesystem" if "filesystem" in allowed else "misc"
    snippet = " ".join(text.split())[:180]
    summary = f"{filename}: {snippet}" if snippet else f"File: {filename}"
    return FileSummary(text=text, collection=collection, summary=summary[:240])


def _json_candidate(raw_text: str) -> str:
    stripped = raw_text.strip()
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", stripped, re.DOTALL)
    if fence:
        return fence.group(1)
    first = stripped.find("{")
    last = stripped.rfind("}")
    if first != -1 and last > first:
        return stripped[first : last + 1]
    return stripped


def _extract_output_text(payload: dict[str, Any]) -> str:
    parts: list[str] = []
    for item in payload.get("output", []):
        for content in item.get("content", []):
            if content.get("text"):
                parts.append(str(content["text"]))
            elif content.get("type") == "text" and content.get("value"):
                parts.append(str(content["value"]))
    return "\n".join(parts)
