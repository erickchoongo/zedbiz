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
from app.models.enums import BillingPeriod, InventoryMovementType, MembershipRole, SaleStatus, SubscriptionStatus
from app.models.inventory_movement import InventoryMovement
from app.models.product import Product
from app.models.sale import Sale
from app.models.sale_item import SaleItem
from app.models.subscription import Subscription
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User

pytestmark = pytest.mark.anyio
PASSWORD = "Strong-enough-password-42"


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register(client: httpx.AsyncClient, email: str) -> dict[str, Any]:
    response = await client.post("/api/v1/auth/register", json={"full_name": email.split("@")[0], "email": email, "password": PASSWORD})
    assert response.status_code == 201, response.text
    return response.json()


async def business(client: httpx.AsyncClient, db: Session, email: str) -> tuple[dict[str, Any], str]:
    tokens = await register(client, email)
    response = await client.post("/api/v1/businesses", headers=auth(tokens["access_token"]), json={"name": "Sales Shop", "phone_number": "+260970000000", "location": "Lusaka"})
    assert response.status_code == 201, response.text
    business_id = response.json()["id"]
    plan = SubscriptionPlan(name="Founder", code=f"SALE-{business_id[:20]}", currency="ZMW", price=Decimal("79.00"), billing_period=BillingPeriod.MONTHLY, grace_period_days=7)
    db.add(plan); db.flush(); now = utc_now()
    db.add(Subscription(business_id=UUID(business_id), plan_id=plan.id, status=SubscriptionStatus.ACTIVE,
        starts_at=now, current_period_start=now, current_period_end=now+timedelta(days=30), grace_ends_at=now+timedelta(days=37)))
    db.commit()
    return tokens, business_id


async def product(client: httpx.AsyncClient, token: str, business_id: str, *, name: str, sku: str,
                  cost: str, price: str, stock: str, tracked: bool = True, threshold: str = "0.000") -> dict[str, Any]:
    response = await client.post(f"/api/v1/businesses/{business_id}/products", headers=auth(token), json={
        "name": name, "sku": sku, "cost_price": cost, "selling_price": price,
        "track_inventory": tracked, "opening_stock": stock if tracked else "0.000",
        "low_stock_threshold": threshold if tracked else "0.000", "client_operation_id": str(uuid4()),
    })
    assert response.status_code == 201, response.text
    return response.json()


def sale_payload(items: list[tuple[str, str]], *, operation: str | None = None,
                 method: str = "CASH", discount: str = "0.00", reference: str | None = None) -> dict[str, Any]:
    return {"client_operation_id": operation or str(uuid4()),
        "items": [{"product_id": item, "quantity": quantity} for item, quantity in items],
        "payment_method": method, "payment_reference": reference, "discount_amount": discount, "notes": "Counter sale"}


async def post_sale(client: httpx.AsyncClient, token: str, business_id: str, payload: dict[str, Any]) -> httpx.Response:
    return await client.post(f"/api/v1/businesses/{business_id}/sales", headers=auth(token), json=payload)


async def test_atomic_sale_snapshots_service_inventory_and_exact_totals(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await business(client, db, "sale-owner@example.com")
    tracked = await product(client, tokens["access_token"], bid, name="USB Charger", sku="USB", cost="60.00", price="120.00", stock="20.000", threshold="18.000")
    service = await product(client, tokens["access_token"], bid, name="Laptop Cleaning", sku="CLEAN", cost="20.00", price="100.00", stock="0", tracked=False)
    response = await post_sale(client, tokens["access_token"], bid, sale_payload([(tracked["id"], "2.000"), (service["id"], "1.000")], method="MTN_MONEY", reference="ABC123", discount="10.00"))
    assert response.status_code == 201, response.text
    sale = response.json()
    assert (sale["subtotal"], sale["discount_amount"], sale["total_amount"], sale["total_cost"], sale["gross_profit"]) == ("340.00", "10.00", "330.00", "140.00", "190.00")
    assert sale["sale_number"].startswith("ZB-") and len(sale["items"]) == 2
    tracked_db = db.get(Product, UUID(tracked["id"])); assert tracked_db.stock_quantity == Decimal("18.000")
    moves = db.scalars(select(InventoryMovement).where(InventoryMovement.reference_id == UUID(sale["id"]), InventoryMovement.movement_type == InventoryMovementType.SALE)).all()
    assert len(moves) == 1 and moves[0].quantity_delta == Decimal("-2.000")
    tracked_db.selling_price = Decimal("150.00"); tracked_db.cost_price = Decimal("80.00"); db.commit()
    detail = await client.get(f"/api/v1/businesses/{bid}/sales/{sale['id']}", headers=auth(tokens["access_token"]))
    sold_item = next(item for item in detail.json()["items"] if item["product_id"] == tracked["id"])
    assert sold_item["unit_selling_price"] == "120.00" and sold_item["unit_cost"] == "60.00"


async def test_fractional_rounding_duplicate_aggregation_and_payment_methods(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await business(client, db, "rounding@example.com")
    item = await product(client, tokens["access_token"], bid, name="Measured Item", sku="MEASURE", cost="0.01", price="79.99", stock="5.000")
    response = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "0.250"), (item["id"], "0.250")], method="BANK_TRANSFER", reference="BANK-1"))
    assert response.status_code == 201, response.text
    body = response.json(); assert len(body["items"]) == 1
    assert body["items"][0]["quantity"] == "0.500" and body["subtotal"] == "40.00" and body["total_cost"] == "0.01"
    assert db.get(Product, UUID(item["id"])).stock_quantity == Decimal("4.500")
    for method in ["CASH", "MTN_MONEY", "AIRTEL_MONEY", "ZAMTEL_MONEY", "OTHER"]:
        result = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "0.100")], method=method))
        assert result.status_code == 201, (method, result.text)
    invalid = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "0.100")], method="CUSTOMER_DEBT"))
    assert invalid.status_code == 422


