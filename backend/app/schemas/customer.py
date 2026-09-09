import re
from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_serializer, field_validator

from app.schemas.debt import DebtListItemResponse


_PHONE_ALLOWED = re.compile(r"^[+0-9() .-]+$")
_E164 = re.compile(r"^\+[1-9][0-9]{7,14}$")


def normalize_phone_number(value: str | None) -> str | None:
    """Normalize confidently identifiable numbers without guessing a country code.

    Zambia national numbers (for example, 0971234567) and Zambia country-code
    numbers without a plus are converted to E.164. Explicit international
    numbers must use ``+`` or ``00`` and are retained as international numbers.
    """

    if value is None:
        return None
    raw = value.strip()
    if not raw:
        return None
    if not _PHONE_ALLOWED.fullmatch(raw) or raw.count("+") > 1 or ("+" in raw and not raw.startswith("+")):
        raise ValueError("Phone number contains unsupported characters")
    compact = re.sub(r"[() .-]", "", raw)
    if compact.startswith("00"):
        compact = f"+{compact[2:]}"
    elif compact.startswith("+"):
        pass
    elif compact.startswith("0"):
        if not re.fullmatch(r"0[1-9][0-9]{8}", compact):
            raise ValueError("Zambia local phone numbers must contain 10 digits")
        compact = f"+260{compact[1:]}"
    elif re.fullmatch(r"260[1-9][0-9]{8}", compact):
        compact = f"+{compact}"
    else:
        raise ValueError("Use a Zambia local number or an international number beginning with +")
    if not _E164.fullmatch(compact):
        raise ValueError("Phone number must be a valid E.164 number")
    return compact


def _clean_name(value: str) -> str:
    cleaned = " ".join(value.split())
    if not cleaned:
        raise ValueError("Customer name is required")
    return cleaned


def _clean_optional(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


class CustomerCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=200)
    phone_number: str | None = Field(default=None, max_length=64)
    email: EmailStr | None = None
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        return _clean_name(value)

    @field_validator("phone_number")
    @classmethod
    def normalize_phone(cls, value: str | None) -> str | None:
        return normalize_phone_number(value)

    @field_validator("email", mode="after")
    @classmethod
    def normalize_email(cls, value: EmailStr | None) -> str | None:
        return str(value).strip().lower() if value is not None else None

    @field_validator("notes")
    @classmethod
    def clean_notes(cls, value: str | None) -> str | None:
        return _clean_optional(value)


class CustomerUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=200)
    phone_number: str | None = Field(default=None, max_length=64)
    email: EmailStr | None = None
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str | None) -> str | None:
        if value is None:
            raise ValueError("Customer name cannot be null")
        return _clean_name(value)

    @field_validator("phone_number")
    @classmethod
    def normalize_phone(cls, value: str | None) -> str | None:
        return normalize_phone_number(value)

    @field_validator("email", mode="after")
    @classmethod
    def normalize_email(cls, value: EmailStr | None) -> str | None:
        return str(value).strip().lower() if value is not None else None

    @field_validator("notes")
    @classmethod
    def clean_notes(cls, value: str | None) -> str | None:
        return _clean_optional(value)


class CustomerListItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    business_id: UUID
    name: str
    phone_number: str | None
    email: str | None
    is_active: bool
    total_outstanding: Decimal
    total_overdue: Decimal
    open_debt_count: int

    @field_serializer("total_outstanding", "total_overdue")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class CustomerDetailResponse(CustomerListItemResponse):
    notes: str | None
    created_at: datetime
    updated_at: datetime
    recent_debts: list[DebtListItemResponse]


class CustomerListResponse(BaseModel):
    items: list[CustomerListItemResponse]
    page: int
    page_size: int
    total: int
