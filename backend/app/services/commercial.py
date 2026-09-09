import math
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.billing import add_calendar_month
from app.core.constants import (
    DEFAULT_COMMERCIAL_CURRENCY,
    DEFAULT_GRACE_PERIOD_DAYS,
    FOUNDER_PLAN_CODE,
    FOUNDER_PLAN_NAME,
    FOUNDER_PLAN_PRICE,
)
from app.core.time import ensure_utc, utc_now
from app.models.audit_log import AuditLog
from app.models.business import Business
from app.models.business_membership import BusinessMembership
from app.models.enums import (
    BillingPeriod,
    MembershipRole,
    OnboardingPaymentStatus,
    OnboardingStatus,
    SubscriptionStatus,
)
from app.models.onboarding_record import OnboardingRecord
from app.models.subscription import Subscription
from app.models.subscription_payment import SubscriptionPayment
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.schemas.commercial import OnboardingAdminUpdateRequest, PaymentRecordRequest


def effective_subscription_status(
    subscription: Subscription | None, now: datetime | None = None
) -> SubscriptionStatus:
    if subscription is None:
        return SubscriptionStatus.PENDING
    if subscription.cancelled_at is not None or subscription.status == SubscriptionStatus.CANCELLED:
        return SubscriptionStatus.CANCELLED
    current = ensure_utc(now or utc_now())
    if current < ensure_utc(subscription.current_period_end):
        return SubscriptionStatus.ACTIVE
    if current <= ensure_utc(subscription.grace_ends_at):
        return SubscriptionStatus.GRACE_PERIOD
    return SubscriptionStatus.EXPIRED


def sync_subscription_status(subscription: Subscription, now: datetime | None = None) -> SubscriptionStatus:
    effective = effective_subscription_status(subscription, now)
    subscription.status = effective
    return effective


def subscription_writes_allowed(subscription: Subscription | None, now: datetime | None = None) -> bool:
    return effective_subscription_status(subscription, now) in {
        SubscriptionStatus.ACTIVE,
        SubscriptionStatus.GRACE_PERIOD,
    }


def add_audit(
    db: Session,
    *,
    actor_user_id: UUID | None,
    business_id: UUID | None,
    action: str,
    entity_type: str,
    entity_id: UUID | None,
    metadata: dict[str, object] | None = None,
) -> AuditLog:
    log = AuditLog(
        actor_user_id=actor_user_id,
        business_id=business_id,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        metadata_json=metadata or {},
    )
    db.add(log)
    return log