async def test_sale_idempotency_conflict_and_sale_numbers(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await business(client, db, "idempotent-sale@example.com")
    item = await product(client, tokens["access_token"], bid, name="Item", sku="ITEM", cost="1.00", price="2.00", stock="10.000")
    operation = str(uuid4()); payload = sale_payload([(item["id"], "2.000")], operation=operation)
    first = await post_sale(client, tokens["access_token"], bid, payload); retry = await post_sale(client, tokens["access_token"], bid, payload)
    assert first.status_code == 201 and retry.status_code == 201 and first.json()["id"] == retry.json()["id"]
    assert db.get(Product, UUID(item["id"])).stock_quantity == Decimal("8.000")
    conflict = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "1.000")], operation=operation))
    assert conflict.status_code == 409
    second = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "1.000")]))
    assert second.status_code == 201 and second.json()["sale_number"] != first.json()["sale_number"]
    assert db.scalar(select(func.count()).select_from(Sale).where(Sale.business_id == UUID(bid))) == 2


async def test_invalid_cart_rolls_back_everything_and_tenant_products_are_hidden(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await business(client, db, "rollback-sale@example.com")
    other, other_bid = await business(client, db, "other-sale@example.com")
    good = await product(client, tokens["access_token"], bid, name="Good", sku="GOOD", cost="2.00", price="4.00", stock="5.000")
    low = await product(client, tokens["access_token"], bid, name="Low", sku="LOW", cost="2.00", price="4.00", stock="1.000")
    foreign = await product(client, other["access_token"], other_bid, name="Foreign", sku="FOREIGN", cost="1.00", price="2.00", stock="5.000")
    failed = await post_sale(client, tokens["access_token"], bid, sale_payload([(good["id"], "2.000"), (low["id"], "2.000")]))
    assert failed.status_code == 409 and db.get(Product, UUID(good["id"])).stock_quantity == Decimal("5.000")
    assert db.scalar(select(func.count()).select_from(Sale).where(Sale.business_id == UUID(bid))) == 0
    hidden = await post_sale(client, tokens["access_token"], bid, sale_payload([(foreign["id"], "1.000")]))
    assert hidden.status_code == 404
    db.get(Product, UUID(low["id"])).is_active = False; db.commit()
    inactive = await post_sale(client, tokens["access_token"], bid, sale_payload([(low["id"], "1.000")]))
    assert inactive.status_code == 409


async def test_discount_validation_listing_filters_receipt_and_tenant_sale_denial(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await business(client, db, "list-sale@example.com")
    other, other_bid = await business(client, db, "list-other@example.com")
    item = await product(client, tokens["access_token"], bid, name="Listed", sku="LIST", cost="20.00", price="120.00", stock="10.000")
    too_large = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "1.000")], discount="120.01")); assert too_large.status_code == 409
    created = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "1.000")], method="AIRTEL_MONEY", reference="AIR-1", discount="0.01")); sale = created.json()
    listing = await client.get(f"/api/v1/businesses/{bid}/sales?page=1&page_size=1&payment_method=AIRTEL_MONEY&search={sale['sale_number']}", headers=auth(tokens["access_token"]))
    assert listing.status_code == 200 and listing.json()["total"] == 1 and len(listing.json()["items"]) == 1
    receipt = await client.get(f"/api/v1/businesses/{bid}/sales/{sale['id']}/receipt", headers=auth(tokens["access_token"])); body = receipt.json()
    assert receipt.status_code == 200 and body["title"] == "SALES RECEIPT" and body["business_phone"] == "+260970000000"
    assert "total_cost" not in body and "gross_profit" not in body and "unit_cost" not in body["items"][0]
    assert (await client.get(f"/api/v1/businesses/{other_bid}/sales/{sale['id']}", headers=auth(other["access_token"]))).status_code == 404
    assert (await client.get(f"/api/v1/businesses/{other_bid}/sales/{sale['id']}/receipt", headers=auth(other["access_token"]))).status_code == 404


