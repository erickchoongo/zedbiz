from datetime import timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID, uuid4

import httpx
import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.business_membership import BusinessMembership
from app.models.debt import Debt
from app.models.enums import (
    BillingPeriod,
    DebtStatus,
    InventoryMovementType,
    MembershipRole,
    SaleStatus,
    SubscriptionStatus,
)
from app.models.inventory_movement import InventoryMovement
from app.models.product import Product
from app.models.sale import Sale
from app.models.subscription import Subscription
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.schemas.sale import SaleCreateRequest
from app.services.sales import SalesService

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


async def active_business(
    client: httpx.AsyncClient, db: Session, email: str
) -> tuple[dict[str, Any], str, Subscription]:
    tokens = await register(client, email)
    response = await client.post(
        "/api/v1/businesses",
        headers=auth(tokens["access_token"]),
        json={"name": "Credit Shop", "phone_number": "+260970000000", "location": "Lusaka"},
    )
    assert response.status_code == 201, response.text
    business_id = response.json()["id"]
    plan = SubscriptionPlan(
        name="Founder",
        code=f"CREDIT-{business_id[:20]}",
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
    return tokens, business_id, subscription


async def create_customer(
    client: httpx.AsyncClient, token: str, business_id: str, name: str = "John Banda"
) -> dict[str, Any]:
    response = await client.post(
        f"/api/v1/businesses/{business_id}/customers",
        headers=auth(token),
        json={"name": name, "phone_number": "097 123 4567", "email": "JOHN@EXAMPLE.COM"},
    )
    assert response.status_code == 201, response.text
    return response.json()


async def create_product(
    client: httpx.AsyncClient,
    token: str,
    business_id: str,
    *,
    tracked: bool = True,
    stock: str = "20.000",
    price: str = "150.00",
) -> dict[str, Any]:
    response = await client.post(
        f"/api/v1/businesses/{business_id}/products",
        headers=auth(token),
        json={
            "name": "Tracked Product" if tracked else "Credit Service",
            "sku": f"CREDIT-{uuid4()}",
            "cost_price": "60.00" if tracked else "20.00",
            "selling_price": price,
            "track_inventory": tracked,
            "opening_stock": stock if tracked else "0.000",
            "low_stock_threshold": "0.000",
            "client_operation_id": str(uuid4()),
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def credit_payload(
    product_id: str,
    customer_id: str | None,
    *,
    operation_id: str | None = None,
    quantity: str = "2.000",
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "client_operation_id": operation_id or str(uuid4()),
        "items": [{"product_id": product_id, "quantity": quantity}],
        "payment_method": "CUSTOMER_DEBT",
        "discount_amount": "0.00",
        "due_date": "2026-09-30",
        "notes": "Credit counter sale",
    }
    if customer_id is not None:
        payload["customer_id"] = customer_id
    return payload


async def test_credit_sale_creates_one_debt_deducts_stock_and_retries_safely(
    client: httpx.AsyncClient, db: Session
) -> None:
    tokens, business_id, _ = await active_business(client, db, "credit-sale@example.com")
    token = tokens["access_token"]
    customer = await create_customer(client, token, business_id)
    tracked = await create_product(client, token, business_id)
    operation = str(uuid4())
    payload = credit_payload(tracked["id"], customer["id"], operation_id=operation)

    first = await client.post(
        f"/api/v1/businesses/{business_id}/sales", headers=auth(token), json=payload
    )
    retry = await client.post(
        f"/api/v1/businesses/{business_id}/sales", headers=auth(token), json=payload
    )
    assert first.status_code == retry.status_code == 201, first.text
    body = first.json()
    assert retry.json()["id"] == body["id"]
    assert body["payment_method"] == "CUSTOMER_DEBT"
    assert body["customer_id"] == customer["id"] and body["customer_name"] == "John Banda"
    assert body["debt_status"] == "OPEN" and body["debt_outstanding_amount"] == "300.00"
    assert body["debt_due_date"] == "2026-09-30"

    debt = db.scalar(select(Debt).where(Debt.sale_id == UUID(body["id"])))
    assert debt is not None
    assert (debt.original_amount, debt.amount_paid, debt.outstanding_amount) == (
        Decimal("300.00"), Decimal("0.00"), Decimal("300.00")
    )
    assert db.get(Product, UUID(tracked["id"])).stock_quantity == Decimal("18.000")
    assert db.scalar(select(func.count()).select_from(Debt)) == 1
    movements = db.scalars(
        select(InventoryMovement).where(
            InventoryMovement.reference_id == UUID(body["id"]),
            InventoryMovement.movement_type == InventoryMovementType.SALE,
        )
    ).all()
    assert len(movements) == 1 and movements[0].quantity_delta == Decimal("-2.000")

    receipt = await client.get(
        f"/api/v1/businesses/{business_id}/sales/{body['id']}/receipt", headers=auth(token)
    )
    assert receipt.status_code == 200
    receipt_body = receipt.json()
    assert receipt_body["payment_method"] == "CUSTOMER_DEBT"
    assert receipt_body["customer_name"] == "John Banda"
    assert receipt_body["due_date"] == "2026-09-30"
    assert "total_cost" not in receipt_body and "notes" not in receipt_body


async def test_service_credit_sale_and_credit_transaction_rollbacks(
    client: httpx.AsyncClient,
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    email = "credit-service-rollback@example.com"
    tokens, business_id, _ = await active_business(client, db, email)
    token = tokens["access_token"]
    customer = await create_customer(client, token, business_id)
    service = await create_product(client, token, business_id, tracked=False, price="25.00")

    service_sale = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json=credit_payload(service["id"], customer["id"], quantity="2.000"),
    )
    assert service_sale.status_code == 201, service_sale.text
    assert service_sale.json()["total_amount"] == "50.00"
    assert service_sale.json()["debt_outstanding_amount"] == "50.00"
    assert db.get(Product, UUID(service["id"])).stock_quantity == Decimal("0.000")
    assert (
        db.scalar(
            select(func.count())
            .select_from(InventoryMovement)
            .where(InventoryMovement.reference_id == UUID(service_sale.json()["id"]))
        )
        == 0
    )

    tracked = await create_product(
        client,
        token,
        business_id,
        stock="1.000",
        price="100.00",
    )
    baseline_sales = db.scalar(select(func.count()).select_from(Sale))
    baseline_debts = db.scalar(select(func.count()).select_from(Debt))
    baseline_movements = db.scalar(select(func.count()).select_from(InventoryMovement))
    actor = db.scalar(select(User).where(User.email == email))
    assert actor is not None
    request = SaleCreateRequest.model_validate(
        credit_payload(tracked["id"], customer["id"], quantity="1.000")
    )

    def fail_commit() -> None:
        raise RuntimeError("simulated credit commit failure")

    with monkeypatch.context() as patcher:
        patcher.setattr(db, "commit", fail_commit)
        with pytest.raises(RuntimeError, match="simulated credit commit failure"):
            SalesService(db).create(UUID(business_id), request, actor)

    db.expire_all()
    assert db.scalar(select(func.count()).select_from(Sale)) == baseline_sales
    assert db.scalar(select(func.count()).select_from(Debt)) == baseline_debts
    assert db.scalar(select(func.count()).select_from(InventoryMovement)) == baseline_movements
    assert db.get(Product, UUID(tracked["id"])).stock_quantity == Decimal("1.000")

    insufficient = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json=credit_payload(tracked["id"], customer["id"], quantity="2.000"),
    )
    assert insufficient.status_code == 409
    assert db.scalar(select(func.count()).select_from(Sale)) == baseline_sales
    assert db.scalar(select(func.count()).select_from(Debt)) == baseline_debts
    assert db.get(Product, UUID(tracked["id"])).stock_quantity == Decimal("1.000")


async def test_credit_sale_validates_customer_tenant_activity_and_rolls_back(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner, business_id, _ = await active_business(client, db, "credit-validation@example.com")
    other, other_business_id, _ = await active_business(client, db, "credit-foreign@example.com")
    token = owner["access_token"]
    product = await create_product(client, token, business_id, stock="1.000")
    customer = await create_customer(client, token, business_id)
    foreign = await create_customer(client, other["access_token"], other_business_id, "Foreign Customer")

    missing = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json=credit_payload(product["id"], None, quantity="1.000"),
    )
    assert missing.status_code == 422
    foreign_result = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json=credit_payload(product["id"], foreign["id"], quantity="1.000"),
    )
    assert foreign_result.status_code == 404

    deactivate = await client.post(
        f"/api/v1/businesses/{business_id}/customers/{customer['id']}/deactivate",
        headers=auth(token),
    )
    assert deactivate.status_code == 200
    inactive = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json=credit_payload(product["id"], customer["id"], quantity="1.000"),
    )
    assert inactive.status_code == 409

    assert db.get(Product, UUID(product["id"])).stock_quantity == Decimal("1.000")
    assert db.scalar(select(func.count()).select_from(Debt).where(Debt.business_id == UUID(business_id))) == 0
    assert db.scalar(select(func.count()).select_from(Sale).where(Sale.business_id == UUID(business_id))) == 0


