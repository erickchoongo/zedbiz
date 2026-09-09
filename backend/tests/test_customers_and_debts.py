from datetime import date, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID, uuid4

import httpx
import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.audit_log import AuditLog
from app.models.business_membership import BusinessMembership
from app.models.customer import Customer
from app.models.debt import Debt
from app.models.debt_payment import DebtPayment
from app.models.enums import (
    BillingPeriod,
    DebtStatus,
    MembershipRole,
    PaymentMethod,
    SaleStatus,
    SubscriptionStatus,
)
from app.models.sale import Sale
from app.models.subscription import Subscription
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.schemas.debt import DebtPaymentCreateRequest
from app.services.debts import DebtService, lusaka_today


pytestmark = pytest.mark.anyio
PASSWORD = "Strong-enough-password-42"


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register(client: httpx.AsyncClient, email: str) -> dict[str, Any]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"full_name": email.split("@")[0], "email": email, "password": PASSWORD},
    )
    assert response.status_code == 201, response.text
    return response.json()


async def create_business(
    client: httpx.AsyncClient,
    db: Session,
    email: str,
    *,
    name: str = "Brown's Tech",
) -> tuple[dict[str, Any], str, User, Subscription]:
    tokens = await register(client, email)
    response = await client.post(
        "/api/v1/businesses",
        headers=auth(tokens["access_token"]),
        json={"name": name, "phone_number": "+260970000000", "location": "Lusaka"},
    )
    assert response.status_code == 201, response.text
    business_id = response.json()["id"]
    user = db.scalar(select(User).where(User.email == email))
    assert user is not None
    plan = SubscriptionPlan(
        name="Founder",
        code=f"DEBT-{business_id[:20]}",
        currency="ZMW",
        price=Decimal("79.00"),
        billing_period=BillingPeriod.MONTHLY,
        grace_period_days=7,
    )
    db.add(plan)
    db.flush()
    now = utc_now()
    subscription = Subscription(
        business_id=UUID(business_id),
        plan_id=plan.id,
        status=SubscriptionStatus.ACTIVE,
        starts_at=now,
        current_period_start=now,
        current_period_end=now + timedelta(days=30),
        grace_ends_at=now + timedelta(days=37),
    )
    db.add(subscription)
    db.commit()
    return tokens, business_id, user, subscription


async def add_member(
    client: httpx.AsyncClient,
    db: Session,
    business_id: str,
    *,
    role: MembershipRole,
    email: str,
) -> tuple[dict[str, Any], User]:
    tokens = await register(client, email)
    user = db.scalar(select(User).where(User.email == email))
    assert user is not None
    db.add(
        BusinessMembership(
            business_id=UUID(business_id),
            user_id=user.id,
            role=role,
        )
    )
    db.commit()
    return tokens, user


async def post_customer(
    client: httpx.AsyncClient,
    token: str,
    business_id: str,
    *,
    name: str,
    phone: str | None = None,
    email: str | None = None,
    notes: str | None = None,
) -> httpx.Response:
    return await client.post(
        f"/api/v1/businesses/{business_id}/customers",
        headers=auth(token),
        json={"name": name, "phone_number": phone, "email": email, "notes": notes},
    )


