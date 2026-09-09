from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator, model_validator

from app.models.enums import (
    OnboardingPaymentStatus,
    OnboardingStatus,
    PaymentMethod,
    SubscriptionStatus,
)


def _external_payment_method(value: PaymentMethod | None) -> PaymentMethod | None:
    if value == PaymentMethod.CUSTOMER_DEBT:
        raise ValueError("Customer credit is not a valid commercial payment method")
    return value


class MoneyFields(BaseModel):
    @field_serializer("fee_amount", "onboarding_fee", "plan_price", "amount", check_fields=False)
    def serialize_money(self, value: Decimal | None) -> str | None:
        return None if value is None else format(value, ".2f")


class CommercialStatusResponse(MoneyFields):
    plan_name: str | None
    plan_code: str | None
    plan_price: Decimal | None
    currency: str
    subscription_status: SubscriptionStatus
    current_period_end: datetime | None
    grace_ends_at: datetime | None
    onboarding_status: OnboardingStatus
    onboarding_payment_status: OnboardingPaymentStatus | None
    onboarding_fee: Decimal | None
    writes_allowed: bool
    days_remaining: int | None
    can_manage_commercial: bool


class OnboardingAdminUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    payment_status: OnboardingPaymentStatus | None = None
    payment_method: PaymentMethod | None = None
    payment_reference: str | None = Field(default=None, min_length=1, max_length=160)
    onboarding_status: OnboardingStatus | None = None
    assign_to_me: bool | None = None
    notes: str | None = Field(default=None, max_length=4000)

    @field_validator("payment_method")
    @classmethod
    def external_payment_only(cls, value: PaymentMethod | None) -> PaymentMethod | None:
        return _external_payment_method(value)

    @field_validator("payment_reference", "notes")
    @classmethod
    def trim_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class PaymentRecordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    payment_method: PaymentMethod
    payment_reference: str = Field(min_length=1, max_length=160)
    paid_at: datetime | None = None

    @field_validator("payment_method")
    @classmethod
    def external_payment_only(cls, value: PaymentMethod) -> PaymentMethod:
        return _external_payment_method(value)  # type: ignore[return-value]

    @field_validator("payment_reference")
    @classmethod
    def trim_reference(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Payment reference is required")
        return value


class OnboardingAdminResponse(MoneyFields):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    fee_amount: Decimal
    currency: str
    payment_status: OnboardingPaymentStatus
    payment_method: PaymentMethod | None
    payment_reference: str | None
    paid_at: datetime | None
    onboarding_status: OnboardingStatus
    assigned_admin_user_id: UUID | None
    completed_at: datetime | None
    notes: str | None
    created_at: datetime
    updated_at: datetime


class SubscriptionPaymentResponse(MoneyFields):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    amount: Decimal
    currency: str
    payment_method: PaymentMethod
    payment_reference: str
    paid_at: datetime
    period_start: datetime
    period_end: datetime
    recorded_by_user_id: UUID
    created_at: datetime


class SubscriptionAdminResponse(MoneyFields):
    id: UUID
    plan_name: str
    plan_code: str
    plan_price: Decimal
    currency: str
    status: SubscriptionStatus
    starts_at: datetime
    current_period_start: datetime
    current_period_end: datetime
    grace_ends_at: datetime
    cancelled_at: datetime | None


class AdminBusinessSummaryResponse(BaseModel):
    id: UUID
    name: str
    owner_name: str | None
    owner_email: str | None
    onboarding_status: OnboardingStatus
    onboarding_payment_status: OnboardingPaymentStatus
    subscription_status: SubscriptionStatus
    paid_through: datetime | None


class AdminBusinessListResponse(BaseModel):
    items: list[AdminBusinessSummaryResponse]
    page: int
    page_size: int
    total: int


class AdminBusinessIdentityResponse(BaseModel):
    id: UUID
    name: str
    business_type: str | None
    phone_number: str | None
    location: str | None
    currency: str
    timezone: str


class AdminCommercialDetailResponse(BaseModel):
    business: AdminBusinessIdentityResponse
    onboarding: OnboardingAdminResponse
    subscription: SubscriptionAdminResponse | None
    payments: list[SubscriptionPaymentResponse]