async def test_unpaid_credit_sale_voids_debt_and_restores_stock_atomically(
    client: httpx.AsyncClient, db: Session
) -> None:
    tokens, business_id, _ = await active_business(client, db, "credit-void@example.com")
    token = tokens["access_token"]
    customer = await create_customer(client, token, business_id)
    product = await create_product(client, token, business_id, stock="4.000", price="100.00")
    sale_response = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json=credit_payload(product["id"], customer["id"], quantity="2.000"),
    )
    assert sale_response.status_code == 201, sale_response.text
    sale = sale_response.json()
    operation_id = str(uuid4())
    void_payload = {"client_operation_id": operation_id, "reason": "Credit order cancelled"}
    first = await client.post(
        f"/api/v1/businesses/{business_id}/sales/{sale['id']}/void",
        headers=auth(token),
        json=void_payload,
    )
    retry = await client.post(
        f"/api/v1/businesses/{business_id}/sales/{sale['id']}/void",
        headers=auth(token),
        json=void_payload,
    )
    assert first.status_code == retry.status_code == 200
    assert first.json()["status"] == "VOIDED" and first.json()["debt_status"] == "VOIDED"
    debt = db.scalar(select(Debt).where(Debt.sale_id == UUID(sale["id"])))
    assert debt.status == DebtStatus.VOIDED and debt.outstanding_amount == Decimal("0.00")
    assert debt.voided_at is not None and debt.voided_by_user_id is not None
    assert db.get(Product, UUID(product["id"])).stock_quantity == Decimal("4.000")
    movement_types = db.scalars(
        select(InventoryMovement.movement_type)
        .where(InventoryMovement.reference_id == UUID(sale["id"]))
        .order_by(InventoryMovement.created_at)
    ).all()
    assert movement_types == [InventoryMovementType.SALE, InventoryMovementType.SALE_VOID]


