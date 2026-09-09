from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.models.enums import MembershipRole


class BusinessCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=2, max_length=200)
    business_type: str | None = Field(default=None, max_length=120)
    phone_number: str | None = Field(default=None, max_length=32)
    location: str | None = Field(default=None, max_length=255)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        cleaned = " ".join(value.split())
        if len(cleaned) < 2:
            raise ValueError("Business name is required")
        return cleaned


class BusinessUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=2, max_length=200)
    business_type: str | None = Field(default=None, max_length=120)
    phone_number: str | None = Field(default=None, max_length=32)
    location: str | None = Field(default=None, max_length=255)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = " ".join(value.split())
        if len(cleaned) < 2:
            raise ValueError("Business name is required")
        return cleaned

    @model_validator(mode="after")
    def reject_explicit_null_name(self) -> "BusinessUpdateRequest":
        if "name" in self.model_fields_set and self.name is None:
            raise ValueError("Business name cannot be null")
        return self


class BusinessResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    business_type: str | None
    phone_number: str | None
    location: str | None
    currency: str
    timezone: str
    is_active: bool
    role: MembershipRole
    created_at: datetime
    updated_at: datetime
