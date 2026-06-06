from __future__ import annotations

from dataclasses import dataclass


class AuthError(PermissionError):
    pass


@dataclass(frozen=True)
class TokenAuth:
    token: str

    def validate_header(self, authorization: str | None) -> None:
        expected = f"Bearer {self.token}"
        if not authorization or authorization.strip() != expected:
            raise AuthError("missing or invalid bearer token")
