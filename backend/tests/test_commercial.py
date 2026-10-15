from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID

import httpx
import pytest
from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.dependencies.business import BusinessAccess, require_business_write_access
from app.core.billing import add_calendar_month
from app.models.audit_log import AuditLog
from app.models.business import Business
from app.models.business_membership import BusinessMembership
from app.models.enums import (
    BillingPeriod,
    MembershipRole,
    OnboardingPaymentStatus,
    OnboardingStatus,
    PaymentMethod,
    SubscriptionStatus,
)
from app.models.onboarding_record import OnboardingRecord
from app.models.subscription import Subscription
from app.models.subscription_payment import SubscriptionPayment
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.schemas.commercial import OnboardingAdminUpdateRequest, PaymentRecordRequest
from app.schemas.business import BusinessCreateRequest
from app.services.businesses import BusinessService
from app.services.commercial import (
    CommercialService,
    effective_subscription_status,
    ensure_founder_plan,
)

pytestmark = pytest.mark.anyio
PASSWORD = "Strong-enough-password-42"


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register(client: httpx.AsyncClient, email: str, name: str = "Test User") -> dict[str, Any]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"full_name": name, "email": email, "password": PASSWORD},
    )
    assert response.status_code == 201, response.text
    return response.json()


async def create_business(client: httpx.AsyncClient, token: str, name: str = "Commercial Business") -> dict[str, Any]:
    response = await client.post("/api/v1/businesses", headers=auth(token), json={"name": name})
    assert response.status_code == 201, response.text
    return response.json()


async def admin_and_business(
    client: httpx.AsyncClient, db: Session
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], User]:
    owner_tokens = await register(client, "owner-commercial@example.com", "Business Owner")
    admin_tokens = await register(client, "admin-commercial@example.com", "Platform Admin")
    admin = db.scalar(select(User).where(User.email == "admin-commercial@example.com"))
    assert admin is not None
    admin.is_platform_admin = True
    db.commit()
    business = await create_business(client, owner_tokens["access_token"])
    return owner_tokens, admin_tokens, business, admin


def payment(reference: str, paid_at: datetime | None = None) -> dict[str, str]:
    payload = {"payment_method": "MTN_MONEY", "payment_reference": reference}
    if paid_at:
        payload["paid_at"] = paid_at.isoformat()
    return payload


async def complete_onboarding(client: httpx.AsyncClient, admin_token: str, business_id: str) -> None:
    paid = await client.patch(
        f"/api/v1/admin/businesses/{business_id}/onboarding",
        headers=auth(admin_token),
        json={
            "payment_status": "PAID",
            "payment_method": "MTN_MONEY",
            "payment_reference": f"ONBOARD-{business_id}",
            "assign_to_me": True,
        },
    )
    assert paid.status_code == 200, paid.text
    started = await client.patch(
        f"/api/v1/admin/businesses/{business_id}/onboarding",
        headers=auth(admin_token),
        json={"onboarding_status": "IN_PROGRESS"},
    )
    assert started.status_code == 200, started.text
    completed = await client.patch(
        f"/api/v1/admin/businesses/{business_id}/onboarding",
        headers=auth(admin_token),
        json={"onboarding_status": "COMPLETED"},
    )
    assert completed.status_code == 200, completed.text


def test_founder_plan_seed_is_idempotent_and_money_is_decimal(db: Session) -> None:
    first, first_created = ensure_founder_plan(db)
    second, second_created = ensure_founder_plan(db)
    db.add_all(
        [
            SubscriptionPlan(
                name=f"Money {value}", code=f"MONEY_{index}", currency="ZMW", price=Decimal(value),
                billing_period=BillingPeriod.MONTHLY, grace_period_days=7,
            )
            for index, value in enumerate(["0.01", "200.00", "999999.99"])
        ]
    )
    db.commit()

    values = db.scalars(select(SubscriptionPlan.price).order_by(SubscriptionPlan.price)).all()
    assert first_created is True
    assert second_created is False
    assert first.id == second.id
    assert first.price == Decimal("79.00")
    assert db.scalar(select(func.count()).select_from(SubscriptionPlan).where(SubscriptionPlan.code == "FOUNDER")) == 1
    assert Decimal("0.01") in values
    assert Decimal("200.00") in values
    assert Decimal("999999.99") in values


