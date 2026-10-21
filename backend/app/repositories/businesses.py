from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.business import Business
from app.models.business_membership import BusinessMembership
from app.models.enums import MembershipRole


@dataclass(frozen=True)
class BusinessWithRole:
    business: Business
    role: MembershipRole


class BusinessRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list_for_user(self, user_id: UUID) -> list[BusinessWithRole]:
        rows = self.db.execute(
            select(Business, BusinessMembership.role)
            .join(BusinessMembership, BusinessMembership.business_id == Business.id)
            .where(
                BusinessMembership.user_id == user_id,
                BusinessMembership.is_active.is_(True),
                BusinessMembership.suspended_at.is_(None),
                Business.is_active.is_(True),
                Business.suspended_at.is_(None),
            )
            .order_by(Business.name, Business.id)
        ).all()
        return [BusinessWithRole(business=business, role=role) for business, role in rows]

    def add(self, business: Business) -> None:
        self.db.add(business)
