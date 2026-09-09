from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx
import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import _encode_token, decode_token, hash_refresh_token, verify_password
from app.core.time import utc_now
from app.models.business_membership import BusinessMembership
from app.models.enums import MembershipRole
from app.models.refresh_session import RefreshSession
from app.models.user import User

pytestmark = pytest.mark.anyio

PASSWORD = "Strong-enough-password-42"


async def register(client: httpx.AsyncClient, email: str, full_name: str = "Test Owner") -> dict[str, Any]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"full_name": full_name, "email": email, "password": PASSWORD},
    )
    assert response.status_code == 201, response.text
    return response.json()


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def create_business(client: httpx.AsyncClient, access_token: str, name: str) -> dict[str, Any]:
    response = await client.post(
        "/api/v1/businesses",
        headers=auth(access_token),
        json={"name": name, "business_type": "Retail", "location": "Lusaka"},
    )
    assert response.status_code == 201, response.text
    return response.json()


async def test_registration_normalizes_email_hashes_password_and_returns_no_hash(
    client: httpx.AsyncClient, db: Session
) -> None:
    tokens = await register(client, "Owner@Example.COM")
    user = db.scalar(select(User).where(User.email == "owner@example.com"))

    assert user is not None
    assert user.password_hash != PASSWORD
    assert verify_password(PASSWORD, user.password_hash)
    assert tokens["token_type"] == "bearer"
    assert "password_hash" not in tokens


async def test_duplicate_registration_is_rejected_after_normalization(client: httpx.AsyncClient) -> None:
    await register(client, "owner@example.com")
    response = await client.post(
        "/api/v1/auth/register",
        json={"full_name": "Duplicate", "email": "OWNER@example.com", "password": PASSWORD},
    )

    assert response.status_code == 409


async def test_registration_rejects_weak_password_and_privilege_fields(client: httpx.AsyncClient) -> None:
    weak = await client.post(
        "/api/v1/auth/register",
        json={"full_name": "Test User", "email": "weak@example.com", "password": "password"},
    )
    privileged = await client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Safe User",
            "email": "safe@example.com",
            "password": PASSWORD,
            "is_platform_admin": True,
            "role": "OWNER",
        },
    )

    assert weak.status_code == 422
    assert '"input":"password"' not in weak.text
    assert '"input":"[redacted]"' in weak.text
    assert privileged.status_code == 422


async def test_login_success_failure_and_inactive_user_rejection(client: httpx.AsyncClient, db: Session) -> None:
    initial_tokens = await register(client, "login@example.com")
    success = await client.post(
        "/api/v1/auth/login",
        json={"email": "LOGIN@example.com", "password": PASSWORD},
    )
    wrong_password = await client.post(
        "/api/v1/auth/login",
        json={"email": "login@example.com", "password": "wrong-password"},
    )
    user = db.scalar(select(User).where(User.email == "login@example.com"))
    assert user is not None
    user.is_active = False
    db.commit()
    inactive = await client.post(
        "/api/v1/auth/login",
        json={"email": "login@example.com", "password": PASSWORD},
    )
    inactive_me = await client.get(
        "/api/v1/auth/me",
        headers=auth(initial_tokens["access_token"]),
    )

    assert success.status_code == 200
    assert wrong_password.status_code == 401
    assert inactive.status_code == 401
    assert inactive_me.status_code == 401
    assert wrong_password.json() == inactive.json()


async def test_me_requires_valid_unexpired_access_token(client: httpx.AsyncClient) -> None:
    tokens = await register(client, "me@example.com")
    valid = await client.get("/api/v1/auth/me", headers=auth(tokens["access_token"]))
    invalid = await client.get("/api/v1/auth/me", headers=auth("not-a-token"))
    refresh_as_access = await client.get(
        "/api/v1/auth/me",
        headers=auth(tokens["refresh_token"]),
    )
    access_as_refresh = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": tokens["access_token"]},
    )
    user_id = valid.json()["id"]
    expired_token = _encode_token(UUID(user_id), "access", timedelta(seconds=-1))
    expired = await client.get("/api/v1/auth/me", headers=auth(expired_token))

    assert valid.status_code == 200
    assert valid.json()["email"] == "me@example.com"
    assert "password_hash" not in valid.json()
    assert invalid.status_code == 401
    assert refresh_as_access.status_code == 401
    assert access_as_refresh.status_code == 401
    assert expired.status_code == 401


async def test_refresh_rotates_token_and_rejects_reuse(client: httpx.AsyncClient, db: Session) -> None:
    tokens = await register(client, "refresh@example.com")
    old_refresh = tokens["refresh_token"]
    old_claims = decode_token(old_refresh, "refresh")
    response = await client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
    replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
    old_session = db.get(RefreshSession, old_claims.token_id)

    assert response.status_code == 200
    assert response.json()["refresh_token"] != old_refresh
    assert replay.status_code == 401
    assert old_session is not None and old_session.revoked_at is not None
    assert old_session.replaced_by_id is not None


