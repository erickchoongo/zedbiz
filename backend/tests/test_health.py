from collections.abc import Generator
from unittest.mock import Mock

import httpx
import pytest
from sqlalchemy.exc import OperationalError

from app.db.session import get_db
from app.main import app


@pytest.mark.anyio
async def test_health_returns_ok() -> None:
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.anyio
async def test_readiness_returns_ok_when_database_responds() -> None:
    session = Mock()

    def override_db() -> Generator[Mock, None, None]:
        yield session

    app.dependency_overrides[get_db] = override_db
    try:
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/api/v1/health/ready")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    session.execute.assert_called_once()


@pytest.mark.anyio
async def test_readiness_returns_503_when_database_is_unavailable() -> None:
    session = Mock()
    session.execute.side_effect = OperationalError("SELECT 1", {}, Exception("offline"))

    def override_db() -> Generator[Mock, None, None]:
        yield session

    app.dependency_overrides[get_db] = override_db
    try:
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/api/v1/health/ready")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json() == {"detail": "Database is unavailable"}