def test_calendar_month_arithmetic_preserves_month_end_and_leap_year() -> None:
    assert add_calendar_month(datetime(2025, 1, 31, tzinfo=UTC)) == datetime(2025, 2, 28, tzinfo=UTC)
    assert add_calendar_month(datetime(2024, 1, 31, tzinfo=UTC)) == datetime(2024, 2, 29, tzinfo=UTC)
    assert add_calendar_month(datetime(2024, 2, 29, tzinfo=UTC)) == datetime(2024, 3, 31, tzinfo=UTC)
    assert add_calendar_month(datetime(2025, 12, 15, tzinfo=UTC)) == datetime(2026, 1, 15, tzinfo=UTC)


async def test_business_creation_adds_default_onboarding_atomically(client: httpx.AsyncClient, db: Session) -> None:
    tokens = await register(client, "new-business@example.com")
    business = await create_business(client, tokens["access_token"])
    business_id = UUID(business["id"])
    membership = db.scalar(select(BusinessMembership).where(BusinessMembership.business_id == business_id))
    onboarding = db.scalar(select(OnboardingRecord).where(OnboardingRecord.business_id == business_id))

    assert membership is not None and membership.role == MembershipRole.OWNER
    assert onboarding is not None
    assert onboarding.fee_amount == Decimal("200.00")
    assert onboarding.currency == "ZMW"
    assert onboarding.payment_status == OnboardingPaymentStatus.UNPAID
    assert onboarding.onboarding_status == OnboardingStatus.NOT_STARTED


@pytest.mark.parametrize("role", [MembershipRole.OWNER, MembershipRole.MANAGER, MembershipRole.CASHIER])
async def test_business_roles_never_grant_platform_admin_access(
    client: httpx.AsyncClient, db: Session, role: MembershipRole
) -> None:
    owner_tokens = await register(client, f"admin-denied-owner-{role.value}@example.com")
    member_tokens = await register(client, f"admin-denied-member-{role.value}@example.com")
    business = await create_business(client, owner_tokens["access_token"], f"Denied {role.value}")
    member = db.scalar(select(User).where(User.email == f"admin-denied-member-{role.value.lower()}@example.com"))
    if member is None:
        member = db.scalar(select(User).where(User.email == f"admin-denied-member-{role.value}@example.com".lower()))
    assert member is not None
    db.add(BusinessMembership(user_id=member.id, business_id=UUID(business["id"]), role=role))
    db.commit()

    response = await client.get("/api/v1/admin/businesses", headers=auth(member_tokens["access_token"]))
    assert response.status_code == 403


async def test_admin_onboarding_activation_renewal_and_auditing(client: httpx.AsyncClient, db: Session) -> None:
    owner_tokens, admin_tokens, business, _ = await admin_and_business(client, db)
    ensure_founder_plan(db)
    business_id = business["id"]
    admin_header = auth(admin_tokens["access_token"])

    denied = await client.post(
        f"/api/v1/admin/businesses/{business_id}/subscription/activate",
        headers=admin_header,
        json=payment("SUB-BEFORE-ONBOARDING"),
    )
    assert denied.status_code == 409

    await complete_onboarding(client, admin_tokens["access_token"], business_id)
    activation_at = datetime(2026, 8, 31, 10, tzinfo=UTC)
    activated = await client.post(
        f"/api/v1/admin/businesses/{business_id}/subscription/activate",
        headers=admin_header,
        json=payment("SUB-ACTIVATE-001", activation_at),
    )
    assert activated.status_code == 200, activated.text
    assert activated.json()["plan_price"] == "79.00"
    assert activated.json()["current_period_end"].startswith("2026-09-30")

    early_renewal = await client.post(
        f"/api/v1/admin/businesses/{business_id}/subscription/renew",
        headers=admin_header,
        json=payment("SUB-RENEW-001", datetime(2026, 9, 20, 10, tzinfo=UTC)),
    )
    assert early_renewal.status_code == 200, early_renewal.text
    assert early_renewal.json()["current_period_start"].startswith("2026-09-30")
    assert early_renewal.json()["current_period_end"].startswith("2026-10-31")

    detail = await client.get(
        f"/api/v1/admin/businesses/{business_id}/commercial", headers=admin_header
    )
    customer = await client.get(
        f"/api/v1/businesses/{business_id}/commercial-status",
        headers=auth(owner_tokens["access_token"]),
    )
    assert detail.status_code == 200
    assert detail.json()["onboarding"]["fee_amount"] == "200.00"
    assert len(detail.json()["payments"]) == 2
    assert customer.status_code == 200
    assert customer.json()["plan_price"] == "79.00"
    assert customer.json()["writes_allowed"] is True
    assert "notes" not in customer.json()
    actions = set(db.scalars(select(AuditLog.action)).all())
    assert {"onboarding.payment_paid", "onboarding.completed", "subscription.activated", "subscription.renewed"} <= actions


