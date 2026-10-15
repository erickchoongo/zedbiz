from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.api.dependencies.admin import PlatformAdmin
from app.db.session import get_db
from app.models.audit_log import AuditLog
from app.models.business import Business
from app.models.business_membership import BusinessMembership
from app.models.enums import MembershipRole, OnboardingStatus, SubscriptionStatus
from app.models.onboarding_record import OnboardingRecord
from app.models.subscription import Subscription
from app.models.subscription_payment import SubscriptionPayment
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.schemas.commercial import (
    AdminBusinessIdentityResponse,
    AdminBusinessListResponse,
    AdminBusinessSummaryResponse,
    AdminCommercialDetailResponse,
    AdminCommercialAuditResponse,
    OnboardingAdminResponse,
    OnboardingAdminUpdateRequest,
    PaymentRecordRequest,
    SubscriptionAdminResponse,
    SubscriptionPaymentResponse,
)
from app.services.commercial import CommercialService, effective_subscription_status
from app.core.time import utc_now

router = APIRouter()


def _subscription_response(subscription: Subscription, plan: SubscriptionPlan) -> SubscriptionAdminResponse:
    return SubscriptionAdminResponse(
        id=subscription.id,
        plan_name=plan.name,
        plan_code=plan.code,
        plan_price=plan.price,
        currency=plan.currency,
        status=effective_subscription_status(subscription),
        starts_at=subscription.starts_at,
        current_period_start=subscription.current_period_start,
        current_period_end=subscription.current_period_end,
        grace_ends_at=subscription.grace_ends_at,
        cancelled_at=subscription.cancelled_at,
    )


@router.get("/businesses", response_model=AdminBusinessListResponse)
def list_admin_businesses(
    admin: PlatformAdmin,
    db: Annotated[Session, Depends(get_db)],
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 25,
    search: Annotated[str | None, Query(max_length=100)] = None,
    subscription_status: SubscriptionStatus | None = None,
    onboarding_status: OnboardingStatus | None = None,
) -> AdminBusinessListResponse:
    del admin
    owner_name = (
        select(User.full_name)
        .join(BusinessMembership, BusinessMembership.user_id == User.id)
        .where(
            BusinessMembership.business_id == Business.id,
            BusinessMembership.role == MembershipRole.OWNER,
            BusinessMembership.is_active.is_(True),
        )
        .order_by(User.created_at, User.id)
        .limit(1)
        .correlate(Business)
        .scalar_subquery()
    )
    owner_email = (
        select(User.email)
        .join(BusinessMembership, BusinessMembership.user_id == User.id)
        .where(
            BusinessMembership.business_id == Business.id,
            BusinessMembership.role == MembershipRole.OWNER,
            BusinessMembership.is_active.is_(True),
        )
        .order_by(User.created_at, User.id)
        .limit(1)
        .correlate(Business)
        .scalar_subquery()
    )
    statement = (
        select(Business, owner_name, owner_email, OnboardingRecord, Subscription)
        .join(OnboardingRecord, OnboardingRecord.business_id == Business.id)
        .outerjoin(Subscription, Subscription.business_id == Business.id)
    )
    if search:
        pattern = f"%{search.strip()}%"
        statement = statement.where(or_(Business.name.ilike(pattern), owner_email.ilike(pattern)))
    if onboarding_status:
        statement = statement.where(OnboardingRecord.onboarding_status == onboarding_status)
    if subscription_status:
        now = utc_now()
        condition = {
            SubscriptionStatus.PENDING: Subscription.id.is_(None),
            SubscriptionStatus.ACTIVE: Subscription.cancelled_at.is_(None) & (Subscription.current_period_end > now),
            SubscriptionStatus.GRACE_PERIOD: Subscription.cancelled_at.is_(None)
            & (Subscription.current_period_end <= now)
            & (Subscription.grace_ends_at >= now),
            SubscriptionStatus.EXPIRED: Subscription.cancelled_at.is_(None) & (Subscription.grace_ends_at < now),
            SubscriptionStatus.CANCELLED: Subscription.cancelled_at.is_not(None),
        }[subscription_status]
        statement = statement.where(condition)
    count_statement = select(func.count()).select_from(
        statement.with_only_columns(Business.id).order_by(None).subquery()
    )
    total = db.scalar(count_statement) or 0
    rows = db.execute(
        statement.order_by(Business.name, Business.id).offset((page - 1) * page_size).limit(page_size)
    ).all()
    items = []
    for business, owner_name, owner_email, onboarding, subscription in rows:
        effective = effective_subscription_status(subscription)
        items.append(
            AdminBusinessSummaryResponse(
                id=business.id,
                name=business.name,
                owner_name=owner_name,
                owner_email=owner_email,
                onboarding_status=onboarding.onboarding_status,
                onboarding_payment_status=onboarding.payment_status,
                subscription_status=effective,
                paid_through=subscription.current_period_end if subscription else None,
            )
        )
    return AdminBusinessListResponse(items=items, page=page, page_size=page_size, total=total)