async def test_expired_and_revoked_refresh_tokens_are_rejected(client: httpx.AsyncClient, db: Session) -> None:
    tokens = await register(client, "expired@example.com")
    me = await client.get("/api/v1/auth/me", headers=auth(tokens["access_token"]))
    user_id = UUID(me.json()["id"])
    expired_id = uuid4()
    expired_token = _encode_token(user_id, "refresh", timedelta(seconds=-1), expired_id)
    db.add(
        RefreshSession(
            id=expired_id,
            user_id=user_id,
            token_hash=hash_refresh_token(expired_token),
            expires_at=utc_now() - timedelta(seconds=1),
        )
    )
    current_claims = decode_token(tokens["refresh_token"], "refresh")
    current_session = db.get(RefreshSession, current_claims.token_id)
    assert current_session is not None
    current_session.revoked_at = utc_now()
    db.commit()

    expired = await client.post("/api/v1/auth/refresh", json={"refresh_token": expired_token})
    revoked = await client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})

    assert expired.status_code == 401
    assert revoked.status_code == 401


async def test_logout_revokes_refresh_session(client: httpx.AsyncClient) -> None:
    tokens = await register(client, "logout@example.com")
    logout = await client.post("/api/v1/auth/logout", json={"refresh_token": tokens["refresh_token"]})
    refresh = await client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})

    assert logout.status_code == 204
    assert refresh.status_code == 401


async def test_business_creation_is_atomic_owner_membership_workflow(
    client: httpx.AsyncClient, db: Session
) -> None:
    tokens = await register(client, "business@example.com")
    business = await create_business(client, tokens["access_token"], "Brown's Tech")
    membership = db.scalar(
        select(BusinessMembership).where(BusinessMembership.business_id == UUID(business["id"]))
    )

    assert business["currency"] == "ZMW"
    assert business["timezone"] == "Africa/Lusaka"
    assert business["role"] == "OWNER"
    assert membership is not None
    assert membership.role == MembershipRole.OWNER
    assert membership.is_active


async def test_cross_tenant_read_write_and_listing_isolation(client: httpx.AsyncClient) -> None:
    user_a = await register(client, "user-a@example.com", "User A")
    user_b = await register(client, "user-b@example.com", "User B")
    business_a = await create_business(client, user_a["access_token"], "Business A")
    business_b = await create_business(client, user_b["access_token"], "Business B")

    list_a = await client.get("/api/v1/businesses", headers=auth(user_a["access_token"]))
    list_b = await client.get("/api/v1/businesses", headers=auth(user_b["access_token"]))
    assert [item["id"] for item in list_a.json()] == [business_a["id"]]
    assert [item["id"] for item in list_b.json()] == [business_b["id"]]

    assert (await client.get(f"/api/v1/businesses/{business_a['id']}", headers=auth(user_a["access_token"]))).status_code == 200
    assert (await client.get(f"/api/v1/businesses/{business_b['id']}", headers=auth(user_b["access_token"]))).status_code == 200
    assert (await client.get(f"/api/v1/businesses/{business_b['id']}", headers=auth(user_a["access_token"]))).status_code == 404
    assert (await client.get(f"/api/v1/businesses/{business_a['id']}", headers=auth(user_b["access_token"]))).status_code == 404
    assert (await client.patch(f"/api/v1/businesses/{business_b['id']}", headers=auth(user_a["access_token"]), json={"name": "Stolen"})).status_code == 404
    assert (await client.patch(f"/api/v1/businesses/{business_a['id']}", headers=auth(user_b["access_token"]), json={"name": "Stolen"})).status_code == 404


@pytest.mark.parametrize("role", [MembershipRole.MANAGER, MembershipRole.CASHIER])
async def test_non_owner_roles_cannot_update_business(
    client: httpx.AsyncClient, db: Session, role: MembershipRole
) -> None:
    owner = await register(client, f"owner-{role.value.lower()}@example.com")
    member = await register(client, f"member-{role.value.lower()}@example.com")
    business = await create_business(client, owner["access_token"], f"{role.value} Business")
    member_profile = await client.get("/api/v1/auth/me", headers=auth(member["access_token"]))
    db.add(
        BusinessMembership(
            user_id=UUID(member_profile.json()["id"]),
            business_id=UUID(business["id"]),
            role=role,
        )
    )
    db.commit()

    read = await client.get(f"/api/v1/businesses/{business['id']}", headers=auth(member["access_token"]))
    update = await client.patch(
        f"/api/v1/businesses/{business['id']}",
        headers=auth(member["access_token"]),
        json={"name": "Not Allowed"},
    )

    assert read.status_code == 200
    assert update.status_code == 403


async def test_owner_can_update_and_inactive_membership_cannot_access(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner = await register(client, "owner-update@example.com")
    business = await create_business(client, owner["access_token"], "Original Name")
    update = await client.patch(
        f"/api/v1/businesses/{business['id']}",
        headers=auth(owner["access_token"]),
        json={"name": "Updated Name"},
    )
    membership = db.scalar(
        select(BusinessMembership).where(BusinessMembership.business_id == UUID(business["id"]))
    )
    assert membership is not None
    membership.is_active = False
    db.commit()
    read = await client.get(f"/api/v1/businesses/{business['id']}", headers=auth(owner["access_token"]))
    denied_update = await client.patch(
        f"/api/v1/businesses/{business['id']}",
        headers=auth(owner["access_token"]),
        json={"name": "Should Fail"},
    )

    assert update.status_code == 200
    assert update.json()["name"] == "Updated Name"
    assert read.status_code == 404
    assert denied_update.status_code == 404
