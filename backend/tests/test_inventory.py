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
from app.models.enums import BillingPeriod, InventoryMovementType, MembershipRole, SubscriptionStatus
from app.models.inventory_movement import InventoryMovement
from app.models.product import Product
from app.models.subscription import Subscription
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User

pytestmark = pytest.mark.anyio
PASSWORD = "Strong-enough-password-42"


def auth(token: str) -> dict[str, str]: return {"Authorization": f"Bearer {token}"}


async def register(client: httpx.AsyncClient, email: str) -> dict[str, Any]:
    result = await client.post("/api/v1/auth/register", json={"full_name": email.split("@")[0], "email": email, "password": PASSWORD})
    assert result.status_code == 201
    return result.json()


async def active_business(client: httpx.AsyncClient, db: Session, email: str = "inventory-owner@example.com") -> tuple[dict[str, Any], str]:
    tokens = await register(client, email)
    result = await client.post("/api/v1/businesses", headers=auth(tokens["access_token"]), json={"name": "Inventory Shop"})
    assert result.status_code == 201
    business_id = result.json()["id"]
    plan = SubscriptionPlan(name="Founder", code=f"F-{business_id[:20]}", currency="ZMW", price=Decimal("79.00"), billing_period=BillingPeriod.MONTHLY, grace_period_days=7)
    db.add(plan); db.flush(); now = utc_now()
    db.add(Subscription(business_id=UUID(business_id), plan_id=plan.id, status=SubscriptionStatus.ACTIVE,
        starts_at=now, current_period_start=now, current_period_end=now+timedelta(days=30), grace_ends_at=now+timedelta(days=37)))
    db.commit()
    return tokens, business_id


async def create_product(client: httpx.AsyncClient, token: str, business_id: str, **changes: Any) -> httpx.Response:
    payload: dict[str, Any] = {"name":"Kapenta","sku":" kp-1 ","cost_price":"5.20","selling_price":"8.75",
        "track_inventory":True,"opening_stock":"10.500","low_stock_threshold":"2.000","client_operation_id":str(uuid4())}
    payload.update(changes)
    return await client.post(f"/api/v1/businesses/{business_id}/products", headers=auth(token), json=payload)


