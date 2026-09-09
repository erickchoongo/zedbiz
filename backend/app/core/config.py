from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

_UNSAFE_SECRETS = {
    "change-me",
    "changeme",
    "replace-me",
    "replace-with-at-least-32-random-characters",
    "secret",
}


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file="../.env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    app_env: Literal["development", "test", "staging", "production"] = "development"
    app_name: str = "ZedBiz API"
    database_url: str = "postgresql+psycopg://zedbiz:zedbiz@localhost:5432/zedbiz"
    jwt_secret: str = "development-only-secret-change-me"
    access_token_expire_minutes: int = Field(default=15, gt=0)
    refresh_token_expire_days: int = Field(default=30, gt=0)
    cors_origins: Annotated[list[str], NoDecode] = Field(default_factory=list)

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @model_validator(mode="after")
    def validate_production_security(self) -> "Settings":
        if self.app_env != "production":
            return self
        normalized_secret = self.jwt_secret.strip().lower()
        if len(self.jwt_secret) < 32 or normalized_secret in _UNSAFE_SECRETS or "change-me" in normalized_secret:
            raise ValueError("JWT_SECRET must be a strong, non-placeholder value in production")
        if "*" in self.cors_origins:
            raise ValueError("Wildcard CORS origins are forbidden in production")
        if not self.cors_origins:
            raise ValueError("CORS_ORIGINS must contain at least one trusted origin in production")
        normalized_database_url = self.database_url.lower()
        if "localhost" in normalized_database_url or "zedbiz:zedbiz@" in normalized_database_url:
            raise ValueError("DATABASE_URL must not use local or default credentials in production")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