@router.get("/businesses/{business_id}/commercial", response_model=AdminCommercialDetailResponse)
def get_admin_commercial_detail(
    business_id: UUID,
    admin: PlatformAdmin,
    db: Annotated[Session, Depends(get_db)],
) -> AdminCommercialDetailResponse:
    del admin
    business = db.get(Business, business_id)
    if business is None:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Business not found")
    onboarding, subscription = CommercialService(db).get_records(business_id)
    plan = db.get(SubscriptionPlan, subscription.plan_id) if subscription else None
    payments = db.scalars(
        select(SubscriptionPayment)
        .where(SubscriptionPayment.business_id == business_id)
        .order_by(SubscriptionPayment.paid_at.desc())
    ).all()
    return AdminCommercialDetailResponse(
        business=AdminBusinessIdentityResponse.model_validate(business, from_attributes=True),
        onboarding=OnboardingAdminResponse.model_validate(onboarding),
        subscription=_subscription_response(subscription, plan) if subscription and plan else None,
        payments=[SubscriptionPaymentResponse.model_validate(payment) for payment in payments],
        audit_history=[AdminCommercialAuditResponse.model_validate(event) for event in db.scalars(
            select(AuditLog).where(AuditLog.business_id == business_id,
                AuditLog.entity_type.in_(['onboarding_record', 'subscription', 'subscription_payment']))
            .order_by(AuditLog.created_at.desc(), AuditLog.id.desc()).limit(100)
        )],
    )


@router.patch("/businesses/{business_id}/onboarding", response_model=OnboardingAdminResponse)
def update_onboarding(
    business_id: UUID,
    request: OnboardingAdminUpdateRequest,
    admin: PlatformAdmin,
    db: Annotated[Session, Depends(get_db)],
) -> OnboardingAdminResponse:
    return OnboardingAdminResponse.model_validate(
        CommercialService(db).update_onboarding(business_id, request, admin)
    )


@router.post("/businesses/{business_id}/subscription/activate", response_model=SubscriptionAdminResponse)
def activate_subscription(
    business_id: UUID,
    request: PaymentRecordRequest,
    admin: PlatformAdmin,
    db: Annotated[Session, Depends(get_db)],
) -> SubscriptionAdminResponse:
    subscription = CommercialService(db).activate(business_id, request, admin)
    plan = db.get(SubscriptionPlan, subscription.plan_id)
    assert plan is not None
    return _subscription_response(subscription, plan)


@router.post("/businesses/{business_id}/subscription/renew", response_model=SubscriptionAdminResponse)
def renew_subscription(
    business_id: UUID,
    request: PaymentRecordRequest,
    admin: PlatformAdmin,
    db: Annotated[Session, Depends(get_db)],
) -> SubscriptionAdminResponse:
    subscription = CommercialService(db).renew(business_id, request, admin)
    plan = db.get(SubscriptionPlan, subscription.plan_id)
    assert plan is not None
    return _subscription_response(subscription, plan)
