from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status, Request
from app.core.readiness import check_database
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.health import HealthResponse

router = APIRouter()


@router.get("", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok")


@router.get("/ready", response_model=HealthResponse)
def readiness(request: Request, db: Annotated[Session, Depends(get_db)]) -> HealthResponse:
    try:
        check_database(db, production=request.app.state.settings.app_env in {'production', 'staging'})
    except (SQLAlchemyError, RuntimeError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is unavailable",
        ) from exc
    return HealthResponse(status="ok")
