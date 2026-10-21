from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.refresh_session import RefreshSession


class RefreshSessionRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_for_update(self, session_id: UUID) -> RefreshSession | None:
        return self.db.scalar(select(RefreshSession).where(RefreshSession.id == session_id).with_for_update())

    def add(self, refresh_session: RefreshSession) -> None:
        self.db.add(refresh_session)

    def revoke_all_for_user(self, user_id: UUID) -> None:
        self.db.execute(
            update(RefreshSession)
            .where(RefreshSession.user_id == user_id, RefreshSession.revoked_at.is_(None))
            .values(revoked_at=utc_now())
        )