async def test_onboarding_waiver_and_transition_validation(client: httpx.AsyncClient, db: Session) -> None:
    _, admin_tokens, business, _ = await admin_and_business(client, db)
    business_id = business["id"]
    header = auth(admin_tokens["access_token"])
    impossible = await client.patch(
        f"/api/v1/admin/businesses/{business_id}/onboarding",
        headers=header,
        json={"onboarding_status": "COMPLETED"},
    )
    waived = await client.patch(
        f"/api/v1/admin/businesses/{business_id}/onboarding",
        headers=header,
        json={"payment_status": "WAIVED"},
    )
    started = await client.patch(
        f"/api/v1/admin/businesses/{business_id}/onboarding",
        headers=header,
        json={"onboarding_status": "IN_PROGRESS"},
    )
    completed = await client.patch(
        f"/api/v1/admin/businesses/{business_id}/onboarding",
        headers=header,
        json={"onboarding_status": "COMPLETED", "notes": "Internal only"},
    )

    assert impossible.status_code == 409
    assert waived.status_code == 200 and waived.json()["payment_status"] == "WAIVED"
    assert started.status_code == 200
    assert completed.status_code == 200 and completed.json()["completed_at"] is not None
    assert db.scalar(select(func.count()).select_from(AuditLog).where(AuditLog.action == "onboarding.payment_waived")) == 1


async def test_cross_tenant_commercial_privacy_and_role_visibility(client: httpx.AsyncClient, db: Session) -> None:
    owner = await register(client, "commercial-owner@example.com")
    outsider = await register(client, "commercial-outsider@example.com")
    manager_tokens = await register(client, "commercial-manager@example.com")
    business = await create_business(client, owner["access_token"])
    business_id = UUID(business["id"])
    onboarding = db.scalar(select(OnboardingRecord).where(OnboardingRecord.business_id == business_id))
    manager = db.scalar(select(User).where(User.email == "commercial-manager@example.com"))
    assert onboarding is not None and manager is not None
    onboarding.notes = "Never return this internal note"
    db.add(BusinessMembership(user_id=manager.id, business_id=business_id, role=MembershipRole.MANAGER))
    db.commit()

    denied = await client.get(
        f"/api/v1/businesses/{business_id}/commercial-status", headers=auth(outsider["access_token"])
    )
    manager_view = await client.get(
        f"/api/v1/businesses/{business_id}/commercial-status", headers=auth(manager_tokens["access_token"])
    )
    assert denied.status_code == 404
    assert manager_view.status_code == 200
    assert manager_view.json()["can_manage_commercial"] is False
    assert manager_view.json()["onboarding_fee"] is None
    assert manager_view.json()["onboarding_payment_status"] is None
    assert "notes" not in manager_view.json()


