from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, Enum, ForeignKey, Numeric, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.constants import DEFAULT_COMMERCIAL_CURRENCY, DEFAULT_ONBOARDING_FEE
from app.db.base import Base
from app.models.enums import OnboardingPaymentStatus, OnboardingStatus, PaymentMethod
from app.models.mixins import TimestampMixin


class OnboardingRecord(TimestampMixin, Base):
    __tablename__ = "onboarding_records"
    __table_args__ = (
        UniqueConstraint("business_id", name="uq_onboarding_records_business"),
        CheckConstraint("fee_amount >= 0", name="ck_onboarding_records_fee_nonnegative"),
        CheckConstraint("payment_status IN ('UNPAID', 'PAID', 'WAIVED')", name="ck_onboarding_payment_status"),
        CheckConstraint(
            "onboarding_status IN ('NOT_STARTED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')",
            name="ck_onboarding_status",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    business_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
    )
    fee_amount: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), nullable=False, default=lambda: Decimal(DEFAULT_ONBOARDING_FEE)
    )
    currency: Mapped[str] = mapped_column(
        String(3), nullable=False, default=DEFAULT_COMMERCIAL_CURRENCY, server_default=DEFAULT_COMMERCIAL_CURRENCY
    )
    payment_status: Mapped[OnboardingPaymentStatus] = mapped_column(
        Enum(OnboardingPaymentStatus, native_enum=False, create_constraint=False, length=16),
        nullable=False,
        default=OnboardingPaymentStatus.UNPAID,
        server_default=OnboardingPaymentStatus.UNPAID.value,
    )
    payment_method: Mapped[PaymentMethod | None] = mapped_column(
        Enum(PaymentMethod, native_enum=False, create_constraint=False, length=24)
    )
    payment_reference: Mapped[str | None] = mapped_column(String(160))
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    onboarding_status: Mapped[OnboardingStatus] = mapped_column(
        Enum(OnboardingStatus, native_enum=False, create_constraint=False, length=20),
        nullable=False,
        default=OnboardingStatus.NOT_STARTED,
        server_default=OnboardingStatus.NOT_STARTED.value,
    )
    assigned_admin_user_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="SET NULL")
    )
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    notes: Mapped[str | None] = mapped_column(Text)

    business = relationship("Business", back_populates="onboarding_record")
