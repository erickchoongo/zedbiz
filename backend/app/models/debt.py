from datetime import date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, Date, DateTime, Enum, ForeignKey, ForeignKeyConstraint, Index, Numeric, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.enums import DebtStatus
from app.models.mixins import TimestampMixin


class Debt(TimestampMixin, Base):
    __tablename__ = "debts"
    __table_args__ = (
        ForeignKeyConstraint(
            ["customer_id", "business_id"],
            ["customers.id", "customers.business_id"],
            name="fk_debts_customer_business",
            ondelete="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["sale_id", "business_id"],
            ["sales.id", "sales.business_id"],
            name="fk_debts_sale_business",
            ondelete="RESTRICT",
        ),
        UniqueConstraint("business_id", "sale_id", name="uq_debts_business_sale"),
        UniqueConstraint("id", "business_id", name="uq_debts_id_business"),
        CheckConstraint(
            "status IN ('OPEN', 'PARTIALLY_PAID', 'PAID', 'VOIDED')",
            name="ck_debts_status",
        ),
        CheckConstraint("original_amount > 0", name="ck_debts_original_positive"),
        CheckConstraint("amount_paid >= 0", name="ck_debts_paid_nonnegative"),
        CheckConstraint("outstanding_amount >= 0", name="ck_debts_outstanding_nonnegative"),
        CheckConstraint("amount_paid <= original_amount", name="ck_debts_paid_within_original"),
        CheckConstraint(
            "(status = 'VOIDED' AND round(amount_paid, 2) = 0 AND round(outstanding_amount, 2) = 0) "
            "OR (status <> 'VOIDED' AND "
            "round(outstanding_amount, 2) = round(original_amount - amount_paid, 2))",
            name="ck_debts_balance_equation",
        ),
        CheckConstraint(
            "(status = 'OPEN' AND round(amount_paid, 2) = 0 "
            "AND round(outstanding_amount, 2) = round(original_amount, 2) "
            "AND settled_at IS NULL AND voided_at IS NULL AND voided_by_user_id IS NULL) "
            "OR (status = 'PARTIALLY_PAID' AND amount_paid > 0 AND outstanding_amount > 0 "
            "AND settled_at IS NULL AND voided_at IS NULL AND voided_by_user_id IS NULL) "
            "OR (status = 'PAID' AND round(amount_paid, 2) = round(original_amount, 2) "
            "AND round(outstanding_amount, 2) = 0 AND settled_at IS NOT NULL "
            "AND voided_at IS NULL AND voided_by_user_id IS NULL) "
            "OR (status = 'VOIDED' AND round(amount_paid, 2) = 0 "
            "AND round(outstanding_amount, 2) = 0 AND settled_at IS NULL "
            "AND voided_at IS NOT NULL AND voided_by_user_id IS NOT NULL)",
            name="ck_debts_status_balance_consistency",
        ),
        Index("ix_debts_business_status_due", "business_id", "status", "due_date"),
        Index("ix_debts_business_customer_created", "business_id", "customer_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    business_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
    )
    customer_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    sale_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    original_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    amount_paid: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    outstanding_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    status: Mapped[DebtStatus] = mapped_column(
        Enum(DebtStatus, native_enum=False, create_constraint=False, length=24), nullable=False
    )
    due_date: Mapped[date | None] = mapped_column(Date)
    notes: Mapped[str | None] = mapped_column(Text)
    created_by_user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    settled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    voided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    voided_by_user_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="RESTRICT")
    )

    business = relationship("Business", back_populates="debts", overlaps="customer,debts,sale")
    customer = relationship(
        "Customer",
        back_populates="debts",
        foreign_keys=[customer_id, business_id],
        overlaps="business,customers,debts,sale",
    )
    sale = relationship(
        "Sale",
        back_populates="debt",
        foreign_keys=[sale_id, business_id],
        overlaps="business,customer,customers,debts",
    )
    created_by = relationship("User", foreign_keys=[created_by_user_id])
    voided_by = relationship("User", foreign_keys=[voided_by_user_id])
    payments = relationship(
        "DebtPayment",
        back_populates="debt",
        overlaps="business,customer,debt_payments,payments",
        order_by="DebtPayment.paid_at",
    )
