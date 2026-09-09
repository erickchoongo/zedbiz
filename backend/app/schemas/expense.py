from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator, model_validator

from app.models.enums import ExpenseCategory, ExpenseStatus, PaymentMethod


def _money(value: object) -> Decimal:
    if isinstance(value, float):
        raise ValueError("Amount must be sent as a decimal string")
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ValueError("Amount must be a valid decimal") from exc
    if not result.is_finite() or result.quantize(Decimal("0.01")) != result:
        raise ValueError("Amount supports at most 2 decimal places")
    if result <= 0:
        raise ValueError("Amount must be greater than zero")
    return result


class ExpenseCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    client_operation_id: UUID
    category: ExpenseCategory
    description: str = Field(min_length=1, max_length=240)
    amount: Decimal
    payment_method: PaymentMethod
    payment_reference: str | None = Field(default=None, max_length=160)
    expense_date: date
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("amount", mode="before")
    @classmethod
    def exact_amount(cls, value: object) -> Decimal:
        return _money(value)

    @field_validator("description")
    @classmethod
    def clean_description(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Description is required")
        return cleaned

    @field_validator("payment_reference", "notes")
    @classmethod
    def clean_optional(cls, value: str | None) -> str | None:
        cleaned = value.strip() if value else ""
        return cleaned or None

    @model_validator(mode="after")
    def reject_customer_debt(self) -> "ExpenseCreateRequest":
        if self.payment_method == PaymentMethod.CUSTOMER_DEBT:
            raise ValueError("CUSTOMER_DEBT is not a valid expense payment method")
        return self


class ExpenseVoidRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    client_operation_id: UUID
    reason: str = Field(min_length=1, max_length=1000)

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("A void reason is required")
        return cleaned


class ExpenseResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    client_operation_id: UUID
    business_id: UUID
    category: ExpenseCategory
    description: str
    amount: Decimal
    payment_method: PaymentMethod
    payment_reference: str | None
    expense_date: date
    notes: str | None
    recorded_by_user_id: UUID
    recorded_by_name: str | None
    status: ExpenseStatus
    voided_at: datetime | None
    voided_by_user_id: UUID | None
    voided_by_name: str | None
    void_reason: str | None
    created_at: datetime
    updated_at: datetime

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class ExpenseListResponse(BaseModel):
    items: list[ExpenseResponse]
    page: int
    page_size: int
    total: int
