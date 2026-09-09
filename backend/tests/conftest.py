import os
from collections.abc import AsyncGenerator, Generator

import httpx
import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

os.environ.update(
    {
        "APP_ENV": "test",
        "DATABASE_URL": "postgresql+psycopg://test:test@localhost:5432/test",
        "JWT_SECRET": "test-only-secret-that-is-longer-than-32-characters",
        "ACCESS_TOKEN_EXPIRE_MINUTES": "15",
        "REFRESH_TOKEN_EXPIRE_DAYS": "30",
    }
)

from app.db.base import Base
from app.db.session import get_db
from app.main import app
import app.models as domain_models  # noqa: F401, E402

integration_url = os.environ.get("ZEDBIZ_TEST_DATABASE_URL")
if integration_url:
    if not (make_url(integration_url).database or "").startswith("zedbiz_test_"):
        raise RuntimeError("PostgreSQL tests require a disposable zedbiz_test_ database")
    test_engine = create_engine(integration_url)
else:
    test_engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)


@event.listens_for(test_engine, "connect")
def enable_sqlite_foreign_keys(dbapi_connection: object, connection_record: object) -> None:
    if test_engine.dialect.name != "sqlite":
        return
    cursor = dbapi_connection.cursor()  # type: ignore[attr-defined]
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


TestingSession = sessionmaker(bind=test_engine, autoflush=False, expire_on_commit=False)


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def db() -> Generator[Session, None, None]:
    Base.metadata.drop_all(test_engine)
    Base.metadata.create_all(test_engine)
    with TestingSession() as session:
        yield session
        session.rollback()


@pytest.fixture
async def client(db: Session) -> AsyncGenerator[httpx.AsyncClient, None]:
    def override_db() -> Generator[Session, None, None]:
        yield db

    app.dependency_overrides[get_db] = override_db
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
        ) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.clear()
