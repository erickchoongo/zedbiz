from dataclasses import dataclass
from typing import Annotated, Callable
from uuid import UUID

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies.auth import CurrentUser
from app.db.session import get_db
from app.models.business import Business
from app.models.business_membership import BusinessMembership
from app.models.enums import MembershipRole
from app.models.subscription import Subscription
from app.services.commercial import effective_subscription_status
from app.models.enums import SubscriptionStatus


@dataclass(frozen=True)
class BusinessAccess:
    business: Business
    membership: BusinessMembership


def get_business_access(
    business_id: UUID,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> BusinessAccess:
    row = db.execute(
        select(Business, BusinessMembership)
        .join(BusinessMembership, BusinessMembership.business_id == Business.id)
        .where(
            Business.id == business_id,
            Business.is_active.is_(True),
            Business.suspended_at.is_(None),
            BusinessMembership.user_id == current_user.id,
            BusinessMembership.is_active.is_(True),
            BusinessMembership.suspended_at.is_(None),
        )
    ).one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Business not found")
    business, membership = row
    return BusinessAccess(business=business, membership=membership)


def require_business_roles(*roles: MembershipRole) -> Callable[..., BusinessAccess]:
    def dependency(access: Annotated[BusinessAccess, Depends(get_business_access)]) -> BusinessAccess:
        if access.membership.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
        return access

    return dependency


BusinessMemberAccess = Annotated[BusinessAccess, Depends(get_business_access)]


def require_business_write_access(
    access: Annotated[BusinessAccess, Depends(get_business_access)],
    db: Annotated[Session, Depends(get_db)],
) -> BusinessAccess:
    subscription = db.scalar(select(Subscription).where(Subscription.business_id == access.business.id))
    effective = effective_subscription_status(subscription)
    if effective not in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE_PERIOD}:
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="An active subscription is required for business changes",
        )
    return access


BusinessWriteAccess = Annotated[BusinessAccess, Depends(require_business_write_access)]


def require_owner_business_profile_write_access(
    access: Annotated[BusinessAccess, Depends(get_business_access)],
    db: Annotated[Session, Depends(get_db)],
) -> BusinessAccess:
    if access.membership.role != MembershipRole.OWNER:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    subscription = db.scalar(select(Subscription).where(Subscription.business_id == access.business.id))
    if subscription is not None and effective_subscription_status(subscription) not in {
        SubscriptionStatus.ACTIVE,
        SubscriptionStatus.GRACE_PERIOD,
    }:
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Subscription renewal is required for business changes",
        )
    return access
