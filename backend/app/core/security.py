import hashlib
from dataclasses import dataclass
from datetime import timedelta
from typing import Literal
from uuid import UUID, uuid4

import jwt
from jwt import InvalidTokenError
from pwdlib import PasswordHash

from app.core.config import get_settings
from app.core.time import utc_now

TokenType = Literal["access", "refresh"]
_ALGORITHM = "HS256"
_password_hash = PasswordHash.recommended()


@dataclass(frozen=True)
class TokenClaims:
    user_id: UUID
    token_type: TokenType
    token_id: UUID | None


def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return _password_hash.verify(password, password_hash)


def create_access_token(user_id: UUID) -> tuple[str, int]:
    settings = get_settings()
    lifetime = timedelta(minutes=settings.access_token_expire_minutes)
    return _encode_token(user_id, "access", lifetime), int(lifetime.total_seconds())


def create_refresh_token(user_id: UUID, token_id: UUID) -> tuple[str, int]:
    settings = get_settings()
    lifetime = timedelta(days=settings.refresh_token_expire_days)
    return _encode_token(user_id, "refresh", lifetime, token_id), int(lifetime.total_seconds())


def _encode_token(user_id: UUID, token_type: TokenType, lifetime: timedelta, token_id: UUID | None = None) -> str:
    now = utc_now()
    payload: dict[str, object] = {
        "sub": str(user_id),
        "type": token_type,
        "iat": now,
        "exp": now + lifetime,
    }
    if token_id is not None:
        payload["jti"] = str(token_id)
    return jwt.encode(payload, get_settings().jwt_secret, algorithm=_ALGORITHM)


def decode_token(token: str, expected_type: TokenType) -> TokenClaims:
    try:
        payload = jwt.decode(
            token,
            get_settings().jwt_secret,
            algorithms=[_ALGORITHM],
            options={"require": ["sub", "type", "iat", "exp"]},
        )
        token_type = payload.get("type")
        if token_type != expected_type:
            raise InvalidTokenError("Unexpected token type")
        user_id = UUID(str(payload["sub"]))
        token_id = UUID(str(payload["jti"])) if expected_type == "refresh" else None
    except (InvalidTokenError, KeyError, TypeError, ValueError) as exc:
        raise ValueError("Invalid or expired token") from exc
    return TokenClaims(user_id=user_id, token_type=expected_type, token_id=token_id)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def new_token_id() -> UUID:
    return uuid4()