async def test_cashier_can_sell_but_costs_hidden_and_void_denied(client: httpx.AsyncClient, db: Session) -> None:
    owner, bid = await business(client, db, "role-owner@example.com")
    item = await product(client, owner["access_token"], bid, name="Role Item", sku="ROLE", cost="4.00", price="10.00", stock="10.000")
    cashier = await register(client, "role-cashier@example.com"); user = db.scalar(select(User).where(User.email == "role-cashier@example.com"))
    db.add(BusinessMembership(user_id=user.id, business_id=UUID(bid), role=MembershipRole.CASHIER)); db.commit()
    response = await post_sale(client, cashier["access_token"], bid, sale_payload([(item["id"], "1.000")]))
    assert response.status_code == 201 and response.json()["total_cost"] is None and response.json()["items"][0]["unit_cost"] is None
    voided = await client.post(f"/api/v1/businesses/{bid}/sales/{response.json()['id']}/void", headers=auth(cashier["access_token"]), json={"client_operation_id": str(uuid4()), "reason": "Not allowed"})
    assert voided.status_code == 403


@pytest.mark.parametrize("role", [MembershipRole.OWNER, MembershipRole.MANAGER])
async def test_owner_and_manager_void_restore_stock_once_with_compensating_movement(client: httpx.AsyncClient, db: Session, role: MembershipRole) -> None:
    owner, bid = await business(client, db, f"void-{role.value.lower()}@example.com")
    token = owner["access_token"]
    if role == MembershipRole.MANAGER:
        manager = await register(client, "void-manager-member@example.com"); user = db.scalar(select(User).where(User.email == "void-manager-member@example.com"))
        db.add(BusinessMembership(user_id=user.id, business_id=UUID(bid), role=MembershipRole.MANAGER)); db.commit(); token = manager["access_token"]
    item = await product(client, owner["access_token"], bid, name="Void Item", sku="VOID", cost="5.00", price="9.00", stock="6.000")
    sale = (await post_sale(client, token, bid, sale_payload([(item["id"], "2.000")]))).json(); operation = str(uuid4())
    payload = {"client_operation_id": operation, "reason": "Customer transaction cancelled"}
    first = await client.post(f"/api/v1/businesses/{bid}/sales/{sale['id']}/void", headers=auth(token), json=payload)
    retry = await client.post(f"/api/v1/businesses/{bid}/sales/{sale['id']}/void", headers=auth(token), json=payload)
    assert first.status_code == retry.status_code == 200 and first.json()["status"] == "VOIDED"
    assert db.get(Product, UUID(item["id"])).stock_quantity == Decimal("6.000")
    movements = db.scalars(select(InventoryMovement).where(InventoryMovement.reference_id == UUID(sale["id"]))).all()
    assert [movement.movement_type for movement in movements] == [InventoryMovementType.SALE, InventoryMovementType.SALE_VOID]
    duplicate = await client.post(f"/api/v1/businesses/{bid}/sales/{sale['id']}/void", headers=auth(token), json={"client_operation_id": str(uuid4()), "reason": "Again"})
    assert duplicate.status_code == 409


async def test_subscription_states_allow_grace_deny_expired_but_keep_history_and_receipt(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await business(client, db, "commercial-sale@example.com")
    item = await product(client, tokens["access_token"], bid, name="Commercial", sku="COMM", cost="1.00", price="3.00", stock="5.000")
    subscription = db.scalar(select(Subscription).where(Subscription.business_id == UUID(bid))); now = utc_now()
    subscription.starts_at = now - timedelta(days=31); subscription.current_period_start = now - timedelta(days=31); subscription.current_period_end = now - timedelta(days=1); subscription.grace_ends_at = now + timedelta(days=2); db.commit()
    grace = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "1.000")]))
    assert grace.status_code == 201
    subscription.starts_at = now - timedelta(days=40); subscription.current_period_start = now - timedelta(days=40); subscription.current_period_end = now - timedelta(days=8); subscription.grace_ends_at = now - timedelta(days=1); db.commit()
    denied = await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "1.000")]))
    assert denied.status_code == 402
    assert (await client.get(f"/api/v1/businesses/{bid}/sales/{grace.json()['id']}", headers=auth(tokens["access_token"]))).status_code == 200
    assert (await client.get(f"/api/v1/businesses/{bid}/sales/{grace.json()['id']}/receipt", headers=auth(tokens["access_token"]))).status_code == 200


async def test_sale_immediately_updates_low_stock(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await business(client, db, "low-stock-sale@example.com")
    item = await product(client, tokens["access_token"], bid, name="Threshold", sku="THRESH", cost="1.00", price="2.00", stock="6.000", threshold="5.000")
    assert (await client.get(f"/api/v1/businesses/{bid}/inventory/low-stock", headers=auth(tokens["access_token"]))).json()["total"] == 0
    assert (await post_sale(client, tokens["access_token"], bid, sale_payload([(item["id"], "2.000")]))).status_code == 201
    low = await client.get(f"/api/v1/businesses/{bid}/inventory/low-stock", headers=auth(tokens["access_token"]))
    assert low.json()["total"] == 1 and low.json()["items"][0]["stock_quantity"] == "4.000"
