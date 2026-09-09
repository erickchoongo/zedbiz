from datetime import date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, Date, DateTime, Enum, ForeignKey, Index, Numeric, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.enums import ExpenseCategory, ExpenseStatus, PaymentMethod
from app.models.mixins import TimestampMixin


class Expense(TimestampMixin, Base):
    __tablename__ = "expenses"
    __table_args__ = (
        UniqueConstraint("id", "business_id", name="uq_expenses_id_business"),
        UniqueConstraint("business_id", "client_operation_id", name="uq_expenses_business_operation"),
        UniqueConstraint("business_id", "void_client_operation_id", name="uq_expenses_business_void_operation"),
        CheckConstraint("amount > 0", name="ck_expenses_amount_positive"),
        CheckConstraint(
            "category IN ('STOCK_PURCHASE', 'RENT', 'UTILITIES', 'TRANSPORT', "
            "'SALARIES_WAGES', 'AIRTIME_DATA', 'MARKETING', 'MAINTENANCE', "
            "'EQUIPMENT', 'FEES_CHARGES', 'OTHER')",
            name="ck_expenses_category",
        ),
        CheckConstraint(
            "payment_method IN ('MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', "
            "'BANK_TRANSFER', 'CASH', 'OTHER')",
            name="ck_expenses_payment_method",
        ),
        CheckConstraint("status IN ('RECORDED', 'VOIDED')", name="ck_expenses_status"),
        CheckConstraint("length(trim(description)) > 0", name="ck_expenses_description_nonblank"),
        CheckConstraint(
            "(status = 'RECORDED' AND voided_at IS NULL AND voided_by_user_id IS NULL "
            "AND void_reason IS NULL AND void_client_operation_id IS NULL) OR "
            "(status = 'VOIDED' AND voided_at IS NOT NULL AND voided_by_user_id IS NOT NULL "
            "AND void_reason IS NOT NULL AND void_client_operation_id IS NOT NULL)",
            name="ck_expenses_void_consistency",
        ),
        Index("ix_expenses_business_date", "business_id", "expense_date"),
        Index("ix_expenses_business_status_date", "business_id", "status", "expense_date"),
        Index("ix_expenses_business_category_date", "business_id", "category", "expense_date"),
        Index("ix_expenses_business_payment_date", "business_id", "payment_method", "expense_date"),
        Index("ix_expenses_business_recorder_date", "business_id", "recorded_by_user_id", "expense_date"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    business_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
    )
    category: Mapped[ExpenseCategory] = mapped_column(
        Enum(ExpenseCategory, native_enum=False, create_constraint=False, length=32), nullable=False
    )
    description: Mapped[str] = mapped_column(String(240), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    payment_method: Mapped[PaymentMethod] = mapped_column(
        Enum(PaymentMethod, native_enum=False, create_constraint=False, length=32), nullable=False
    )
    payment_reference: Mapped[str | None] = mapped_column(String(160))
    expense_date: Mapped[date] = mapped_column(Date, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    client_operation_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    request_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
    recorded_by_user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    status: Mapped[ExpenseStatus] = mapped_column(
        Enum(ExpenseStatus, native_enum=False, create_constraint=False, length=16), nullable=False
    )
    voided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    voided_by_user_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="RESTRICT")
    )
    void_reason: Mapped[str | None] = mapped_column(Text)
    void_client_operation_id: Mapped[UUID | None] = mapped_column(Uuid)

    business = relationship("Business", back_populates="expenses")
    recorded_by = relationship("User", foreign_keys=[recorded_by_user_id])
    voided_by = relationship("User", foreign_keys=[voided_by_user_id])
