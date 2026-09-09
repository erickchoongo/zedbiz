import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_development_configuration_accepts_local_defaults() -> None:
    settings = Settings(app_env="development")

    assert settings.app_name == "ZedBiz API"


def test_cors_origins_parse_from_comma_separated_environment_value(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ORIGINS", "http://localhost:3000, http://localhost:8080")

    settings = Settings(_env_file=None)

    assert settings.cors_origins == ["http://localhost:3000", "http://localhost:8080"]


@pytest.mark.parametrize("secret", ["short", "change-me", "replace-with-at-least-32-random-characters"])
def test_production_rejects_unsafe_jwt_secrets(secret: str) -> None:
    with pytest.raises(ValidationError, match="JWT_SECRET"):
        Settings(app_env="production", jwt_secret=secret, cors_origins=["https://app.zedbiz.example"], database_url="postgresql+psycopg://app:strong-password@db.internal/zedbiz")


def test_production_rejects_wildcard_cors() -> None:
    with pytest.raises(ValidationError, match="Wildcard CORS"):
        Settings(app_env="production", jwt_secret="a-strong-production-secret-with-entropy", cors_origins=["*"], database_url="postgresql+psycopg://app:strong-password@db.internal/zedbiz")


def test_production_requires_trusted_cors_origin() -> None:
    with pytest.raises(ValidationError, match="CORS_ORIGINS"):
        Settings(app_env="production", jwt_secret="a-strong-production-secret-with-entropy", cors_origins=[], database_url="postgresql+psycopg://app:strong-password@db.internal/zedbiz")


def test_production_rejects_local_database_configuration() -> None:
    with pytest.raises(ValidationError, match="DATABASE_URL"):
        Settings(app_env="production", jwt_secret="a-strong-production-secret-with-entropy", cors_origins=["https://app.zedbiz.example"])