def seed_debt(
    db: Session,
    *,
    business_id: str,
    customer: Customer,
    creator: User,
    amount: str,
    amount_paid: str = "0.00",
    status: DebtStatus = DebtStatus.OPEN,
    due_date: date | None = None,
    notes: str | None = "Management-only debt note",
) -> Debt:
    original = Decimal(amount)
    paid = Decimal(amount_paid)
    now = utc_now()
    is_voided = status == DebtStatus.VOIDED
    if is_voided:
        paid = Decimal("0.00")
        outstanding = Decimal("0.00")
    else:
        outstanding = original - paid
    sale = Sale(
        business_id=UUID(business_id),
        customer_id=customer.id,
        sale_number=f"ZB-20260902-{uuid4().hex[:6].upper()}",
        status=SaleStatus.VOIDED if is_voided else SaleStatus.COMPLETED,
        subtotal=original,
        discount_amount=Decimal("0.00"),
        total_amount=original,
        total_cost=Decimal("0.00"),
        gross_profit=original,
        payment_method=PaymentMethod.CUSTOMER_DEBT,
        payment_reference=None,
        notes=None,
        client_operation_id=uuid4(),
        request_fingerprint=uuid4().hex + uuid4().hex,
        sold_by_user_id=creator.id,
        sold_at=now,
        voided_at=now if is_voided else None,
        voided_by_user_id=creator.id if is_voided else None,
        void_reason="Test reversal" if is_voided else None,
        void_client_operation_id=uuid4() if is_voided else None,
    )
    db.add(sale)
    db.flush()
    debt = Debt(
        business_id=UUID(business_id),
        customer_id=customer.id,
        sale_id=sale.id,
        original_amount=original,
        amount_paid=paid,
        outstanding_amount=outstanding,
        status=status,
        due_date=due_date,
        notes=notes,
        created_by_user_id=creator.id,
        settled_at=now if status == DebtStatus.PAID else None,
        voided_at=now if is_voided else None,
        voided_by_user_id=creator.id if is_voided else None,
    )
    db.add(debt)
    db.commit()
    db.refresh(debt)
    return debt


