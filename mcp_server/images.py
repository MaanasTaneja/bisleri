from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO
import logging

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class NormalizedImage:
    data: bytes
    mime_type: str

    @property
    def base64_mime_type(self) -> str:
        return self.mime_type


def normalize_image_for_openai(image_bytes: bytes, mime_type: str) -> NormalizedImage:
    try:
        from PIL import Image, ImageOps
    except ImportError:
        logger.warning("Pillow is not installed; sending %s image to OpenAI without normalization", mime_type)
        return NormalizedImage(data=image_bytes, mime_type=mime_type)

    try:
        with Image.open(BytesIO(image_bytes)) as image:
            image.load()
            image = ImageOps.exif_transpose(image)
            if image.mode not in ("RGB", "RGBA"):
                image = image.convert("RGB")
            output = BytesIO()
            image.save(output, format="PNG", optimize=True)
    except Exception as exc:
        raise ValueError("image data could not be decoded") from exc

    return NormalizedImage(data=output.getvalue(), mime_type="image/png")