def ensure_founder_plan(db: Session) -> tuple[SubscriptionPlan, bool]:
    plan = db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == FOUNDER_PLAN_CODE))
    if plan is not None:
        return plan, False
    plan = SubscriptionPlan(
        name=FOUNDER_PLAN_NAME,
        code=FOUNDER_PLAN_CODE,
        currency=DEFAULT_COMMERCIAL_CURRENCY,
        price=Decimal(FOUNDER_PLAN_PRICE),
        billing_period=BillingPeriod.MONTHLY,
        grace_period_days=DEFAULT_GRACE_PERIOD_DAYS,
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan, True


@dataclass(frozen=True)
class AdminBusinessRow:
    business: Business
    owner_name: str | None
    owner_email: str | None
    onboarding: OnboardingRecord
    subscription: Subscription | None


class CommercialService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_records(self, business_id: UUID) -> tuple[OnboardingRecord, Subscription | None]:
        onboarding = self.db.scalar(
            select(OnboardingRecord).where(OnboardingRecord.business_id == business_id)
        )
        if onboarding is None:
            raise HTTPException(status_code=404, detail="Commercial record not found")
        subscription = self.db.scalar(
            select(Subscription).where(Subscription.business_id == business_id)
        )
        if subscription is not None:
            stored = subscription.status
            effective = sync_subscription_status(subscription)
            if effective != stored:
                self.db.commit()
        return onboarding, subscription

    def update_onboarding(
        self,
        business_id: UUID,
        request: OnboardingAdminUpdateRequest,
        admin: User,
    ) -> OnboardingRecord:
        try:
            return self._update_onboarding(business_id, request, admin)
        except Exception:
            self.db.rollback()
            raise

    def _update_onboarding(
        self,
        business_id: UUID,
        request: OnboardingAdminUpdateRequest,
        admin: User,
    ) -> OnboardingRecord:
        onboarding, _ = self.get_records(business_id)
        old_payment = onboarding.payment_status
        old_status = onboarding.onboarding_status
        payment_status = request.payment_status or old_payment
        onboarding_status = request.onboarding_status or old_status

        allowed_transitions = {
            OnboardingStatus.NOT_STARTED: {OnboardingStatus.NOT_STARTED, OnboardingStatus.IN_PROGRESS, OnboardingStatus.CANCELLED},
            OnboardingStatus.IN_PROGRESS: {OnboardingStatus.IN_PROGRESS, OnboardingStatus.COMPLETED, OnboardingStatus.CANCELLED},
            OnboardingStatus.COMPLETED: {OnboardingStatus.COMPLETED},
            OnboardingStatus.CANCELLED: {OnboardingStatus.CANCELLED},
        }
        if onboarding_status not in allowed_transitions[old_status]:
            raise HTTPException(status_code=409, detail="Invalid onboarding status transition")
        if old_payment != OnboardingPaymentStatus.UNPAID and payment_status != old_payment:
            raise HTTPException(status_code=409, detail="Finalized onboarding payment cannot be changed")
        if payment_status == OnboardingPaymentStatus.PAID:
            method = request.payment_method or onboarding.payment_method
            reference = request.payment_reference or onboarding.payment_reference
            if method is None or reference is None:
                raise HTTPException(status_code=422, detail="Paid onboarding requires payment method and reference")
            onboarding.payment_method = method
            onboarding.payment_reference = reference
            onboarding.paid_at = onboarding.paid_at or utc_now()
        elif payment_status == OnboardingPaymentStatus.WAIVED:
            onboarding.payment_method = None
            onboarding.payment_reference = None
            onboarding.paid_at = onboarding.paid_at or utc_now()
        if onboarding_status == OnboardingStatus.COMPLETED and payment_status == OnboardingPaymentStatus.UNPAID:
            raise HTTPException(status_code=409, detail="Onboarding payment must be paid or waived before completion")

        onboarding.payment_status = payment_status
        onboarding.onboarding_status = onboarding_status
        if request.assign_to_me is True:
            onboarding.assigned_admin_user_id = admin.id
        elif request.assign_to_me is False:
            onboarding.assigned_admin_user_id = None
        if "notes" in request.model_fields_set:
            onboarding.notes = request.notes
        if onboarding_status == OnboardingStatus.COMPLETED and onboarding.completed_at is None:
            onboarding.completed_at = utc_now()

        if old_payment != payment_status:
            action = "onboarding.payment_paid" if payment_status == OnboardingPaymentStatus.PAID else "onboarding.payment_waived"
            add_audit(
                self.db, actor_user_id=admin.id, business_id=business_id, action=action,
                entity_type="onboarding_record", entity_id=onboarding.id,
                metadata={"amount": format(onboarding.fee_amount, ".2f"), "currency": onboarding.currency},
            )
        if old_status != onboarding_status and onboarding_status == OnboardingStatus.COMPLETED:
            add_audit(
                self.db, actor_user_id=admin.id, business_id=business_id, action="onboarding.completed",
                entity_type="onboarding_record", entity_id=onboarding.id,
            )
        self.db.commit()
        self.db.refresh(onboarding)
        return onboarding

    def activate(self, business_id: UUID, payment: PaymentRecordRequest, admin: User) -> Subscription:
        onboarding, existing = self.get_records(business_id)
        if onboarding.onboarding_status != OnboardingStatus.COMPLETED:
            raise HTTPException(status_code=409, detail="Onboarding must be completed before subscription activation")
        if existing is not None:
            raise HTTPException(status_code=409, detail="Subscription already exists; use renewal")
        plan = self.db.scalar(
            select(SubscriptionPlan).where(
                SubscriptionPlan.code == FOUNDER_PLAN_CODE, SubscriptionPlan.is_active.is_(True)
            )
        )
        if plan is None:
            raise HTTPException(status_code=409, detail="Founder plan is not available")
        paid_at = ensure_utc(payment.paid_at or utc_now())
        period_end = add_calendar_month(paid_at)
        subscription = Subscription(
            business_id=business_id,
            plan_id=plan.id,
            status=SubscriptionStatus.ACTIVE,
            starts_at=paid_at,
            current_period_start=paid_at,
            current_period_end=period_end,
            grace_ends_at=period_end + timedelta(days=plan.grace_period_days),
        )
        self.db.add(subscription)
        try:
            self.db.flush()
            record = self._payment(subscription, plan, payment, admin, paid_at, period_end)
            add_audit(
                self.db, actor_user_id=admin.id, business_id=business_id, action="subscription.activated",
                entity_type="subscription", entity_id=subscription.id,
                metadata={"payment_id": str(record.id), "amount": format(plan.price, ".2f"), "currency": plan.currency},
            )
            self.db.commit()
            self.db.refresh(subscription)
        except IntegrityError as exc:
            self.db.rollback()
            raise HTTPException(status_code=409, detail="Payment reference has already been recorded") from exc
        except Exception:
            self.db.rollback()
            raise
        return subscription

    def renew(self, business_id: UUID, payment: PaymentRecordRequest, admin: User) -> Subscription:
        _, subscription = self.get_records(business_id)
        if subscription is None:
            raise HTTPException(status_code=409, detail="Subscription must be activated before renewal")
        plan = self.db.get(SubscriptionPlan, subscription.plan_id)
        if plan is None or not plan.is_active:
            raise HTTPException(status_code=409, detail="Subscription plan is not available")
        paid_at = ensure_utc(payment.paid_at or utc_now())
        current_end = ensure_utc(subscription.current_period_end)
        period_start = current_end if current_end > paid_at else paid_at
        period_end = add_calendar_month(period_start)
        previous = {
            "period_start": subscription.current_period_start,
            "period_end": subscription.current_period_end,
            "grace": subscription.grace_ends_at,
            "status": subscription.status,
        }
        subscription.current_period_start = period_start
        subscription.current_period_end = period_end
        subscription.grace_ends_at = period_end + timedelta(days=plan.grace_period_days)
        subscription.cancelled_at = None
        subscription.status = SubscriptionStatus.ACTIVE
        try:
            record = self._payment(subscription, plan, payment, admin, period_start, period_end)
            add_audit(
                self.db, actor_user_id=admin.id, business_id=business_id, action="subscription.renewed",
                entity_type="subscription", entity_id=subscription.id,
                metadata={"payment_id": str(record.id), "amount": format(plan.price, ".2f"), "currency": plan.currency},
            )
            self.db.commit()
            self.db.refresh(subscription)
        except IntegrityError as exc:
            self.db.rollback()
            raise HTTPException(status_code=409, detail="Payment reference has already been recorded") from exc
        except Exception:
            subscription.current_period_start = previous["period_start"]
            subscription.current_period_end = previous["period_end"]
            subscription.grace_ends_at = previous["grace"]
            subscription.status = previous["status"]
            self.db.rollback()
            raise
        return subscription

    def _payment(
        self,
        subscription: Subscription,
        plan: SubscriptionPlan,
        request: PaymentRecordRequest,
        admin: User,
        period_start: datetime,
        period_end: datetime,
    ) -> SubscriptionPayment:
        record = SubscriptionPayment(
            business_id=subscription.business_id,
            subscription_id=subscription.id,
            amount=plan.price,
            currency=plan.currency,
            payment_method=request.payment_method,
            payment_reference=request.payment_reference,
            paid_at=ensure_utc(request.paid_at or utc_now()),
            period_start=period_start,
            period_end=period_end,
            recorded_by_user_id=admin.id,
            created_at=utc_now(),
        )
        self.db.add(record)
        self.db.flush()
        return record

    def commercial_days_remaining(self, subscription: Subscription | None, now: datetime | None = None) -> int | None:
        if subscription is None:
            return None
        current = ensure_utc(now or utc_now())
        state = effective_subscription_status(subscription, current)
        boundary = subscription.current_period_end if state == SubscriptionStatus.ACTIVE else subscription.grace_ends_at
        if state in {SubscriptionStatus.EXPIRED, SubscriptionStatus.CANCELLED}:
            return 0
        seconds = (ensure_utc(boundary) - current).total_seconds()
        return max(0, math.ceil(seconds / 86400))
