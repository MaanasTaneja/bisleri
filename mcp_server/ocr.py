from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass
from typing import Any


SUPPORTED_IMAGE_TYPES = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "image/gif": ".gif"}
COLLECTIONS = {"filesystem", "messages", "browser", "misc"}
logger = logging.getLogger(__name__)

OCR_RESPONSE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "text": {
            "type": "string",
            "description": "All visible text extracted from the screenshot. Use an empty string if no text is visible.",
        },
        "collection": {
            "type": "string",
            "enum": ["messages", "browser", "filesystem", "misc"],
            "description": "The ContextKit memory collection this screenshot belongs in.",
        },
        "summary": {
            "type": "string",
            "description": "A concise one or two sentence description of what the screenshot shows.",
        },
    },
    "required": ["text", "collection", "summary"],
}


@dataclass(frozen=True)
class OCRResult:
    text: str
    collection: str
    summary: str


class OCRConfigurationError(RuntimeError):
    pass


class OCRProcessor:
    def __init__(self, api_key: str | None = None, model: str | None = None) -> None:
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY")
        self.model = model or os.environ.get("OPENAI_OCR_MODEL", "gpt-4o-mini")

    async def process(self, image_base64: str, mime_type: str) -> OCRResult:
        if not self.api_key:
            raise OCRConfigurationError("OPENAI_API_KEY is not set")
        if mime_type not in SUPPORTED_IMAGE_TYPES:
            raise ValueError(f"unsupported image type: {mime_type}")

        try:
            import httpx
        except ImportError as exc:  # pragma: no cover
            raise RuntimeError("httpx is required for OpenAI OCR requests") from exc

        payload = self._build_payload(image_base64, mime_type)
        headers = {"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post("https://api.openai.com/v1/responses", headers=headers, json=payload)
            response.raise_for_status()
        return self._parse_response(response.json())

    def _build_payload(self, image_base64: str, mime_type: str) -> dict[str, Any]:
        return {
            "model": self.model,
            "text": {
                "format": {
                    "type": "json_schema",
                    "name": "contextkit_screenshot_ocr",
                    "strict": True,
                    "schema": OCR_RESPONSE_SCHEMA,
                }
            },
            "input": [
                {
                    "role": "system",
                    "content": [
                        {
                            "type": "input_text",
                            "text": (
                                "You are ContextKit's local screenshot OCR and classifier. "
                                "Extract visible text and summarize what is happening in the picture and classify screenshots for a private local memory database."
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
                                "Analyze the screenshot and output JSON matching the schema. Classification rules: "
                                "messages = iMessage, WhatsApp, Slack, email, or any chat/messaging window; "
                                "browser = web browser, URLs visible, or web content; "
                                "filesystem = Finder, file explorer, code editor, PDF/document viewer, or file path content; "
                                "misc = terminal, settings, clipboard/manual context, or anything else."
                            ),
                        },
                        {
                            "type": "input_image",
                            "image_url": f"data:{mime_type};base64,{image_base64}",
                        },
                    ],
                }
            ],
        }

    @staticmethod
    def fallback_result(message: str) -> OCRResult:
        return OCRResult(text=message, collection="misc", summary=message[:180])

    @staticmethod
    def _parse_response(payload: dict[str, Any]) -> OCRResult:
        raw_text = payload.get("output_text") or OCRProcessor._extract_output_text(payload)
        if not raw_text:
            logger.warning("OpenAI OCR response did not include output text; storing response summary as misc")
            return OCRProcessor.fallback_result("Screenshot captured, but OpenAI returned no OCR text.")
        try:
            parsed = json.loads(OCRProcessor._json_candidate(raw_text))
        except json.JSONDecodeError:
            logger.warning("OpenAI OCR response was not JSON; storing raw OCR text as misc")
            return OCRResult(text=raw_text.strip(), collection="misc", summary=raw_text.strip()[:180])
        return OCRProcessor._coerce_result(parsed)

    @staticmethod
    def _coerce_result(parsed: dict[str, Any]) -> OCRResult:
        collection = str(parsed.get("collection", "misc"))
        if collection not in COLLECTIONS:
            collection = "misc"
        text = str(parsed.get("text", "")).strip()
        summary = str(parsed.get("summary", "")).strip()
        if not summary:
            summary = text[:180] if text else "Screenshot captured"
        return OCRResult(text=text, collection=collection, summary=summary)

    @staticmethod
    def _json_candidate(raw_text: str) -> str:
        stripped = raw_text.strip()
        fence_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", stripped, re.DOTALL)
        if fence_match:
            return fence_match.group(1)
        first = stripped.find("{")
        last = stripped.rfind("}")
        if first != -1 and last > first:
            return stripped[first : last + 1]
        return stripped

    @staticmethod
    def _extract_output_text(payload: dict[str, Any]) -> str:
        parts: list[str] = []
        for item in payload.get("output", []):
            for content in item.get("content", []):
                if content.get("text"):
                    parts.append(str(content["text"]))
                elif content.get("type") == "text" and content.get("value"):
                    parts.append(str(content["value"]))
        return "\n".join(parts)
