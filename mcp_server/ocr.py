from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Any


SUPPORTED_IMAGE_TYPES = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "image/gif": ".gif"}


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

        payload = {
            "model": self.model,
            "input": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": (
                                "Extract all visible text from this screenshot. Then classify what type of content "
                                "this is. Return only JSON with keys: text, collection, summary. Collection must be "
                                "one of: messages, browser, filesystem, misc."
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
        headers = {"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post("https://api.openai.com/v1/responses", headers=headers, json=payload)
            response.raise_for_status()
        return self._parse_response(response.json())

    @staticmethod
    def _parse_response(payload: dict[str, Any]) -> OCRResult:
        raw_text = payload.get("output_text") or OCRProcessor._extract_output_text(payload)
        if not raw_text:
            raise ValueError("OpenAI OCR response did not include output text")
        try:
            parsed = json.loads(raw_text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"OpenAI OCR response was not JSON: {raw_text[:200]}") from exc
        return OCRResult(
            text=str(parsed.get("text", "")),
            collection=str(parsed.get("collection", "misc")),
            summary=str(parsed.get("summary", "")),
        )

    @staticmethod
    def _extract_output_text(payload: dict[str, Any]) -> str:
        parts: list[str] = []
        for item in payload.get("output", []):
            for content in item.get("content", []):
                if content.get("type") == "output_text" and content.get("text"):
                    parts.append(str(content["text"]))
        return "\n".join(parts)
