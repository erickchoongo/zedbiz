"""Platform-only suspension and reactivation controls.

A suspension is independent of the subscription/trial lifecycle and of is_active.
"""
from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies.admin import PlatformAdmin
from app.core.time import utc_now
from app.db.session import get_db
from app.models.audit_log import AuditLog
from app.models.business import Business
from app.models.business_membership import BusinessMembership
from app.models.user import User
from app.repositories.refresh_sessions import RefreshSessionRepository

router = APIRouter()


class SuspensionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    reason: str = Field(min_length=5, max_length=2000)

    @field_validator("reason")
    @classmethod
    def nonblank_reason(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 5:
            raise ValueError("A suspension reason of at least 5 characters is required")
        return value


class AccessState(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    is_active: bool
    suspended_at: datetime | None
    suspension_reason: str | None
    suspended_by_user_id: UUID | None


class MembershipAccessState(AccessState):
    user_id: UUID
    business_id: UUID


def _lookup(db: Session, model: type, object_id: UUID, label: str):
    obj = db.get(model, object_id)
    if obj is None:
        raise HTTPException(status_code=404, detail=f"{label} not found")
    return obj


def _change(db: Session, actor: User, target, kind: str, suspend: bool, reason: str | None = None) -> None:
    if suspend and target.suspended_at is not None:
        raise HTTPException(status_code=409, detail=f"{kind.capitalize()} is already suspended")
    if not suspend and target.suspended_at is None:
        raise HTTPException(status_code=409, detail=f"{kind.capitalize()} is not suspended")
    if suspend:
        target.suspended_at = utc_now()
        target.suspension_reason = reason
        target.suspended_by_user_id = actor.id
    else:
        target.suspended_at = None
        target.suspension_reason = None
        target.suspended_by_user_id = None
    business_id = target.id if kind == "business" else (target.business_id if kind == "membership" else None)
    db.add(AuditLog(
        actor_user_id=actor.id,
        business_id=business_id,
        action=f"{kind}.{'suspended' if suspend else 'reactivated'}",
        entity_type=kind,
        entity_id=target.id,
        metadata_json={"reason": reason if suspend else None},
    ))


@router.get("/businesses/{business_id}/access", response_model=AccessState)
def business_access(business_id: UUID, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    return _lookup(db, Business, business_id, "Business")


@router.post("/businesses/{business_id}/suspend", response_model=AccessState)
def suspend_business(business_id: UUID, request: SuspensionRequest, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    business = _lookup(db, Business, business_id, "Business")
    _change(db, admin, business, "business", True, request.reason)
    db.commit()
    db.refresh(business)
    return business


@router.post("/businesses/{business_id}/reactivate", response_model=AccessState)
def reactivate_business(business_id: UUID, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    business = _lookup(db, Business, business_id, "Business")
    _change(db, admin, business, "business", False)
    db.commit()
    db.refresh(business)
    return business


@router.get("/users", response_model=list[AccessState])
def list_users(admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)], email: Annotated[str | None, Query(max_length=320)] = None):
    statement = select(User)
    if email:
        statement = statement.where(User.email.ilike(f"%{email.strip()}%"))
    return db.scalars(statement.order_by(User.created_at.desc()).limit(100)).all()


@router.get("/users/{user_id}/access", response_model=AccessState)
def user_access(user_id: UUID, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    return _lookup(db, User, user_id, "User")


@router.post("/users/{user_id}/suspend", response_model=AccessState)
def suspend_user(user_id: UUID, request: SuspensionRequest, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    user = _lookup(db, User, user_id, "User")
    if user.id == admin.id or user.is_platform_admin:
        raise HTTPException(status_code=403, detail="Platform administrator accounts cannot be suspended via this endpoint")
    _change(db, admin, user, "user", True, request.reason)
    RefreshSessionRepository(db).revoke_all_for_user(user.id)
    db.commit()
    db.refresh(user)
    return user


@router.post("/users/{user_id}/reactivate", response_model=AccessState)
def reactivate_user(user_id: UUID, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    user = _lookup(db, User, user_id, "User")
    _change(db, admin, user, "user", False)
    db.commit()
    db.refresh(user)
    return user


@router.get("/businesses/{business_id}/memberships", response_model=list[MembershipAccessState])
def list_memberships(business_id: UUID, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    _lookup(db, Business, business_id, "Business")
    return db.scalars(select(BusinessMembership).where(BusinessMembership.business_id == business_id).order_by(BusinessMembership.created_at)).all()


def _membership(db: Session, business_id: UUID, user_id: UUID) -> BusinessMembership:
    membership = db.scalar(select(BusinessMembership).where(
        BusinessMembership.business_id == business_id,
        BusinessMembership.user_id == user_id,
    ))
    if membership is None:
        raise HTTPException(status_code=404, detail="Business membership not found")
    return membership


@router.post("/businesses/{business_id}/memberships/{user_id}/suspend", response_model=MembershipAccessState)
def suspend_membership(business_id: UUID, user_id: UUID, request: SuspensionRequest, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    membership = _membership(db, business_id, user_id)
    _change(db, admin, membership, "membership", True, request.reason)
    db.commit()
    db.refresh(membership)
    return membership


@router.post("/businesses/{business_id}/memberships/{user_id}/reactivate", response_model=MembershipAccessState)
def reactivate_membership(business_id: UUID, user_id: UUID, admin: PlatformAdmin, db: Annotated[Session, Depends(get_db)]):
    membership = _membership(db, business_id, user_id)
    _change(db, admin, membership, "membership", False)
    db.commit()
    db.refresh(membership)
    return membership