async def test_product_opening_stock_decimal_history_and_service_rules(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await active_business(client, db)
    created = await create_product(client, tokens["access_token"], bid)
    assert created.status_code == 201, created.text
    item = created.json(); assert item["sku"] == "KP-1" and item["stock_quantity"] == "10.500"
    movements = await client.get(f"/api/v1/businesses/{bid}/products/{item['id']}/inventory-movements", headers=auth(tokens["access_token"]))
    assert movements.json()["total"] == 1 and movements.json()["items"][0]["movement_type"] == "OPENING_STOCK"
    service = await create_product(client, tokens["access_token"], bid, name="Delivery", sku="SERV", track_inventory=False, opening_stock="0.000", low_stock_threshold="0.000")
    assert service.status_code == 201
    denied = await client.post(f"/api/v1/businesses/{bid}/products/{service.json()['id']}/stock/add", headers=auth(tokens["access_token"]), json={"quantity":"1.000","client_operation_id":str(uuid4())})
    assert denied.status_code == 409


async def test_stock_operations_are_idempotent_and_never_negative(client: httpx.AsyncClient, db: Session) -> None:
    tokens, bid = await active_business(client, db, "stock-owner@example.com")
    product = (await create_product(client, tokens["access_token"], bid)).json(); op = str(uuid4())
    url=f"/api/v1/businesses/{bid}/products/{product['id']}/stock/add"; body={"quantity":"2.250","unit_cost":"5.00","reason":"Supplier","client_operation_id":op}
    first=await client.post(url,headers=auth(tokens["access_token"]),json=body); retry=await client.post(url,headers=auth(tokens["access_token"]),json=body)
    assert first.status_code == retry.status_code == 200 and first.json()["id"] == retry.json()["id"]
    assert db.scalar(select(Product).where(Product.id==UUID(product["id"]))).stock_quantity == Decimal("12.750")
    lost_url=f"/api/v1/businesses/{bid}/products/{product['id']}/stock/lost"
    lost=await client.post(lost_url,headers=auth(tokens["access_token"]),json={"quantity":"99.000","reason":"Missing","client_operation_id":str(uuid4())})
    assert lost.status_code == 409
    assert db.scalar(select(func.count()).select_from(InventoryMovement).where(InventoryMovement.product_id==UUID(product["id"]))) == 2


async def test_adjust_damage_low_stock_summary_and_lifecycle(client: httpx.AsyncClient, db: Session) -> None:
    tokens,bid=await active_business(client,db,"lifecycle@example.com"); p=(await create_product(client,tokens["access_token"],bid)).json(); base=f"/api/v1/businesses/{bid}/products/{p['id']}"
    adjusted=await client.post(f"{base}/stock/adjust",headers=auth(tokens["access_token"]),json={"target_quantity":"3.000","reason":"Count","client_operation_id":str(uuid4())}); assert adjusted.status_code==200
    damaged=await client.post(f"{base}/stock/damaged",headers=auth(tokens["access_token"]),json={"quantity":"1.500","reason":"Spoiled","client_operation_id":str(uuid4())}); assert damaged.status_code==200
    low=await client.get(f"/api/v1/businesses/{bid}/inventory/low-stock",headers=auth(tokens["access_token"])); assert low.json()["total"]==1
    summary=await client.get(f"/api/v1/businesses/{bid}/inventory/summary",headers=auth(tokens["access_token"])); assert summary.json()=={"total_active_products":1,"low_stock_count":1,"out_of_stock_count":0}
    assert (await client.post(f"{base}/deactivate",headers=auth(tokens["access_token"]),json={})).status_code==200
    assert (await client.post(f"{base}/stock/add",headers=auth(tokens["access_token"]),json={"quantity":"1.000","client_operation_id":str(uuid4())})).status_code==409
    assert (await client.get(f"{base}/inventory-movements",headers=auth(tokens["access_token"]))).json()["total"]==3


async def test_tenant_role_and_commercial_guards(client: httpx.AsyncClient, db: Session) -> None:
    owner,bid=await active_business(client,db,"guard-owner@example.com"); other,other_bid=await active_business(client,db,"other-owner@example.com")
    p=(await create_product(client,owner["access_token"],bid)).json()
    assert (await client.get(f"/api/v1/businesses/{other_bid}/products/{p['id']}",headers=auth(other["access_token"]))).status_code==404
    cashier=await register(client,"cashier@example.com"); user=db.scalar(select(User).where(User.email=="cashier@example.com")); db.add(BusinessMembership(user_id=user.id,business_id=UUID(bid),role=MembershipRole.CASHIER)); db.commit()
    assert (await client.get(f"/api/v1/businesses/{bid}/products",headers=auth(cashier["access_token"]))).status_code==200
    assert (await create_product(client,cashier["access_token"],bid,name="Denied",sku="DENIED")).status_code==403
    subscription=db.scalar(select(Subscription).where(Subscription.business_id==UUID(bid))); subscription.starts_at=utc_now()-timedelta(days=40); subscription.current_period_start=utc_now()-timedelta(days=40); subscription.current_period_end=utc_now()-timedelta(days=8); subscription.grace_ends_at=utc_now()-timedelta(days=1); db.commit()
    assert (await create_product(client,owner["access_token"],bid,name="Expired",sku="EXP")).status_code==402
    assert (await client.get(f"/api/v1/businesses/{bid}/products",headers=auth(owner["access_token"]))).status_code==200


async def test_business_scoped_uniqueness_and_operation_reuse_conflict(client: httpx.AsyncClient, db: Session) -> None:
    tokens,bid=await active_business(client,db,"unique@example.com"); one=(await create_product(client,tokens["access_token"],bid)).json()
    assert (await create_product(client,tokens["access_token"],bid,name="Duplicate",barcode="",client_operation_id=str(uuid4()))).status_code==409
    two=(await create_product(client,tokens["access_token"],bid,name="Second",sku="KP-2",client_operation_id=str(uuid4()))).json(); op=str(uuid4())
    assert (await client.post(f"/api/v1/businesses/{bid}/products/{one['id']}/stock/add",headers=auth(tokens["access_token"]),json={"quantity":"1.000","client_operation_id":op})).status_code==200
    assert (await client.post(f"/api/v1/businesses/{bid}/products/{two['id']}/stock/add",headers=auth(tokens["access_token"]),json={"quantity":"1.000","client_operation_id":op})).status_code==409
