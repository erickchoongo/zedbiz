from uuid import UUID, uuid4

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Index, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.mixins import TimestampMixin


class Customer(TimestampMixin, Base):
    __tablename__ = "customers"
    __table_args__ = (
        UniqueConstraint("id", "business_id", name="uq_customers_id_business"),
        CheckConstraint("length(trim(name)) > 0", name="ck_customers_name_nonempty"),
        CheckConstraint(
            "phone_number IS NULL OR "
            "(length(phone_number) BETWEEN 9 AND 16 AND substr(phone_number, 1, 1) = '+')",
            name="ck_customers_phone_e164_shape",
        ),
        CheckConstraint(
            "email IS NULL OR (length(trim(email)) > 0 AND email = lower(trim(email)))",
            name="ck_customers_email_normalized",
        ),
        Index("ix_customers_business_active_name", "business_id", "is_active", "name"),
        Index("ix_customers_business_phone", "business_id", "phone_number"),
        Index("ix_customers_business_email", "business_id", "email"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    business_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    phone_number: Mapped[str | None] = mapped_column(String(16))
    email: Mapped[str | None] = mapped_column(String(320))
    notes: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")

    business = relationship("Business", back_populates="customers")
    sales = relationship("Sale", back_populates="customer", overlaps="business,customers,sales")
    debts = relationship("Debt", back_populates="customer", overlaps="business,customers,debts,sale")
    debt_payments = relationship(
        "DebtPayment",
        back_populates="customer",
        overlaps="business,customer,debt,debt_payments,payments",
        order_by="DebtPayment.paid_at",
    )
