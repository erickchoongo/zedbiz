from uuid import UUID, uuid4

from sqlalchemy import Boolean, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.constants import DEFAULT_BUSINESS_CURRENCY, DEFAULT_BUSINESS_TIMEZONE
from app.db.base import Base
from app.models.mixins import TimestampMixin


class Business(TimestampMixin, Base):
    __tablename__ = "businesses"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    business_type: Mapped[str | None] = mapped_column(String(120))
    phone_number: Mapped[str | None] = mapped_column(String(32))
    location: Mapped[str | None] = mapped_column(String(255))
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default=DEFAULT_BUSINESS_CURRENCY, server_default=DEFAULT_BUSINESS_CURRENCY)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default=DEFAULT_BUSINESS_TIMEZONE, server_default=DEFAULT_BUSINESS_TIMEZONE)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")

    memberships = relationship("BusinessMembership", back_populates="business", cascade="all, delete-orphan")
    onboarding_record = relationship(
        "OnboardingRecord", back_populates="business", cascade="all, delete-orphan", uselist=False
    )
    subscription = relationship(
        "Subscription", back_populates="business", cascade="all, delete-orphan", uselist=False
    )
    products = relationship("Product", back_populates="business", cascade="all, delete-orphan")
    sales = relationship("Sale", back_populates="business", cascade="all, delete-orphan")
    sale_counter = relationship("SaleCounter", back_populates="business", cascade="all, delete-orphan", uselist=False)
    customers = relationship("Customer", back_populates="business", cascade="all, delete-orphan")
    debts = relationship("Debt", back_populates="business", cascade="all, delete-orphan")
    debt_payments = relationship("DebtPayment", back_populates="business", cascade="all, delete-orphan")
    expenses = relationship("Expense", back_populates="business", cascade="all, delete-orphan")