async def test_repaid_credit_sale_cannot_be_voided_and_cashier_can_create_credit(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner, business_id, _ = await active_business(client, db, "credit-cashier-owner@example.com")
    token = owner["access_token"]
    customer = await create_customer(client, token, business_id)
    product = await create_product(client, token, business_id, stock="5.000", price="100.00")
    cashier_tokens = await register(client, "credit-cashier@example.com")
    cashier = db.scalar(select(User).where(User.email == "credit-cashier@example.com"))
    db.add(
        BusinessMembership(
            user_id=cashier.id, business_id=UUID(business_id), role=MembershipRole.CASHIER
        )
    )
    db.commit()

    created = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(cashier_tokens["access_token"]),
        json=credit_payload(product["id"], customer["id"], quantity="2.000"),
    )
    assert created.status_code == 201, created.text
    assert created.json()["total_cost"] is None
    debt_id = created.json()["debt_id"]
    payment = await client.post(
        f"/api/v1/businesses/{business_id}/debts/{debt_id}/payments",
        headers=auth(cashier_tokens["access_token"]),
        json={
            "client_operation_id": str(uuid4()),
            "amount": "50.00",
            "payment_method": "CASH",
        },
    )
    assert payment.status_code == 201, payment.text

    denied = await client.post(
        f"/api/v1/businesses/{business_id}/sales/{created.json()['id']}/void",
        headers=auth(token),
        json={"client_operation_id": str(uuid4()), "reason": "Cannot erase a repayment"},
    )
    assert denied.status_code == 409
    debt = db.get(Debt, UUID(debt_id))
    assert debt.status == DebtStatus.PARTIALLY_PAID
    assert debt.outstanding_amount == Decimal("150.00")
    assert db.get(Product, UUID(product["id"])).stock_quantity == Decimal("3.000")
    sale = db.get(Sale, UUID(created.json()["id"]))
    assert sale.status == SaleStatus.COMPLETED


async def test_expired_blocks_credit_sale_while_grace_allows_it(
    client: httpx.AsyncClient, db: Session
) -> None:
    tokens, business_id, subscription = await active_business(client, db, "credit-commercial@example.com")
    token = tokens["access_token"]
    customer = await create_customer(client, token, business_id)
    product = await create_product(client, token, business_id, stock="3.000", price="10.00")
    now = utc_now()
    subscription.starts_at = now - timedelta(days=31)
    subscription.current_period_start = now - timedelta(days=31)
    subscription.current_period_end = now - timedelta(days=1)
    subscription.grace_ends_at = now + timedelta(days=1)
    db.commit()
    grace = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json=credit_payload(product["id"], customer["id"], quantity="1.000"),
    )
    assert grace.status_code == 201
    subscription.current_period_end = now - timedelta(days=8)
    subscription.grace_ends_at = now - timedelta(days=1)
    db.commit()
    expired = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json=credit_payload(product["id"], customer["id"], quantity="1.000"),
    )
    assert expired.status_code == 402
    history = await client.get(
        f"/api/v1/businesses/{business_id}/debts/{grace.json()['debt_id']}", headers=auth(token)
    )
    receipt = await client.get(
        f"/api/v1/businesses/{business_id}/sales/{grace.json()['id']}/receipt", headers=auth(token)
    )
    assert history.status_code == receipt.status_code == 200
