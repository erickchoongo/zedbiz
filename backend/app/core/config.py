from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict
from sqlalchemy.engine import make_url
from urllib.parse import urlsplit

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
        hide_input_in_errors=True,
    )

    app_env: Literal["development", "test", "staging", "production"] = "development"
    app_name: str = "ZedBiz API"
    database_url: str = "postgresql+psycopg://zedbiz:zedbiz@localhost:5432/zedbiz"
    jwt_secret: str = "development-only-secret-change-me"
    access_token_expire_minutes: int = Field(default=15, gt=0)
    refresh_token_expire_days: int = Field(default=30, gt=0)
    cors_origins: Annotated[list[str], NoDecode] = Field(default_factory=list)
    trusted_hosts: Annotated[list[str], NoDecode] = Field(default_factory=lambda: ['*'])
    log_level: Literal['DEBUG', 'INFO', 'WARNING', 'ERROR'] = 'INFO'
    db_pool_size: int = Field(default=5, ge=1, le=20)
    db_max_overflow: int = Field(default=5, ge=0, le=20)
    db_pool_timeout: int = Field(default=10, ge=1, le=60)
    db_pool_recycle: int = Field(default=1800, ge=60)
    web_concurrency: int = Field(default=1, ge=1, le=4)
    rate_limit_enabled: bool = True
    rate_limit_api: int = Field(default=600, ge=1)
    rate_limit_login: int = Field(default=30, ge=1)
    rate_limit_account: int = Field(default=8, ge=1)
    rate_limit_register: int = Field(default=5, ge=1)
    rate_limit_refresh: int = Field(default=60, ge=1)
    rate_limit_window_seconds: int = Field(default=60, ge=1, le=3600)
    max_request_bytes: int = Field(default=262144, ge=1024, le=1048576)

    @field_validator("cors_origins", "trusted_hosts", mode="before")
    @classmethod
    def parse_cors_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @model_validator(mode="after")
    def validate_production_security(self) -> "Settings":
        if self.app_env not in {'production', 'staging'}:
            return self
        normalized_secret = self.jwt_secret.strip().lower()
        if len(self.jwt_secret) < 32 or len(set(self.jwt_secret)) < 12 or normalized_secret in _UNSAFE_SECRETS or any(x in normalized_secret for x in ('change-me', 'replace-', 'development-only')):
            raise ValueError("JWT_SECRET must be a strong, non-placeholder value in production")
        if "*" in self.cors_origins:
            raise ValueError("Wildcard CORS origins are forbidden in production")
        if not self.cors_origins:
            raise ValueError("CORS_ORIGINS must contain at least one trusted origin in production")
        normalized_database_url = self.database_url.lower()
        if "localhost" in normalized_database_url or "zedbiz:zedbiz@" in normalized_database_url:
            raise ValueError("DATABASE_URL must not use local or default credentials in production")
        try:
            url = make_url(self.database_url)
            valid = url.drivername == 'postgresql+psycopg' and url.host and url.database and url.username not in {None, 'postgres'} and url.password and len(url.password) >= 24 and not any(x in url.password.lower() for x in ('replace-', 'password', 'change-me'))
        except Exception:
            valid = False
        if not valid:
            raise ValueError('DATABASE_URL requires PostgreSQL and a dedicated user with a strong explicit password')
        if any(urlsplit(o).scheme != 'https' or not urlsplit(o).hostname or urlsplit(o).path not in {'', '/'} or urlsplit(o).username or urlsplit(o).query or urlsplit(o).fragment for o in self.cors_origins):
            raise ValueError('CORS_ORIGINS must be explicit HTTPS origins')
        if not self.trusted_hosts or any('*' in h or '/' in h or ':' in h for h in self.trusted_hosts):
            raise ValueError('TRUSTED_HOSTS must list explicit hostnames in production')
        if not self.rate_limit_enabled or self.web_concurrency != 1:
            raise ValueError('Pilot production requires rate limiting and WEB_CONCURRENCY=1; use shared limits before scaling')
        if self.access_token_expire_minutes > 30 or self.refresh_token_expire_days > 30:
            raise ValueError('Production token lifetimes must not exceed 30 minutes / 30 days')
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
