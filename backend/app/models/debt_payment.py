from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, Enum, ForeignKey, ForeignKeyConstraint, Index, Numeric, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.time import utc_now
from app.db.base import Base
from app.models.enums import PaymentMethod


class DebtPayment(Base):
    __tablename__ = "debt_payments"
    __table_args__ = (
        ForeignKeyConstraint(
            ["debt_id", "business_id"],
            ["debts.id", "debts.business_id"],
            name="fk_debt_payments_debt_business",
            ondelete="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["customer_id", "business_id"],
            ["customers.id", "customers.business_id"],
            name="fk_debt_payments_customer_business",
            ondelete="RESTRICT",
        ),
        UniqueConstraint(
            "business_id",
            "client_operation_id",
            name="uq_debt_payments_business_operation",
        ),
        UniqueConstraint("id", "business_id", name="uq_debt_payments_id_business"),
        CheckConstraint("amount > 0", name="ck_debt_payments_amount_positive"),
        CheckConstraint(
            "payment_method IN "
            "('CASH', 'MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', 'BANK_TRANSFER', 'OTHER')",
            name="ck_debt_payments_method",
        ),
        Index("ix_debt_payments_business_debt_paid", "business_id", "debt_id", "paid_at"),
        Index("ix_debt_payments_business_customer_paid", "business_id", "customer_id", "paid_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    business_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
    )
    debt_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    customer_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    payment_method: Mapped[PaymentMethod] = mapped_column(
        Enum(PaymentMethod, native_enum=False, create_constraint=False, length=24), nullable=False
    )
    payment_reference: Mapped[str | None] = mapped_column(String(160))
    client_operation_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    request_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
    received_by_user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    paid_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=utc_now
    )

    business = relationship(
        "Business",
        back_populates="debt_payments",
        overlaps="customer,debt,debt_payments,payments",
    )
    debt = relationship(
        "Debt",
        back_populates="payments",
        foreign_keys=[debt_id, business_id],
        overlaps="business,customer,debt_payments,payments",
    )
    customer = relationship(
        "Customer",
        back_populates="debt_payments",
        foreign_keys=[customer_id, business_id],
        overlaps="business,customer,debt,debt_payments,payments",
    )
    received_by = relationship("User", foreign_keys=[received_by_user_id])
