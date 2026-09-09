from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies.business import BusinessMemberAccess
from app.db.session import get_db
from app.models.enums import MembershipRole
from app.models.subscription_plan import SubscriptionPlan
from app.core.constants import FOUNDER_PLAN_CODE
from app.schemas.commercial import CommercialStatusResponse
from app.services.commercial import CommercialService, effective_subscription_status, subscription_writes_allowed

router = APIRouter()


@router.get("/{business_id}/commercial-status", response_model=CommercialStatusResponse)
def get_commercial_status(
    business_id: UUID,
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> CommercialStatusResponse:
    onboarding, subscription = CommercialService(db).get_records(business_id)
    plan = (
        db.get(SubscriptionPlan, subscription.plan_id)
        if subscription is not None
        else db.scalar(
            select(SubscriptionPlan).where(
                SubscriptionPlan.code == FOUNDER_PLAN_CODE,
                SubscriptionPlan.is_active.is_(True),
            )
        )
    )
    owner = access.membership.role == MembershipRole.OWNER
    service = CommercialService(db)
    return CommercialStatusResponse(
        plan_name=plan.name if plan else None,
        plan_code=plan.code if plan else None,
        plan_price=plan.price if plan and owner else None,
        currency=plan.currency if plan else onboarding.currency,
        subscription_status=effective_subscription_status(subscription),
        current_period_end=subscription.current_period_end if subscription else None,
        grace_ends_at=subscription.grace_ends_at if subscription else None,
        onboarding_status=onboarding.onboarding_status,
        onboarding_payment_status=onboarding.payment_status if owner else None,
        onboarding_fee=onboarding.fee_amount if owner else None,
        writes_allowed=subscription_writes_allowed(subscription),
        days_remaining=service.commercial_days_remaining(subscription),
        can_manage_commercial=owner,
    )
