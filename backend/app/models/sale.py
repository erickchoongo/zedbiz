from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, Enum, ForeignKey, ForeignKeyConstraint, Index, Numeric, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.enums import PaymentMethod, SaleStatus
from app.models.mixins import TimestampMixin


class Sale(TimestampMixin, Base):
    __tablename__ = "sales"
    __table_args__ = (
        ForeignKeyConstraint(
            ["customer_id", "business_id"],
            ["customers.id", "customers.business_id"],
            name="fk_sales_customer_business",
            ondelete="RESTRICT",
        ),
        UniqueConstraint("business_id", "sale_number", name="uq_sales_business_number"),
        UniqueConstraint("business_id", "client_operation_id", name="uq_sales_business_operation"),
        UniqueConstraint("business_id", "void_client_operation_id", name="uq_sales_business_void_operation"),
        UniqueConstraint("id", "business_id", name="uq_sales_id_business"),
        CheckConstraint("status IN ('COMPLETED', 'VOIDED')", name="ck_sales_status"),
        CheckConstraint(
            "payment_method IN ('CASH', 'MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', 'BANK_TRANSFER', 'OTHER', 'CUSTOMER_DEBT')",
            name="ck_sales_payment_method",
        ),
        CheckConstraint(
            "payment_method <> 'CUSTOMER_DEBT' OR customer_id IS NOT NULL",
            name="ck_sales_customer_debt_customer",
        ),
        CheckConstraint("subtotal >= 0", name="ck_sales_subtotal_nonnegative"),
        CheckConstraint("discount_amount >= 0", name="ck_sales_discount_nonnegative"),
        CheckConstraint("discount_amount <= subtotal", name="ck_sales_discount_within_subtotal"),
        CheckConstraint("total_amount = subtotal - discount_amount", name="ck_sales_total_equation"),
        CheckConstraint("total_cost >= 0", name="ck_sales_cost_nonnegative"),
        Index("ix_sales_business_sold_at", "business_id", "sold_at"),
        Index("ix_sales_business_status_sold", "business_id", "status", "sold_at"),
        Index("ix_sales_business_payment_sold", "business_id", "payment_method", "sold_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    business_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
    customer_id: Mapped[UUID | None] = mapped_column(Uuid)
    sale_number: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[SaleStatus] = mapped_column(Enum(SaleStatus, native_enum=False, create_constraint=False, length=16), nullable=False)
    subtotal: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    total_cost: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    gross_profit: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    payment_method: Mapped[PaymentMethod] = mapped_column(Enum(PaymentMethod, native_enum=False, create_constraint=False, length=24), nullable=False)
    payment_reference: Mapped[str | None] = mapped_column(String(160))
    notes: Mapped[str | None] = mapped_column(Text)
    client_operation_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    request_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
    sold_by_user_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    sold_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    voided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    voided_by_user_id: Mapped[UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="RESTRICT"))
    void_reason: Mapped[str | None] = mapped_column(Text)
    void_client_operation_id: Mapped[UUID | None] = mapped_column(Uuid)

    business = relationship("Business", back_populates="sales")
    customer = relationship(
        "Customer",
        back_populates="sales",
        foreign_keys=[customer_id, business_id],
        overlaps="business,customers,sales",
    )
    sold_by = relationship("User", foreign_keys=[sold_by_user_id])
    voided_by = relationship("User", foreign_keys=[voided_by_user_id])
    items = relationship("SaleItem", back_populates="sale", cascade="all, delete-orphan", order_by="SaleItem.created_at")
    debt = relationship(
        "Debt",
        back_populates="sale",
        uselist=False,
        overlaps="business,customer,customers,debts",
    )
