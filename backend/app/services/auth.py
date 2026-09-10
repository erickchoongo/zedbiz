import hmac
from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import AuthenticationError, DuplicateEmailError
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    hash_refresh_token,
    new_token_id,
    verify_password,
)
from app.core.time import ensure_utc, utc_now
from app.models.refresh_session import RefreshSession
from app.models.user import User
from app.models.audit_log import AuditLog
from app.repositories.refresh_sessions import RefreshSessionRepository
from app.repositories.users import UserRepository
from app.schemas.auth import LoginRequest, RegisterRequest

_DUMMY_PASSWORD_HASH = hash_password("not-a-real-user-password")


@dataclass(frozen=True)
class TokenBundle:
    access_token: str
    refresh_token: str
    expires_in: int
    refresh_expires_in: int


class AuthService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.users = UserRepository(db)
        self.refresh_sessions = RefreshSessionRepository(db)

    def register(self, request: RegisterRequest) -> TokenBundle:
        if self.users.get_by_email(str(request.email)) is not None:
            raise DuplicateEmailError
        user = User(
            email=str(request.email),
            full_name=request.full_name,
            password_hash=hash_password(request.password.get_secret_value()),
        )
        self.users.add(user)
        try:
            self.db.flush()
            bundle = self._issue_token_bundle(user)
            self.db.commit()
        except IntegrityError as exc:
            self.db.rollback()
            raise DuplicateEmailError from exc
        except Exception:
            self.db.rollback()
            raise
        return bundle

    def login(self, request: LoginRequest) -> TokenBundle:
        user = self.users.get_by_email(str(request.email))
        password = request.password.get_secret_value()
        if user is None:
            verify_password(password, _DUMMY_PASSWORD_HASH)
            raise AuthenticationError
        if not verify_password(password, user.password_hash) or not user.is_active:
            raise AuthenticationError
        try:
            bundle = self._issue_token_bundle(user)
            self.db.add(AuditLog(actor_user_id=user.id, action='session.login', entity_type='user', entity_id=user.id, metadata_json={}))
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise
        return bundle

    def refresh(self, raw_token: str) -> TokenBundle:
        try:
            claims = decode_token(raw_token, "refresh")
        except ValueError as exc:
            raise AuthenticationError from exc
        if claims.token_id is None:
            raise AuthenticationError
        refresh_session = self.refresh_sessions.get_for_update(claims.token_id)
        now = utc_now()
        if (
            refresh_session is None
            or refresh_session.user_id != claims.user_id
            or not hmac.compare_digest(refresh_session.token_hash, hash_refresh_token(raw_token))
            or refresh_session.revoked_at is not None
            or ensure_utc(refresh_session.expires_at) <= now
            or not refresh_session.user.is_active
        ):
            raise AuthenticationError
        refresh_session.revoked_at = now
        refresh_session.last_used_at = now
        try:
            bundle, replacement = self._new_token_bundle(refresh_session.user)
            self.db.flush()
            refresh_session.replaced_by_id = replacement.id
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise
        return bundle

    def logout(self, raw_token: str) -> None:
        try:
            claims = decode_token(raw_token, "refresh")
        except ValueError as exc:
            raise AuthenticationError from exc
        if claims.token_id is None:
            raise AuthenticationError
        refresh_session = self.refresh_sessions.get_for_update(claims.token_id)
        if (
            refresh_session is None
            or refresh_session.user_id != claims.user_id
            or not hmac.compare_digest(refresh_session.token_hash, hash_refresh_token(raw_token))
        ):
            raise AuthenticationError
        if refresh_session.revoked_at is None:
            refresh_session.revoked_at = utc_now()
            self.db.add(AuditLog(actor_user_id=refresh_session.user_id, action='session.logout', entity_type='user', entity_id=refresh_session.user_id, metadata_json={}))
            self.db.commit()

    def _issue_token_bundle(self, user: User) -> TokenBundle:
        bundle, _ = self._new_token_bundle(user)
        return bundle

    def _new_token_bundle(self, user: User) -> tuple[TokenBundle, RefreshSession]:
        token_id = new_token_id()
        refresh_token, refresh_expires_in = create_refresh_token(user.id, token_id)
        access_token, expires_in = create_access_token(user.id)
        refresh_session = RefreshSession(
            id=token_id,
            user_id=user.id,
            token_hash=hash_refresh_token(refresh_token),
            expires_at=utc_now() + timedelta(days=get_settings().refresh_token_expire_days),
        )
        self.refresh_sessions.add(refresh_session)
        return (
            TokenBundle(
                access_token=access_token,
                refresh_token=refresh_token,
                expires_in=expires_in,
                refresh_expires_in=refresh_expires_in,
            ),
            refresh_session,
        )