async def test_state_boundaries_read_only_guard_and_expired_renewal(client: httpx.AsyncClient, db: Session) -> None:
    owner_tokens, admin_tokens, business_json, _ = await admin_and_business(client, db)
    plan, _ = ensure_founder_plan(db)
    await complete_onboarding(client, admin_tokens["access_token"], business_json["id"])
    business_id = UUID(business_json["id"])
    start = datetime(2026, 1, 1, tzinfo=UTC)
    subscription = Subscription(
        business_id=business_id,
        plan_id=plan.id,
        status=SubscriptionStatus.ACTIVE,
        starts_at=start,
        current_period_start=start,
        current_period_end=start + timedelta(days=1),
        grace_ends_at=start + timedelta(days=8),
    )
    db.add(subscription)
    db.commit()
    business = db.get(Business, business_id)
    membership = db.scalar(select(BusinessMembership).where(BusinessMembership.business_id == business_id))
    assert business is not None and membership is not None
    access = BusinessAccess(business=business, membership=membership)

    assert effective_subscription_status(subscription, start) == SubscriptionStatus.ACTIVE
    assert effective_subscription_status(subscription, start + timedelta(days=1)) == SubscriptionStatus.GRACE_PERIOD
    assert effective_subscription_status(subscription, start + timedelta(days=8)) == SubscriptionStatus.GRACE_PERIOD
    assert effective_subscription_status(subscription, start + timedelta(days=8, microseconds=1)) == SubscriptionStatus.EXPIRED
    subscription.cancelled_at = start
    assert effective_subscription_status(subscription, start) == SubscriptionStatus.CANCELLED
    subscription.cancelled_at = None

    subscription.current_period_end = datetime.now(UTC) - timedelta(days=3)
    subscription.grace_ends_at = datetime.now(UTC) + timedelta(days=2)
    db.commit()
    assert require_business_write_access(access, db) == access
    grace_update = await client.patch(
        f"/api/v1/businesses/{business_id}",
        headers=auth(owner_tokens["access_token"]),
        json={"name": "Grace Update Allowed"},
    )
    assert grace_update.status_code == 200
    subscription.grace_ends_at = datetime.now(UTC) - timedelta(seconds=1)
    db.commit()
    with pytest.raises(HTTPException) as error:
        require_business_write_access(access, db)
    assert error.value.status_code == 402
    read = await client.get(f"/api/v1/businesses/{business_id}", headers=auth(owner_tokens["access_token"]))
    expired_update = await client.patch(
        f"/api/v1/businesses/{business_id}",
        headers=auth(owner_tokens["access_token"]),
        json={"name": "Expired Update Denied"},
    )
    assert read.status_code == 200
    assert expired_update.status_code == 402

    renewal_at = datetime(2026, 11, 15, 9, tzinfo=UTC)
    renewed = await client.post(
        f"/api/v1/admin/businesses/{business_id}/subscription/renew",
        headers=auth(admin_tokens["access_token"]),
        json=payment("EXPIRED-RENEWAL", renewal_at),
    )
    assert renewed.status_code == 200, renewed.text
    assert renewed.json()["current_period_start"].startswith("2026-11-15")
    assert renewed.json()["current_period_end"].startswith("2026-12-15")
    assert renewed.json()["status"] == "ACTIVE"


async def test_duplicate_payment_rolls_back_renewal(client: httpx.AsyncClient, db: Session) -> None:
    _, admin_tokens, business, _ = await admin_and_business(client, db)
    ensure_founder_plan(db)
    await complete_onboarding(client, admin_tokens["access_token"], business["id"])
    header = auth(admin_tokens["access_token"])
    activated = await client.post(
        f"/api/v1/admin/businesses/{business['id']}/subscription/activate",
        headers=header,
        json=payment("DUPLICATE-REFERENCE"),
    )
    assert activated.status_code == 200
    original_end = activated.json()["current_period_end"]
    duplicate = await client.post(
        f"/api/v1/admin/businesses/{business['id']}/subscription/renew",
        headers=header,
        json=payment("DUPLICATE-REFERENCE"),
    )
    subscription = db.scalar(select(Subscription).where(Subscription.business_id == UUID(business["id"])))
    assert duplicate.status_code == 409
    assert subscription is not None
    assert subscription.current_period_end.isoformat().startswith(original_end[:19])
    assert db.scalar(select(func.count()).select_from(SubscriptionPayment)) == 1


