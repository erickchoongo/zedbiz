from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator

from app.models.enums import DebtStatus, PaymentMethod


def exact_money(value: object, *, label: str = "Amount") -> Decimal:
    if isinstance(value, float):
        raise ValueError(f"{label} must be sent as a decimal string")
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ValueError(f"{label} must be a valid decimal") from exc
    try:
        quantized = result.quantize(Decimal("0.01"))
    except InvalidOperation as exc:
        raise ValueError(f"{label} must be a valid decimal") from exc
    if not result.is_finite() or quantized != result:
        raise ValueError(f"{label} supports at most 2 decimal places")
    if abs(result) >= Decimal("10000000000.00"):
        raise ValueError(f"{label} is too large")
    return result


def _clean_optional(value: str | None) -> str | None:
    cleaned = value.strip() if value else ""
    return cleaned or None


class DebtPaymentCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    client_operation_id: UUID
    amount: Decimal
    payment_method: PaymentMethod
    payment_reference: str | None = Field(default=None, max_length=160)
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("amount", mode="before")
    @classmethod
    def amount_exact(cls, value: object) -> Decimal:
        result = exact_money(value)
        if result <= 0:
            raise ValueError("Amount must be greater than zero")
        return result

    @field_validator("payment_method")
    @classmethod
    def repayment_method_only(cls, value: PaymentMethod) -> PaymentMethod:
        if value == PaymentMethod.CUSTOMER_DEBT:
            raise ValueError("CUSTOMER_DEBT cannot be used for a repayment")
        return value

    @field_validator("payment_reference", "notes")
    @classmethod
    def clean_optional(cls, value: str | None) -> str | None:
        return _clean_optional(value)


class DebtListItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    business_id: UUID
    customer_id: UUID
    customer_name: str
    customer_phone_number: str | None
    sale_id: UUID
    sale_number: str
    original_amount: Decimal
    amount_paid: Decimal
    outstanding_amount: Decimal
    status: DebtStatus
    due_date: date | None
    is_overdue: bool
    created_at: datetime

    @field_serializer("original_amount", "amount_paid", "outstanding_amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class DebtDetailResponse(DebtListItemResponse):
    notes: str | None
    created_by_user_id: UUID
    created_by_name: str | None
    settled_at: datetime | None
    voided_at: datetime | None
    updated_at: datetime


class DebtListResponse(BaseModel):
    items: list[DebtListItemResponse]
    page: int
    page_size: int
    total: int


class DebtSummaryResponse(BaseModel):
    total_outstanding: Decimal
    total_overdue: Decimal
    customers_owing: int
    open_debt_count: int

    @field_serializer("total_outstanding", "total_overdue")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class DebtPaymentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    business_id: UUID
    debt_id: UUID
    customer_id: UUID
    customer_name: str
    amount: Decimal
    payment_method: PaymentMethod
    payment_reference: str | None
    received_by_user_id: UUID
    received_by_name: str | None
    paid_at: datetime
    notes: str | None
    created_at: datetime

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class DebtPaymentListResponse(BaseModel):
    items: list[DebtPaymentResponse]
    page: int
    page_size: int
    total: int


class DebtPaymentCreateResponse(BaseModel):
    payment: DebtPaymentResponse
    debt: DebtDetailResponse


class DebtReminderResponse(BaseModel):
    debt_id: UUID
    customer_id: UUID
    customer_name: str
    phone_number: str | None
    outstanding_amount: Decimal
    due_date: date | None
    message: str

    @field_serializer("outstanding_amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")
