from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import Boolean, CheckConstraint, DateTime, Enum, ForeignKey, Index, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.enums import MembershipRole
from app.models.mixins import TimestampMixin


class BusinessMembership(TimestampMixin, Base):
    __tablename__ = "business_memberships"
    __table_args__ = (
        UniqueConstraint("user_id", "business_id", name="uq_business_memberships_user_business"),
        CheckConstraint(
            "role IN ('OWNER', 'MANAGER', 'CASHIER')",
            name="ck_business_memberships_role",
        ),
        Index("ix_business_memberships_business_active", "business_id", "is_active"),
        Index("ix_business_memberships_user_active", "user_id", "is_active"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    business_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
    role: Mapped[MembershipRole] = mapped_column(
        Enum(MembershipRole, name="membership_role", native_enum=False, create_constraint=False, length=16),
        nullable=False,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    suspended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    suspension_reason: Mapped[str | None] = mapped_column(Text)
    suspended_by_user_id: Mapped[UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))

    user = relationship("User", back_populates="memberships", foreign_keys=[user_id])
    business = relationship("Business", back_populates="memberships")
