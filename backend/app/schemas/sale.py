from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator, model_validator

from app.models.enums import DebtStatus, PaymentMethod, SaleStatus


def _decimal(value: object, *, places: int, label: str) -> Decimal:
    if isinstance(value, float):
        raise ValueError(f"{label} must be sent as a decimal string")
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ValueError(f"{label} must be a valid decimal") from exc
    if not result.is_finite() or result.quantize(Decimal(1).scaleb(-places)) != result:
        raise ValueError(f"{label} supports at most {places} decimal places")
    return result


class SaleItemRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    product_id: UUID
    quantity: Decimal
    sale_version: str | None = Field(default=None, pattern=r"^[a-f0-9]{64}$")

    @field_validator("quantity", mode="before")
    @classmethod
    def quantity_exact(cls, value: object) -> Decimal:
        result = _decimal(value, places=3, label="Quantity")
        if result <= 0:
            raise ValueError("Quantity must be greater than zero")
        return result


class SaleCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    client_operation_id: UUID
    items: list[SaleItemRequest] = Field(min_length=1, max_length=200)
    payment_method: PaymentMethod
    payment_reference: str | None = Field(default=None, max_length=160)
    discount_amount: Decimal = Decimal("0.00")
    notes: str | None = Field(default=None, max_length=2000)
    customer_id: UUID | None = None
    due_date: date | None = None

    @field_validator("discount_amount", mode="before")
    @classmethod
    def discount_exact(cls, value: object) -> Decimal:
        result = _decimal(value, places=2, label="Discount")
        if result < 0:
            raise ValueError("Discount cannot be negative")
        return result

    @field_validator("payment_reference", "notes")
    @classmethod
    def clean_optional(cls, value: str | None) -> str | None:
        cleaned = value.strip() if value else ""
        return cleaned or None

    @model_validator(mode="after")
    def validate_credit_customer(self) -> "SaleCreateRequest":
        is_credit = self.payment_method == PaymentMethod.CUSTOMER_DEBT
        if is_credit and self.customer_id is None:
            raise ValueError("Customer is required for a customer-credit sale")
        if not is_credit and (self.customer_id is not None or self.due_date is not None):
            raise ValueError("Customer and due date are only accepted for customer-credit sales")
        return self


class SaleVoidRequest(BaseModel):
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


class SaleItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    product_id: UUID
    product_name_snapshot: str
    sku_snapshot: str | None
    track_inventory_snapshot: bool
    quantity: Decimal
    unit_selling_price: Decimal
    unit_cost: Decimal | None
    line_subtotal: Decimal
    line_cost: Decimal | None
    line_profit: Decimal | None

    @field_serializer("quantity")
    def quantity_string(self, value: Decimal) -> str:
        return format(value, ".3f")

    @field_serializer("unit_selling_price", "unit_cost", "line_subtotal", "line_cost", "line_profit")
    def money_string(self, value: Decimal | None) -> str | None:
        return None if value is None else format(value, ".2f")


class SaleResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    client_operation_id: UUID
    business_id: UUID
    sale_number: str
    status: SaleStatus
    subtotal: Decimal
    discount_amount: Decimal
    total_amount: Decimal
    total_cost: Decimal | None
    gross_profit: Decimal | None
    payment_method: PaymentMethod
    payment_reference: str | None
    notes: str | None
    sold_by_user_id: UUID
    sold_by_name: str | None
    sold_at: datetime
    voided_at: datetime | None
    voided_by_user_id: UUID | None
    voided_by_name: str | None
    void_reason: str | None
    customer_id: UUID | None = None
    customer_name: str | None = None
    debt_id: UUID | None = None
    debt_status: DebtStatus | None = None
    debt_due_date: date | None = None
    debt_outstanding_amount: Decimal | None = None
    items: list[SaleItemResponse]

    @field_serializer(
        "subtotal", "discount_amount", "total_amount", "total_cost", "gross_profit",
        "debt_outstanding_amount",
    )
    def money_string(self, value: Decimal | None) -> str | None:
        return None if value is None else format(value, ".2f")


class SaleListItemResponse(BaseModel):
    id: UUID
    client_operation_id: UUID
    sale_number: str
    status: SaleStatus
    total_amount: Decimal
    payment_method: PaymentMethod
    sold_at: datetime
    sold_by_name: str | None

    @field_serializer("total_amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class SaleListResponse(BaseModel):
    items: list[SaleListItemResponse]
    page: int
    page_size: int
    total: int


class ReceiptItemResponse(BaseModel):
    product_name: str
    sku: str | None
    quantity: Decimal
    unit_price: Decimal
    line_total: Decimal

    @field_serializer("quantity")
    def quantity_string(self, value: Decimal) -> str:
        return format(value, ".3f")

    @field_serializer("unit_price", "line_total")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class ReceiptResponse(BaseModel):
    business_name: str
    business_phone: str | None
    business_location: str | None
    currency: str
    title: str = "SALES RECEIPT"
    sale_number: str
    status: SaleStatus
    sold_at: datetime
    seller_name: str
    items: list[ReceiptItemResponse]
    subtotal: Decimal
    discount_amount: Decimal
    total_amount: Decimal
    payment_method: PaymentMethod
    payment_reference: str | None
    customer_name: str | None = None
    due_date: date | None = None
    footer: str = "Thank you"

    @field_serializer("subtotal", "discount_amount", "total_amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")
