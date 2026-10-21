"""Platform suspension boundaries: tests run against the isolated pytest database."""
from datetime import timedelta
from uuid import UUID

import httpx
import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import decode_token
from app.core.time import ensure_utc, utc_now
from app.models.audit_log import AuditLog
from app.models.business import Business
from app.models.business_membership import BusinessMembership
from app.models.enums import MembershipRole, SubscriptionStatus
from app.models.refresh_session import RefreshSession
from app.models.subscription import Subscription
from app.models.user import User
from app.services.commercial import ensure_founder_plan

pytestmark = pytest.mark.anyio
PASSWORD = "Strong-enough-password-42"
PREFIX = "/api/v1/admin/access"


async def test_openapi_contains_all_access_routes(client):
    response = await client.get("/openapi.json")
    assert response.status_code == 200
    routes = response.json()["paths"]
    for resource in ("businesses/{business_id}", "users/{user_id}"):
        assert "get" in routes[f"{PREFIX}/{resource}/access"]
        for action in ("suspend", "reactivate"):
            assert "post" in routes[f"{PREFIX}/{resource}/{action}"]
    assert "get" in routes[f"{PREFIX}/users"]
    assert "get" in routes[f"{PREFIX}/businesses/{{business_id}}/memberships"]
    for action in ("suspend", "reactivate"):
        assert "post" in routes[f"{PREFIX}/businesses/{{business_id}}/memberships/{{user_id}}/{action}"]


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register(client: httpx.AsyncClient, email: str) -> dict:
    result = await client.post("/api/v1/auth/register", json={
        "email": email, "full_name": "Suspension Test User", "password": PASSWORD,
    })
    assert result.status_code == 201, result.text
    return result.json()


async def business(client: httpx.AsyncClient, token: str, name: str) -> str:
    result = await client.post("/api/v1/businesses", headers=auth(token), json={"name": name})
    assert result.status_code == 201, result.text
    return result.json()["id"]


async def admin_tokens(client: httpx.AsyncClient, db: Session) -> tuple[dict, User]:
    tokens = await register(client, "suspension-admin@example.com")
    admin = db.scalar(select(User).where(User.email == "suspension-admin@example.com"))
    assert admin is not None
    admin.is_platform_admin = True
    db.commit()
    return tokens, admin


async def test_business_suspension_overrides_active_subscription_and_restores_access(
    client: httpx.AsyncClient, db: Session,
) -> None:
    owner = await register(client, "suspension-owner@example.com")
    administrator, admin = await admin_tokens(client, db)
    bid = await business(client, owner["access_token"], "Active Trial Business")
    plan, _ = ensure_founder_plan(db)
    now = utc_now()
    subscription = Subscription(
        business_id=UUID(bid), plan_id=plan.id, status=SubscriptionStatus.ACTIVE,
        starts_at=now, current_period_start=now,
        current_period_end=now + timedelta(days=30),
        grace_ends_at=now + timedelta(days=37),
    )
    db.add(subscription)
    db.commit()
    assert (await client.get(f"/api/v1/businesses/{bid}", headers=auth(owner["access_token"]))).status_code == 200
    suspended = await client.post(f"{PREFIX}/businesses/{bid}/suspend", headers=auth(administrator["access_token"]), json={"reason": "Fraud risk investigation"})
    assert suspended.status_code == 200, suspended.text
    assert suspended.json()["suspended_at"] is not None
    assert (await client.get(f"/api/v1/businesses/{bid}", headers=auth(owner["access_token"]))).status_code == 404
    listing = await client.get("/api/v1/businesses", headers=auth(owner["access_token"]))
    assert listing.status_code == 200 and all(x["id"] != bid for x in listing.json())
    assert (await client.post(f"{PREFIX}/businesses/{bid}/suspend", headers=auth(administrator["access_token"]), json={"reason": "Second suspension"})).status_code == 409
    restored = await client.post(f"{PREFIX}/businesses/{bid}/reactivate", headers=auth(administrator["access_token"]))
    assert restored.status_code == 200, restored.text
    assert restored.json()["suspended_at"] is None
    assert (await client.get(f"/api/v1/businesses/{bid}", headers=auth(owner["access_token"]))).status_code == 200
    db.refresh(subscription)
    assert subscription.status == SubscriptionStatus.ACTIVE
    assert subscription.plan_id == plan.id
    assert ensure_utc(subscription.starts_at) == now
    assert ensure_utc(subscription.current_period_start) == now
    assert ensure_utc(subscription.grace_ends_at) == now + timedelta(days=37)
    assert ensure_utc(subscription.current_period_end) == now + timedelta(days=30)
    events = db.scalars(select(AuditLog).where(AuditLog.business_id == UUID(bid), AuditLog.action.in_(["business.suspended", "business.reactivated"]))).all()
    assert {x.action for x in events} == {"business.suspended", "business.reactivated"}
    assert all(x.actor_user_id == admin.id for x in events)