def test_activation_and_onboarding_failures_rollback_all_changes(db: Session, monkeypatch: pytest.MonkeyPatch) -> None:
    owner = User(email="tx-owner@example.com", full_name="Tx Owner", password_hash="not-a-real-password-hash")
    admin = User(email="tx-admin@example.com", full_name="Tx Admin", password_hash="not-a-real-password-hash", is_platform_admin=True)
    business = Business(name="Transactional Business")
    db.add_all([owner, admin, business])
    db.flush()
    membership = BusinessMembership(user_id=owner.id, business_id=business.id, role=MembershipRole.OWNER)
    onboarding = OnboardingRecord(
        business_id=business.id,
        payment_status=OnboardingPaymentStatus.PAID,
        onboarding_status=OnboardingStatus.COMPLETED,
        payment_method=PaymentMethod.CASH,
        payment_reference="ONBOARD-TX",
    )
    db.add_all([membership, onboarding])
    db.commit()
    ensure_founder_plan(db)
    service = CommercialService(db)

    def fail_payment(*args: object, **kwargs: object) -> None:
        raise RuntimeError("simulated payment failure")

    monkeypatch.setattr(service, "_payment", fail_payment)
    with pytest.raises(RuntimeError, match="simulated payment failure"):
        service.activate(
            business.id,
            PaymentRecordRequest(payment_method=PaymentMethod.CASH, payment_reference="TX-FAIL"),
            admin,
        )
    assert db.scalar(select(Subscription).where(Subscription.business_id == business.id)) is None
    assert db.scalar(select(func.count()).select_from(SubscriptionPayment)) == 0
    assert db.scalar(select(func.count()).select_from(AuditLog)) == 0

    onboarding.payment_status = OnboardingPaymentStatus.UNPAID
    onboarding.onboarding_status = OnboardingStatus.NOT_STARTED
    onboarding.paid_at = None
    onboarding.payment_method = None
    onboarding.payment_reference = None
    db.commit()

    def fail_audit(*args: object, **kwargs: object) -> None:
        raise RuntimeError("simulated audit failure")

    monkeypatch.setattr("app.services.commercial.add_audit", fail_audit)
    with pytest.raises(RuntimeError, match="simulated audit failure"):
        service.update_onboarding(
            business.id,
            OnboardingAdminUpdateRequest(
                payment_status=OnboardingPaymentStatus.PAID,
                payment_method=PaymentMethod.CASH,
                payment_reference="ONBOARD-FAIL",
            ),
            admin,
        )
    db.refresh(onboarding)
    assert onboarding.payment_status == OnboardingPaymentStatus.UNPAID
    assert onboarding.payment_reference is None


def test_business_commercial_creation_rolls_back_when_commit_fails(
    db: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    owner = User(
        email="business-tx@example.com",
        full_name="Business Tx",
        password_hash="not-a-real-password-hash",
    )
    db.add(owner)
    db.commit()

    def fail_commit() -> None:
        raise RuntimeError("simulated commit failure")

    monkeypatch.setattr(db, "commit", fail_commit)
    with pytest.raises(RuntimeError, match="simulated commit failure"):
        BusinessService(db).create_for_owner(BusinessCreateRequest(name="Rollback Business"), owner)

    assert db.scalar(select(Business).where(Business.name == "Rollback Business")) is None
    assert db.scalar(select(func.count()).select_from(OnboardingRecord)) == 0
    assert db.scalar(select(func.count()).select_from(BusinessMembership)) == 0


async def test_promoted_admin_profile_survives_refresh_and_revocation_is_immediate(client: httpx.AsyncClient, db: Session) -> None:
    _, tokens, business, admin = await admin_and_business(client, db)
    me = await client.get('/api/v1/auth/me', headers=auth(tokens['access_token']))
    assert me.json()['is_platform_admin'] is True
    refreshed = await client.post('/api/v1/auth/refresh', json={'refresh_token': tokens['refresh_token']})
    assert refreshed.status_code == 200
    header = auth(refreshed.json()['access_token'])
    assert (await client.get('/api/v1/auth/me', headers=header)).json()['is_platform_admin'] is True
    assert (await client.get('/api/v1/admin/businesses', headers=header)).status_code == 200
    await complete_onboarding(client, refreshed.json()['access_token'], business['id'])
    detail = await client.get(f"/api/v1/admin/businesses/{business['id']}/commercial", headers=header)
    assert detail.status_code == 200
    assert detail.json()['audit_history']
    assert all(set(e) == {'id', 'actor_user_id', 'action', 'created_at'} for e in detail.json()['audit_history'])
    admin.is_platform_admin = False
    db.commit()
    assert (await client.get('/api/v1/admin/businesses', headers=header)).status_code == 403
    assert (await client.get(f"/api/v1/admin/businesses/{business['id']}/commercial", headers=header)).status_code == 403