def payment_payload(
    amount: str,
    *,
    operation_id: str | None = None,
    method: str = "CASH",
    reference: str | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    return {
        "client_operation_id": operation_id or str(uuid4()),
        "amount": amount,
        "payment_method": method,
        "payment_reference": reference,
        "notes": notes,
    }


async def post_payment(
    client: httpx.AsyncClient,
    token: str,
    business_id: str,
    debt_id: UUID | str,
    payload: dict[str, Any],
) -> httpx.Response:
    return await client.post(
        f"/api/v1/businesses/{business_id}/debts/{debt_id}/payments",
        headers=auth(token),
        json=payload,
    )


async def test_customer_crud_phone_email_lifecycle_and_validation(
    client: httpx.AsyncClient,
    db: Session,
) -> None:
    tokens, business_id, _, _ = await create_business(client, db, "customer-crud@example.com")
    token = tokens["access_token"]
    created = await post_customer(
        client,
        token,
        business_id,
        name="  John   Banda  ",
        phone="097 123 4567",
        email="JOHN.BANDA@EXAMPLE.COM",
        notes="  Reliable wholesale customer  ",
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["name"] == "John Banda"
    assert body["phone_number"] == "+260971234567"
    assert body["email"] == "john.banda@example.com"
    assert body["notes"] == "Reliable wholesale customer"
    assert body["total_outstanding"] == "0.00" and body["recent_debts"] == []

    international = await post_customer(
        client,
        token,
        business_id,
        name="International Contact",
        phone="+1 (415) 555-2671",
    )
    assert international.status_code == 201
    assert international.json()["phone_number"] == "+14155552671"
    for invalid_phone in ["971234567", "09712", "+0123456789", "097-ABC-4567"]:
        invalid = await post_customer(
            client, token, business_id, name="Invalid Phone", phone=invalid_phone
        )
        assert invalid.status_code == 422, (invalid_phone, invalid.text)
    assert (
        await post_customer(client, token, business_id, name="   ", phone="0971234567")
    ).status_code == 422

    customer_id = body["id"]
    updated = await client.patch(
        f"/api/v1/businesses/{business_id}/customers/{customer_id}",
        headers=auth(token),
        json={"name": "John B. Banda", "phone_number": "260961112222", "email": None},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["phone_number"] == "+260961112222"
    assert updated.json()["email"] is None
    null_name = await client.patch(
        f"/api/v1/businesses/{business_id}/customers/{customer_id}",
        headers=auth(token),
        json={"name": None},
    )
    assert null_name.status_code == 422

    deactivated = await client.post(
        f"/api/v1/businesses/{business_id}/customers/{customer_id}/deactivate",
        headers=auth(token),
    )
    inactive_list = await client.get(
        f"/api/v1/businesses/{business_id}/customers?is_active=false",
        headers=auth(token),
    )
    assert [item["id"] for item in inactive_list.json()["items"]] == [customer_id]
    reactivated = await client.post(
        f"/api/v1/businesses/{business_id}/customers/{customer_id}/reactivate",
        headers=auth(token),
    )
    assert deactivated.status_code == reactivated.status_code == 200
    assert not deactivated.json()["is_active"] and reactivated.json()["is_active"]
    actions = db.scalars(
        select(AuditLog.action)
        .where(AuditLog.business_id == UUID(business_id), AuditLog.entity_id == UUID(customer_id))
        .order_by(AuditLog.created_at)
    ).all()
    assert actions == ["customer.deactivated", "customer.reactivated"]


async def test_customer_listing_search_pagination_aggregates_and_recent_debts(
    client: httpx.AsyncClient,
    db: Session,
) -> None:
    tokens, business_id, owner, _ = await create_business(client, db, "customer-list@example.com")
    token = tokens["access_token"]
    john_json = (
        await post_customer(
            client,
            token,
            business_id,
            name="John Banda",
            phone="0971111111",
            email="john@example.com",
            notes="Internal customer note",
        )
    ).json()
    mary_json = (
        await post_customer(
            client,
            token,
            business_id,
            name="Mary Phiri",
            phone="0962222222",
            email="mary@example.com",
        )
    ).json()
    john = db.get(Customer, UUID(john_json["id"]))
    mary = db.get(Customer, UUID(mary_json["id"]))
    assert john is not None and mary is not None
    today = lusaka_today()
    seed_debt(db, business_id=business_id, customer=john, creator=owner, amount="100.00", due_date=today - timedelta(days=1))
    seed_debt(db, business_id=business_id, customer=john, creator=owner, amount="50.00", due_date=today + timedelta(days=1))
    seed_debt(db, business_id=business_id, customer=john, creator=owner, amount="100.00", amount_paid="25.00", status=DebtStatus.PARTIALLY_PAID, due_date=today - timedelta(days=2))
    seed_debt(db, business_id=business_id, customer=john, creator=owner, amount="10.00", amount_paid="10.00", status=DebtStatus.PAID, due_date=today - timedelta(days=3))
    seed_debt(db, business_id=business_id, customer=john, creator=owner, amount="11.00", amount_paid="11.00", status=DebtStatus.PAID)
    seed_debt(db, business_id=business_id, customer=john, creator=owner, amount="12.00", amount_paid="12.00", status=DebtStatus.PAID)
    seed_debt(db, business_id=business_id, customer=mary, creator=owner, amount="20.00", status=DebtStatus.VOIDED, due_date=today - timedelta(days=4))

    first_page = await client.get(
        f"/api/v1/businesses/{business_id}/customers?page=1&page_size=1",
        headers=auth(token),
    )
    assert first_page.status_code == 200, first_page.text
    assert first_page.json()["total"] == 2 and len(first_page.json()["items"]) == 1
    john_row = first_page.json()["items"][0]
    assert john_row["name"] == "John Banda"
    assert john_row["total_outstanding"] == "225.00"
    assert john_row["total_overdue"] == "175.00"
    assert john_row["open_debt_count"] == 3
    assert "notes" not in john_row

    for search in ["Banda", "+260971", "JOHN@EXAMPLE.COM"]:
        response = await client.get(
            f"/api/v1/businesses/{business_id}/customers",
            headers=auth(token),
            params={"search": search},
        )
        assert response.status_code == 200 and response.json()["total"] == 1
    owing = await client.get(
        f"/api/v1/businesses/{business_id}/customers?outstanding_only=true",
        headers=auth(token),
    )
    clear = await client.get(
        f"/api/v1/businesses/{business_id}/customers?outstanding_only=false",
        headers=auth(token),
    )
    assert [item["name"] for item in owing.json()["items"]] == ["John Banda"]
    assert [item["name"] for item in clear.json()["items"]] == ["Mary Phiri"]

    detail = await client.get(
        f"/api/v1/businesses/{business_id}/customers/{john.id}", headers=auth(token)
    )
    assert detail.status_code == 200
    assert detail.json()["notes"] == "Internal customer note"
    assert len(detail.json()["recent_debts"]) == 5
    assert detail.json()["total_outstanding"] == "225.00"


async def test_customer_roles_privacy_tenant_and_subscription_enforcement(
    client: httpx.AsyncClient,
    db: Session,
) -> None:
    owner_tokens, business_id, owner, subscription = await create_business(
        client, db, "customer-role-owner@example.com"
    )
    other_tokens, other_business_id, _, _ = await create_business(
        client, db, "customer-role-other@example.com"
    )
    cashier_tokens, _ = await add_member(
        client,
        db,
        business_id,
        role=MembershipRole.CASHIER,
        email="customer-role-cashier@example.com",
    )
    manager_tokens, _ = await add_member(
        client,
        db,
        business_id,
        role=MembershipRole.MANAGER,
        email="customer-role-manager@example.com",
    )
    owner_customer = await post_customer(
        client,
        owner_tokens["access_token"],
        business_id,
        name="Private Notes",
        phone="0973333333",
        notes="Do not expose this note",
    )
    customer_id = owner_customer.json()["id"]

    cashier_detail = await client.get(
        f"/api/v1/businesses/{business_id}/customers/{customer_id}",
        headers=auth(cashier_tokens["access_token"]),
    )
    assert cashier_detail.status_code == 200 and cashier_detail.json()["notes"] is None
    cashier_created = await post_customer(
        client,
        cashier_tokens["access_token"],
        business_id,
        name="Counter Customer",
        phone="0954444444",
    )
    assert cashier_created.status_code == 201
    cashier_with_notes = await post_customer(
        client,
        cashier_tokens["access_token"],
        business_id,
        name="Forbidden Note",
        notes="sensitive",
    )
    assert cashier_with_notes.status_code == 403
    assert (
        await client.patch(
            f"/api/v1/businesses/{business_id}/customers/{customer_id}",
            headers=auth(cashier_tokens["access_token"]),
            json={"name": "Not permitted"},
        )
    ).status_code == 403
    assert (
        await client.post(
            f"/api/v1/businesses/{business_id}/customers/{customer_id}/deactivate",
            headers=auth(cashier_tokens["access_token"]),
        )
    ).status_code == 403
    assert (
        await client.patch(
            f"/api/v1/businesses/{business_id}/customers/{customer_id}",
            headers=auth(manager_tokens["access_token"]),
            json={"name": "Manager Updated"},
        )
    ).status_code == 200

    assert (
        await client.get(
            f"/api/v1/businesses/{other_business_id}/customers/{customer_id}",
            headers=auth(other_tokens["access_token"]),
        )
    ).status_code == 404
    assert (
        await client.get(
            f"/api/v1/businesses/{business_id}/customers",
            headers=auth(other_tokens["access_token"]),
        )
    ).status_code == 404

    now = utc_now()
    subscription.current_period_start = now - timedelta(days=40)
    subscription.current_period_end = now - timedelta(days=8)
    subscription.grace_ends_at = now - timedelta(days=1)
    db.commit()
    expired_create = await post_customer(
        client,
        owner_tokens["access_token"],
        business_id,
        name="Expired Write",
    )
    assert expired_create.status_code == 402
    assert (
        await client.patch(
            f"/api/v1/businesses/{business_id}/customers/{customer_id}",
            headers=auth(owner_tokens["access_token"]),
            json={"name": "Expired Update"},
        )
    ).status_code == 402
    expired_read = await client.get(
        f"/api/v1/businesses/{business_id}/customers/{customer_id}",
        headers=auth(owner_tokens["access_token"]),
    )
    assert expired_read.status_code == 200 and expired_read.json()["name"] == "Manager Updated"


async def test_debt_listing_filters_summary_detail_reminder_and_privacy(
    client: httpx.AsyncClient,
    db: Session,
) -> None:
    owner_tokens, business_id, owner, _ = await create_business(
        client, db, "debt-list-owner@example.com"
    )
    cashier_tokens, _ = await add_member(
        client,
        db,
        business_id,
        role=MembershipRole.CASHIER,
        email="debt-list-cashier@example.com",
    )
    john_data = (
        await post_customer(
            client,
            owner_tokens["access_token"],
            business_id,
            name="John Banda",
            phone="0975555555",
            notes="Internal customer note",
        )
    ).json()
    mary_data = (
        await post_customer(
            client,
            owner_tokens["access_token"],
            business_id,
            name="Mary Phiri",
            phone="0966666666",
        )
    ).json()
    john = db.get(Customer, UUID(john_data["id"]))
    mary = db.get(Customer, UUID(mary_data["id"]))
    assert john is not None and mary is not None
    today = lusaka_today()
    overdue = seed_debt(
        db,
        business_id=business_id,
        customer=john,
        creator=owner,
        amount="250.50",
        due_date=today - timedelta(days=2),
        notes="Never mention margin K99",
    )
    future = seed_debt(
        db,
        business_id=business_id,
        customer=mary,
        creator=owner,
        amount="100.00",
        due_date=today + timedelta(days=5),
    )
    seed_debt(
        db,
        business_id=business_id,
        customer=mary,
        creator=owner,
        amount="50.00",
        amount_paid="50.00",
        status=DebtStatus.PAID,
        due_date=today - timedelta(days=5),
    )
    seed_debt(
        db,
        business_id=business_id,
        customer=john,
        creator=owner,
        amount="30.00",
        status=DebtStatus.VOIDED,
        due_date=today - timedelta(days=10),
    )

    listing = await client.get(
        f"/api/v1/businesses/{business_id}/debts?page=1&page_size=10",
        headers=auth(owner_tokens["access_token"]),
    )
    assert listing.status_code == 200, listing.text
    assert listing.json()["total"] == 4
    assert listing.json()["items"][0]["id"] == str(overdue.id)
    assert listing.json()["items"][0]["is_overdue"] is True
    assert listing.json()["items"][1]["id"] == str(future.id)

    cases = [
        ({"status": "PAID"}, 1),
        ({"overdue_only": "true"}, 1),
        ({"customer_id": str(john.id)}, 2),
        ({"search": "097555"}, 2),
        ({"due_date_from": str(today), "due_date_to": str(today + timedelta(days=10))}, 1),
    ]
    for params, expected in cases:
        response = await client.get(
            f"/api/v1/businesses/{business_id}/debts",
            headers=auth(owner_tokens["access_token"]),
            params=params,
        )
        assert response.status_code == 200, response.text
        assert response.json()["total"] == expected, params
    invalid_dates = await client.get(
        f"/api/v1/businesses/{business_id}/debts",
        headers=auth(owner_tokens["access_token"]),
        params={"due_date_from": str(today), "due_date_to": str(today - timedelta(days=1))},
    )
    assert invalid_dates.status_code == 422

    summary = await client.get(
        f"/api/v1/businesses/{business_id}/debts/summary",
        headers=auth(owner_tokens["access_token"]),
    )
    assert summary.status_code == 200, summary.text
    assert summary.json() == {
        "total_outstanding": "350.50",
        "total_overdue": "250.50",
        "customers_owing": 2,
        "open_debt_count": 2,
    }
    detail = await client.get(
        f"/api/v1/businesses/{business_id}/debts/{overdue.id}",
        headers=auth(owner_tokens["access_token"]),
    )
    assert detail.status_code == 200 and detail.json()["notes"] == "Never mention margin K99"
    cashier_detail = await client.get(
        f"/api/v1/businesses/{business_id}/debts/{overdue.id}",
        headers=auth(cashier_tokens["access_token"]),
    )
    assert cashier_detail.status_code == 200 and cashier_detail.json()["notes"] is None

    reminder = await client.get(
        f"/api/v1/businesses/{business_id}/debts/{overdue.id}/reminder",
        headers=auth(cashier_tokens["access_token"]),
    )
    assert reminder.status_code == 200, reminder.text
    reminder_body = reminder.json()
    assert reminder_body["phone_number"] == "+260975555555"
    assert "Hello John Banda," in reminder_body["message"]
    assert "Brown's Tech" in reminder_body["message"]
    assert "K250.50" in reminder_body["message"]
    assert str(overdue.due_date.day) in reminder_body["message"]
    assert "margin" not in reminder_body["message"] and "Internal" not in reminder_body["message"]


async def test_partial_multiple_full_repayments_exact_balances_and_history(
    client: httpx.AsyncClient,
    db: Session,
) -> None:
    tokens, business_id, owner, _ = await create_business(client, db, "repay-exact@example.com")
    customer_body = (
        await post_customer(
            client,
            tokens["access_token"],
            business_id,
            name="Exact Customer",
            phone="0977777777",
        )
    ).json()
    customer = db.get(Customer, UUID(customer_body["id"]))
    assert customer is not None
    debt = seed_debt(
        db,
        business_id=business_id,
        customer=customer,
        creator=owner,
        amount="250.50",
        due_date=lusaka_today() - timedelta(days=1),
    )
    amounts = ["0.01", "100.00", "150.49"]
    expected = ["250.49", "150.49", "0.00"]
    payment_ids: list[str] = []
    for amount, remaining in zip(amounts, expected, strict=True):
        response = await post_payment(
            client,
            tokens["access_token"],
            business_id,
            debt.id,
            payment_payload(amount, method="MTN_MONEY", reference=f"REF-{amount}"),
        )
        assert response.status_code == 201, response.text
        body = response.json()
        payment_ids.append(body["payment"]["id"])
        assert body["payment"]["amount"] == amount
        assert body["debt"]["outstanding_amount"] == remaining
    final = db.get(Debt, debt.id)
    assert final is not None
    assert final.amount_paid == Decimal("250.50")
    assert final.outstanding_amount == Decimal("0.00")
    assert final.status == DebtStatus.PAID and final.settled_at is not None

    history = await client.get(
        f"/api/v1/businesses/{business_id}/debts/{debt.id}/payments?page=1&page_size=2",
        headers=auth(tokens["access_token"]),
    )
    assert history.status_code == 200
    assert history.json()["total"] == 3 and len(history.json()["items"]) == 2
    assert set(payment_ids) == {
        str(item.id)
        for item in db.scalars(
            select(DebtPayment).where(DebtPayment.debt_id == debt.id)
        ).all()
    }
    customer_detail = await client.get(
        f"/api/v1/businesses/{business_id}/customers/{customer.id}",
        headers=auth(tokens["access_token"]),
    )
    assert customer_detail.json()["total_outstanding"] == "0.00"
    debt_detail = await client.get(
        f"/api/v1/businesses/{business_id}/debts/{debt.id}",
        headers=auth(tokens["access_token"]),
    )
    assert debt_detail.status_code == 200 and debt_detail.json()["status"] == "PAID"
    assert (
        await client.get(
            f"/api/v1/businesses/{business_id}/debts/{debt.id}/reminder",
            headers=auth(tokens["access_token"]),
        )
    ).status_code == 409


async def test_repayment_idempotency_conflicts_overpayment_and_terminal_states(
    client: httpx.AsyncClient,
    db: Session,
) -> None:
    tokens, business_id, owner, _ = await create_business(client, db, "repay-rules@example.com")
    customer_data = (
        await post_customer(client, tokens["access_token"], business_id, name="Rules Customer")
    ).json()
    customer = db.get(Customer, UUID(customer_data["id"]))
    assert customer is not None
    debt = seed_debt(db, business_id=business_id, customer=customer, creator=owner, amount="100.00")
    other_debt = seed_debt(db, business_id=business_id, customer=customer, creator=owner, amount="10.00")
    operation = str(uuid4())
    payload = payment_payload("70.00", operation_id=operation, method="AIRTEL_MONEY", reference="TXN123")
    first = await post_payment(client, tokens["access_token"], business_id, debt.id, payload)
    retry = await post_payment(client, tokens["access_token"], business_id, debt.id, payload)
    assert first.status_code == retry.status_code == 201
    assert first.json()["payment"]["id"] == retry.json()["payment"]["id"]
    assert retry.json()["debt"]["outstanding_amount"] == "30.00"
    assert db.scalar(select(func.count()).select_from(DebtPayment).where(DebtPayment.debt_id == debt.id)) == 1

    changed_values = [
        (debt.id, payment_payload("69.99", operation_id=operation, method="AIRTEL_MONEY", reference="TXN123")),
        (debt.id, payment_payload("70.00", operation_id=operation, method="CASH", reference="TXN123")),
        (debt.id, payment_payload("70.00", operation_id=operation, method="AIRTEL_MONEY", reference="DIFFERENT")),
        (other_debt.id, payload),
    ]
    for target, changed in changed_values:
        response = await post_payment(client, tokens["access_token"], business_id, target, changed)
        assert response.status_code == 409, response.text

    overpay = await post_payment(
        client,
        tokens["access_token"],
        business_id,
        debt.id,
        payment_payload("30.01"),
    )
    assert overpay.status_code == 409 and "30.00" in overpay.json()["detail"]
    for invalid_payload in [
        payment_payload("0.00"),
        payment_payload("1.001"),
        payment_payload("10000000000.00"),
        payment_payload("1.00", method="CUSTOMER_DEBT"),
    ]:
        invalid = await post_payment(
            client, tokens["access_token"], business_id, debt.id, invalid_payload
        )
        assert invalid.status_code == 422, invalid.text
    float_amount = payment_payload("1.00")
    float_amount["amount"] = 1.0
    assert (
        await post_payment(client, tokens["access_token"], business_id, debt.id, float_amount)
    ).status_code == 422

    paid = seed_debt(
        db,
        business_id=business_id,
        customer=customer,
        creator=owner,
        amount="5.00",
        amount_paid="5.00",
        status=DebtStatus.PAID,
    )
    voided = seed_debt(
        db,
        business_id=business_id,
        customer=customer,
        creator=owner,
        amount="5.00",
        status=DebtStatus.VOIDED,
    )
    assert (
        await post_payment(
            client, tokens["access_token"], business_id, paid.id, payment_payload("1.00")
        )
    ).status_code == 409
    assert (
        await post_payment(
            client, tokens["access_token"], business_id, voided.id, payment_payload("1.00")
        )
    ).status_code == 409


@pytest.mark.parametrize(
    ("role", "email"),
    [
        (MembershipRole.OWNER, "payment-owner-role@example.com"),
        (MembershipRole.MANAGER, "payment-manager-role@example.com"),
        (MembershipRole.CASHIER, "payment-cashier-role@example.com"),
    ],
)
async def test_repayment_roles_and_cashier_note_privacy(
    client: httpx.AsyncClient,
    db: Session,
    role: MembershipRole,
    email: str,
) -> None:
    owner_tokens, business_id, owner, _ = await create_business(
        client, db, f"business-{email}"
    )
    token = owner_tokens["access_token"]
    if role != MembershipRole.OWNER:
        member_tokens, _ = await add_member(
            client, db, business_id, role=role, email=email
        )
        token = member_tokens["access_token"]
    customer_data = (
        await post_customer(
            client, owner_tokens["access_token"], business_id, name=f"{role.value} Customer"
        )
    ).json()
    customer = db.get(Customer, UUID(customer_data["id"]))
    assert customer is not None
    debt = seed_debt(db, business_id=business_id, customer=customer, creator=owner, amount="10.00")
    response = await post_payment(
        client,
        token,
        business_id,
        debt.id,
        payment_payload("1.00", notes=None if role == MembershipRole.CASHIER else "Internal collection note"),
    )
    assert response.status_code == 201, response.text
    if role == MembershipRole.CASHIER:
        forbidden_note = await post_payment(
            client,
            token,
            business_id,
            debt.id,
            payment_payload("1.00", notes="Cashier should not set this"),
        )
        assert forbidden_note.status_code == 403
        # A management-authored note is hidden from the cashier in history.
        payment = db.get(DebtPayment, UUID(response.json()["payment"]["id"]))
        assert payment is not None
        payment.notes = "Hidden history note"
        db.commit()
        history = await client.get(
            f"/api/v1/businesses/{business_id}/debts/{debt.id}/payments",
            headers=auth(token),
        )
        assert history.json()["items"][0]["notes"] is None


async def test_repayment_subscription_states_tenant_safety_and_business_scoped_operation(
    client: httpx.AsyncClient,
    db: Session,
) -> None:
    first_tokens, first_bid, first_owner, first_subscription = await create_business(
        client, db, "repay-tenant-first@example.com"
    )
    second_tokens, second_bid, second_owner, _ = await create_business(
        client, db, "repay-tenant-second@example.com"
    )
    first_customer_data = (
        await post_customer(client, first_tokens["access_token"], first_bid, name="First Customer")
    ).json()
    second_customer_data = (
        await post_customer(client, second_tokens["access_token"], second_bid, name="Second Customer")
    ).json()
    first_customer = db.get(Customer, UUID(first_customer_data["id"]))
    second_customer = db.get(Customer, UUID(second_customer_data["id"]))
    assert first_customer is not None and second_customer is not None
    first_debt = seed_debt(db, business_id=first_bid, customer=first_customer, creator=first_owner, amount="20.00")
    second_debt = seed_debt(db, business_id=second_bid, customer=second_customer, creator=second_owner, amount="20.00")

    for suffix in ["", "/payments", "/reminder"]:
        foreign = await client.get(
            f"/api/v1/businesses/{second_bid}/debts/{first_debt.id}{suffix}",
            headers=auth(second_tokens["access_token"]),
        )
        assert foreign.status_code == 404, (suffix, foreign.text)
    foreign_payment = await post_payment(
        client,
        second_tokens["access_token"],
        second_bid,
        first_debt.id,
        payment_payload("1.00"),
    )
    assert foreign_payment.status_code == 404

    shared_operation = str(uuid4())
    first_payment = await post_payment(
        client,
        first_tokens["access_token"],
        first_bid,
        first_debt.id,
        payment_payload("1.00", operation_id=shared_operation),
    )
    second_payment = await post_payment(
        client,
        second_tokens["access_token"],
        second_bid,
        second_debt.id,
        payment_payload("1.00", operation_id=shared_operation),
    )
    assert first_payment.status_code == second_payment.status_code == 201

    now = utc_now()
    first_subscription.current_period_start = now - timedelta(days=31)
    first_subscription.current_period_end = now - timedelta(days=1)
    first_subscription.grace_ends_at = now + timedelta(days=2)
    db.commit()
    grace = await post_payment(
        client,
        first_tokens["access_token"],
        first_bid,
        first_debt.id,
        payment_payload("1.00"),
    )
    assert grace.status_code == 201
    first_subscription.current_period_start = now - timedelta(days=40)
    first_subscription.current_period_end = now - timedelta(days=8)
    first_subscription.grace_ends_at = now - timedelta(days=1)
    db.commit()
    expired = await post_payment(
        client,
        first_tokens["access_token"],
        first_bid,
        first_debt.id,
        payment_payload("1.00"),
    )
    assert expired.status_code == 402
    assert (
        await client.get(
            f"/api/v1/businesses/{first_bid}/debts/{first_debt.id}",
            headers=auth(first_tokens["access_token"]),
        )
    ).status_code == 200
    assert (
        await client.get(
            f"/api/v1/businesses/{first_bid}/debts/{first_debt.id}/payments",
            headers=auth(first_tokens["access_token"]),
        )
    ).status_code == 200
    assert (
        await client.get(
            f"/api/v1/businesses/{first_bid}/debts/{first_debt.id}/reminder",
            headers=auth(first_tokens["access_token"]),
        )
    ).status_code == 200


async def test_repayment_transaction_rolls_back_if_commit_fails(
    client: httpx.AsyncClient,
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    tokens, business_id, owner, _ = await create_business(client, db, "repay-rollback@example.com")
    customer_data = (
        await post_customer(client, tokens["access_token"], business_id, name="Rollback Customer")
    ).json()
    customer = db.get(Customer, UUID(customer_data["id"]))
    assert customer is not None
    debt = seed_debt(db, business_id=business_id, customer=customer, creator=owner, amount="25.00")
    request = DebtPaymentCreateRequest.model_validate(payment_payload("10.00"))

    def fail_commit() -> None:
        raise RuntimeError("simulated commit failure")

    with monkeypatch.context() as patcher:
        patcher.setattr(db, "commit", fail_commit)
        with pytest.raises(RuntimeError, match="simulated commit failure"):
            DebtService(db).record_payment(UUID(business_id), debt.id, request, owner)
    db.expire_all()
    unchanged = db.get(Debt, debt.id)
    assert unchanged is not None
    assert unchanged.amount_paid == Decimal("0.00")
    assert unchanged.outstanding_amount == Decimal("25.00")
    assert unchanged.status == DebtStatus.OPEN
    assert db.scalar(select(func.count()).select_from(DebtPayment)) == 0
