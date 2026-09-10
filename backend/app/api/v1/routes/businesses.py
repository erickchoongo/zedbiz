from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.api.dependencies.auth import CurrentUser
from app.api.dependencies.business import (
    BusinessAccess,
    BusinessMemberAccess,
    require_owner_business_profile_write_access,
)
from app.db.session import get_db
from app.repositories.businesses import BusinessWithRole
from app.schemas.business import BusinessCreateRequest, BusinessResponse, BusinessUpdateRequest
from app.services.businesses import BusinessService

router = APIRouter()


def _response(result: BusinessWithRole) -> BusinessResponse:
    return BusinessResponse.model_validate({**result.business.__dict__, "role": result.role})


@router.post("", response_model=BusinessResponse, status_code=status.HTTP_201_CREATED)
def create_business(
    request: BusinessCreateRequest,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> BusinessResponse:
    return _response(BusinessService(db).create_for_owner(request, current_user))


@router.get("", response_model=list[BusinessResponse])
def list_businesses(current_user: CurrentUser, db: Annotated[Session, Depends(get_db)]) -> list[BusinessResponse]:
    return [_response(result) for result in BusinessService(db).list_for_user(current_user.id)]


@router.get("/{business_id}", response_model=BusinessResponse)
def get_business(business_id: UUID, access: BusinessMemberAccess) -> BusinessResponse:
    return _response(BusinessWithRole(business=access.business, role=access.membership.role))


@router.patch("/{business_id}", response_model=BusinessResponse)
def update_business(
    business_id: UUID,
    request: BusinessUpdateRequest,
    access: Annotated[BusinessAccess, Depends(require_owner_business_profile_write_access)],
    db: Annotated[Session, Depends(get_db)],
) -> BusinessResponse:
    business = BusinessService(db).update(access.business, request, access.membership.user_id)
    return _response(BusinessWithRole(business=business, role=access.membership.role))