async def test_membership_suspension_is_business_specific(client: httpx.AsyncClient, db: Session) -> None:
    owner = await register(client, "membership-owner@example.com")
    member_tokens = await register(client, "membership-employee@example.com")
    administrator, _ = await admin_tokens(client, db)
    a = await business(client, owner["access_token"], "Business A")
    b = await business(client, owner["access_token"], "Business B")
    member = db.scalar(select(User).where(User.email == "membership-employee@example.com"))
    assert member is not None
    db.add_all([
        BusinessMembership(user_id=member.id, business_id=UUID(a), role=MembershipRole.CASHIER),
        BusinessMembership(user_id=member.id, business_id=UUID(b), role=MembershipRole.CASHIER),
    ])
    db.commit()
    path = f"{PREFIX}/businesses/{a}/memberships/{member.id}"
    response = await client.post(path + "/suspend", headers=auth(administrator["access_token"]), json={"reason": "Temporary disciplinary suspension"})
    assert response.status_code == 200, response.text
    assert (await client.get(f"/api/v1/businesses/{a}", headers=auth(member_tokens["access_token"]))).status_code == 404
    assert (await client.get(f"/api/v1/businesses/{b}", headers=auth(member_tokens["access_token"]))).status_code == 200
    assert (await client.get("/api/v1/auth/me", headers=auth(member_tokens["access_token"]))).status_code == 200
    assert (await client.post(path + "/reactivate", headers=auth(administrator["access_token"]))).status_code == 200
    assert (await client.get(f"/api/v1/businesses/{a}", headers=auth(member_tokens["access_token"]))).status_code == 200


async def test_global_user_suspension_blocks_tokens_and_revokes_refresh_sessions(
    client: httpx.AsyncClient, db: Session,
) -> None:
    user_tokens = await register(client, "global-target@example.com")
    administrator, _ = await admin_tokens(client, db)
    target = db.scalar(select(User).where(User.email == "global-target@example.com"))
    assert target is not None
    session_id = decode_token(user_tokens["refresh_token"], "refresh").token_id
    assert session_id is not None
    result = await client.post(f"{PREFIX}/users/{target.id}/suspend", headers=auth(administrator["access_token"]), json={"reason": "Confirmed account abuse"})
    assert result.status_code == 200, result.text
    assert (await client.get("/api/v1/auth/me", headers=auth(user_tokens["access_token"]))).status_code == 401
    assert (await client.post("/api/v1/auth/refresh", json={"refresh_token": user_tokens["refresh_token"]})).status_code == 401
    assert (await client.post("/api/v1/auth/login", json={"email": target.email, "password": PASSWORD})).status_code == 401
    session = db.get(RefreshSession, session_id)
    assert session is not None and session.revoked_at is not None
    assert (await client.post(f"{PREFIX}/users/{target.id}/reactivate", headers=auth(administrator["access_token"]))).status_code == 200
    assert (await client.post("/api/v1/auth/refresh", json={"refresh_token": user_tokens["refresh_token"]})).status_code == 401
    new_login = await client.post("/api/v1/auth/login", json={"email": target.email, "password": PASSWORD})
    assert new_login.status_code == 200, new_login.text
    assert (await client.get("/api/v1/auth/me", headers=auth(new_login.json()["access_token"]))).status_code == 200


async def test_non_platform_admin_and_anonymous_cannot_suspend(client: httpx.AsyncClient, db: Session) -> None:
    owner = await register(client, "unprivileged-owner@example.com")
    bid = await business(client, owner["access_token"], "Unprivileged Business")
    url = f"{PREFIX}/businesses/{bid}/suspend"
    assert (await client.post(url, headers=auth(owner["access_token"]), json={"reason": "Unauthorized attempt"})).status_code == 403
    assert (await client.post(url, json={"reason": "Anonymous attempt"})).status_code == 401
    target = db.get(Business, UUID(bid))
    assert target is not None and target.suspended_at is None


async def test_admin_self_suspension_denied_and_reason_required(client: httpx.AsyncClient, db: Session) -> None:
    administrator, admin = await admin_tokens(client, db)
    url = f"{PREFIX}/users/{admin.id}/suspend"
    assert (await client.post(url, headers=auth(administrator["access_token"]), json={"reason": "Attempt self suspension"})).status_code == 403
    target = await register(client, "reason-target@example.com")
    me = await client.get("/api/v1/auth/me", headers=auth(target["access_token"]))
    uid = me.json()["id"]
    for reason in ["", "   ", "no"]:
        response = await client.post(f"{PREFIX}/users/{uid}/suspend", headers=auth(administrator["access_token"]), json={"reason": reason})
        assert response.status_code == 422


async def test_audit_reason_and_business_membership_history(client: httpx.AsyncClient, db: Session) -> None:
    owner = await register(client, "audit-owner@example.com")
    administrator, admin = await admin_tokens(client, db)
    bid = await business(client, owner["access_token"], "Audit Business")
    owner_user = db.scalar(select(User).where(User.email == "audit-owner@example.com"))
    assert owner_user is not None
    reason = "Administrative access review"
    path = f"{PREFIX}/businesses/{bid}/memberships/{owner_user.id}"
    assert (await client.post(path + "/suspend", headers=auth(administrator["access_token"]), json={"reason": reason})).status_code == 200
    assert (await client.post(path + "/reactivate", headers=auth(administrator["access_token"]))).status_code == 200
    events = db.scalars(select(AuditLog).where(AuditLog.business_id == UUID(bid), AuditLog.entity_type == "membership")).all()
    assert len(events) == 2
    assert events[0].metadata_json["reason"] == reason
    assert all(event.actor_user_id == admin.id for event in events)
    assert events[0].action == "membership.suspended"
    assert events[1].action == "membership.reactivated"
