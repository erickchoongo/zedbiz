from datetime import datetime
from decimal import Decimal, InvalidOperation
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator, model_validator

from app.models.enums import InventoryMovementType


def _exact_decimal(value: object, *, places: int, label: str) -> Decimal:
    if isinstance(value, float):
        raise ValueError(f"{label} must be sent as a decimal string, not a floating-point number")
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ValueError(f"{label} must be a valid decimal") from exc
    if not result.is_finite():
        raise ValueError(f"{label} must be finite")
    quantum = Decimal(1).scaleb(-places)
    if result.quantize(quantum) != result:
        raise ValueError(f"{label} supports at most {places} decimal places")
    return result


class ProductCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=200)
    sku: str | None = Field(default=None, max_length=80)
    barcode: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=4000)
    cost_price: Decimal = Decimal("0.00")
    selling_price: Decimal
    track_inventory: bool = True
    opening_stock: Decimal = Decimal("0.000")
    low_stock_threshold: Decimal = Decimal("0.000")
    client_operation_id: UUID | None = None

    @field_validator("cost_price", "selling_price", mode="before")
    @classmethod
    def validate_money(cls, value: object) -> Decimal:
        return _exact_decimal(value, places=2, label="Money")

    @field_validator("opening_stock", "low_stock_threshold", mode="before")
    @classmethod
    def validate_quantity(cls, value: object) -> Decimal:
        return _exact_decimal(value, places=3, label="Quantity")

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        cleaned = " ".join(value.split())
        if not cleaned:
            raise ValueError("Product name is required")
        return cleaned

    @field_validator("sku")
    @classmethod
    def normalize_sku(cls, value: str | None) -> str | None:
        cleaned = "".join(value.split()).upper() if value else ""
        return cleaned or None

    @field_validator("barcode", "description")
    @classmethod
    def clean_optional(cls, value: str | None) -> str | None:
        cleaned = value.strip() if value else ""
        return cleaned or None

    @model_validator(mode="after")
    def validate_inventory_fields(self) -> "ProductCreateRequest":
        if self.cost_price < 0 or self.selling_price < 0:
            raise ValueError("Prices cannot be negative")
        if self.opening_stock < 0 or self.low_stock_threshold < 0:
            raise ValueError("Inventory quantities cannot be negative")
        if not self.track_inventory and (
            self.opening_stock != Decimal("0") or self.low_stock_threshold != Decimal("0")
        ):
            raise ValueError("Services cannot have opening stock or a low-stock threshold")
        return self


class ProductUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=200)
    sku: str | None = Field(default=None, max_length=80)
    barcode: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=4000)
    cost_price: Decimal | None = None
    selling_price: Decimal | None = None
    low_stock_threshold: Decimal | None = None

    @field_validator("cost_price", "selling_price", mode="before")
    @classmethod
    def validate_money(cls, value: object) -> Decimal | None:
        return None if value is None else _exact_decimal(value, places=2, label="Money")

    @field_validator("low_stock_threshold", mode="before")
    @classmethod
    def validate_quantity(cls, value: object) -> Decimal | None:
        return None if value is None else _exact_decimal(value, places=3, label="Quantity")

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = " ".join(value.split())
        if not cleaned:
            raise ValueError("Product name is required")
        return cleaned

    @field_validator("sku")
    @classmethod
    def normalize_sku(cls, value: str | None) -> str | None:
        cleaned = "".join(value.split()).upper() if value else ""
        return cleaned or None

    @field_validator("barcode", "description")
    @classmethod
    def clean_optional(cls, value: str | None) -> str | None:
        cleaned = value.strip() if value else ""
        return cleaned or None

    @model_validator(mode="after")
    def validate_nonnegative(self) -> "ProductUpdateRequest":
        for value in (self.cost_price, self.selling_price, self.low_stock_threshold):
            if value is not None and value < 0:
                raise ValueError("Prices and thresholds cannot be negative")
        if "name" in self.model_fields_set and self.name is None:
            raise ValueError("Product name cannot be null")
        return self


class StockAddRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    quantity: Decimal
    unit_cost: Decimal | None = None
    reason: str | None = Field(default=None, max_length=1000)
    client_operation_id: UUID

    @field_validator("quantity", mode="before")
    @classmethod
    def validate_quantity(cls, value: object) -> Decimal:
        result = _exact_decimal(value, places=3, label="Quantity")
        if result <= 0:
            raise ValueError("Quantity must be greater than zero")
        return result

    @field_validator("unit_cost", mode="before")
    @classmethod
    def validate_unit_cost(cls, value: object) -> Decimal | None:
        if value is None:
            return None
        result = _exact_decimal(value, places=2, label="Unit cost")
        if result < 0:
            raise ValueError("Unit cost cannot be negative")
        return result

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, value: str | None) -> str | None:
        cleaned = value.strip() if value else ""
        return cleaned or None


class StockAdjustRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    target_quantity: Decimal
    reason: str = Field(min_length=1, max_length=1000)
    client_operation_id: UUID

    @field_validator("target_quantity", mode="before")
    @classmethod
    def validate_quantity(cls, value: object) -> Decimal:
        result = _exact_decimal(value, places=3, label="Target quantity")
        if result < 0:
            raise ValueError("Target quantity cannot be negative")
        return result

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("A reason is required")
        return cleaned


class StockReductionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    quantity: Decimal
    reason: str = Field(min_length=1, max_length=1000)
    client_operation_id: UUID

    @field_validator("quantity", mode="before")
    @classmethod
    def validate_quantity(cls, value: object) -> Decimal:
        result = _exact_decimal(value, places=3, label="Quantity")
        if result <= 0:
            raise ValueError("Quantity must be greater than zero")
        return result

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("A reason is required")
        return cleaned


class ProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    business_id: UUID
    name: str
    sku: str | None
    barcode: str | None
    description: str | None
    cost_price: Decimal
    selling_price: Decimal
    stock_quantity: Decimal
    low_stock_threshold: Decimal
    track_inventory: bool
    is_active: bool
    is_low_stock: bool
    created_at: datetime
    updated_at: datetime
    sale_version: str

    @field_serializer("cost_price", "selling_price")
    def serialize_money(self, value: Decimal) -> str:
        return format(value, ".2f")

    @field_serializer("stock_quantity", "low_stock_threshold")
    def serialize_quantity(self, value: Decimal) -> str:
        return format(value, ".3f")


class ProductListResponse(BaseModel):
    items: list[ProductResponse]
    page: int
    page_size: int
    total: int


class InventoryMovementResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    movement_type: InventoryMovementType
    quantity_delta: Decimal
    quantity_before: Decimal
    quantity_after: Decimal
    unit_cost: Decimal | None
    reason: str | None
    performed_by_user_id: UUID
    performed_by_name: str | None = None
    client_operation_id: UUID | None
    created_at: datetime

    @field_serializer("quantity_delta", "quantity_before", "quantity_after")
    def serialize_quantity(self, value: Decimal) -> str:
        return format(value, ".3f")

    @field_serializer("unit_cost")
    def serialize_money(self, value: Decimal | None) -> str | None:
        return None if value is None else format(value, ".2f")


class InventoryMovementListResponse(BaseModel):
    items: list[InventoryMovementResponse]
    page: int
    page_size: int
    total: int


class InventorySummaryResponse(BaseModel):
    total_active_products: int
    low_stock_count: int
    out_of_stock_count: int
