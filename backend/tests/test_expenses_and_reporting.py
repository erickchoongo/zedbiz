from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.audit_log import AuditLog
from app.models.business_membership import BusinessMembership
from app.models.enums import BillingPeriod, MembershipRole, SubscriptionStatus
from app.models.expense import Expense
from app.models.product import Product
from app.models.subscription import Subscription
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.schemas.reporting import ReportRange
from app.services.debts import lusaka_today
from app.services.reporting import resolve_period

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
        json={"name": "Milestone Seven Shop", "phone_number": "+260970000000", "location": "Lusaka"},
    )
    assert response.status_code == 201, response.text
    business_id = response.json()["id"]
    plan = SubscriptionPlan(
        name="Founder",
        code=f"M7-{business_id[:20]}",
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


async def add_member(
    client: httpx.AsyncClient,
    db: Session,
    business_id: str,
    email: str,
    role: MembershipRole,
) -> dict[str, Any]:
    tokens = await register(client, email)
    user = db.scalar(select(User).where(User.email == email))
    assert user is not None
    db.add(BusinessMembership(user_id=user.id, business_id=UUID(business_id), role=role))
    db.commit()
    return tokens


async def create_product(
    client: httpx.AsyncClient,
    token: str,
    business_id: str,
    *,
    name: str = "Report Item",
    cost: str = "200.00",
    price: str = "500.00",
    stock: str = "5.000",
    threshold: str = "2.000",
) -> dict[str, Any]:
    response = await client.post(
        f"/api/v1/businesses/{business_id}/products",
        headers=auth(token),
        json={
            "name": name,
            "sku": str(uuid4()),
            "cost_price": cost,
            "selling_price": price,
            "track_inventory": True,
            "opening_stock": stock,
            "low_stock_threshold": threshold,
            "client_operation_id": str(uuid4()),
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


async def post_expense(
    client: httpx.AsyncClient,
    token: str,
    business_id: str,
    *,
    operation: str | None = None,
    amount: object = "75.50",
    description: str = "Shop electricity",
    notes: str | None = None,
) -> httpx.Response:
    return await client.post(
        f"/api/v1/businesses/{business_id}/expenses",
        headers=auth(token),
        json={
            "client_operation_id": operation or str(uuid4()),
            "category": "UTILITIES",
            "description": description,
            "amount": amount,
            "payment_method": "MTN_MONEY",
            "payment_reference": "EXP-REF",
            "expense_date": lusaka_today().isoformat(),
            "notes": notes,
        },
    )


async def test_expense_exactness_idempotency_roles_tenant_and_void_audit(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner, business_id, _ = await active_business(client, db, "m7-expense-owner@example.com")
    other, other_id, _ = await active_business(client, db, "m7-expense-other@example.com")
    cashier = await add_member(
        client, db, business_id, "m7-expense-cashier@example.com", MembershipRole.CASHIER
    )
    manager = await add_member(
        client, db, business_id, "m7-expense-manager@example.com", MembershipRole.MANAGER
    )
    owner_token = owner["access_token"]

    assert (await post_expense(client, owner_token, business_id, amount=75.5)).status_code == 422
    debt_method = await client.post(
        f"/api/v1/businesses/{business_id}/expenses",
        headers=auth(owner_token),
        json={
            "client_operation_id": str(uuid4()), "category": "RENT", "description": "Rent",
            "amount": "100.00", "payment_method": "CUSTOMER_DEBT",
            "expense_date": lusaka_today().isoformat(),
        },
    )
    assert debt_method.status_code == 422

    operation = str(uuid4())
    first = await post_expense(client, owner_token, business_id, operation=operation)
    retry = await post_expense(client, owner_token, business_id, operation=operation)
    assert first.status_code == retry.status_code == 201
    assert first.json()["id"] == retry.json()["id"]
    assert first.json()["amount"] == "75.50" and first.json()["status"] == "RECORDED"
    conflict = await post_expense(
        client, owner_token, business_id, operation=operation, description="Different expense"
    )
    assert conflict.status_code == 409

    cashier_notes = await post_expense(
        client, cashier["access_token"], business_id, description="Till expense", notes="Private"
    )
    assert cashier_notes.status_code == 403
    cashier_expense = await post_expense(
        client, cashier["access_token"], business_id, description="Till expense"
    )
    assert cashier_expense.status_code == 201
    own_list = await client.get(
        f"/api/v1/businesses/{business_id}/expenses", headers=auth(cashier["access_token"])
    )
    assert own_list.status_code == 200 and own_list.json()["total"] == 1
    assert own_list.json()["items"][0]["id"] == cashier_expense.json()["id"]
    hidden = await client.get(
        f"/api/v1/businesses/{business_id}/expenses/{first.json()['id']}",
        headers=auth(cashier["access_token"]),
    )
    assert hidden.status_code == 404
    foreign = await client.get(
        f"/api/v1/businesses/{other_id}/expenses/{first.json()['id']}",
        headers=auth(other["access_token"]),
    )
    assert foreign.status_code == 404

    denied = await client.post(
        f"/api/v1/businesses/{business_id}/expenses/{first.json()['id']}/void",
        headers=auth(cashier["access_token"]),
        json={"client_operation_id": str(uuid4()), "reason": "Not allowed"},
    )
    assert denied.status_code == 403
    void_operation = str(uuid4())
    void_payload = {"client_operation_id": void_operation, "reason": "Duplicate supplier invoice"}
    voided = await client.post(
        f"/api/v1/businesses/{business_id}/expenses/{first.json()['id']}/void",
        headers=auth(manager["access_token"]),
        json=void_payload,
    )
    void_retry = await client.post(
        f"/api/v1/businesses/{business_id}/expenses/{first.json()['id']}/void",
        headers=auth(manager["access_token"]),
        json=void_payload,
    )
    assert voided.status_code == void_retry.status_code == 200
    assert voided.json()["status"] == "VOIDED" and void_retry.json()["id"] == first.json()["id"]
    assert db.scalar(select(func.count()).select_from(Expense)) == 2
    assert db.scalar(
        select(func.count()).select_from(AuditLog).where(AuditLog.action == "expense.voided")
    ) == 1


async def test_dashboard_reports_snapshot_revenue_debt_and_void_semantics(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner, business_id, _ = await active_business(client, db, "m7-report-owner@example.com")
    token = owner["access_token"]
    product = await create_product(client, token, business_id)
    empty = await create_product(
        client, token, business_id, name="Empty Item", cost="1.00", price="2.00", stock="0.000", threshold="0.000"
    )
    assert empty["stock_quantity"] == "0.000"

    customer = await client.post(
        f"/api/v1/businesses/{business_id}/customers",
        headers=auth(token),
        json={"name": "Credit Customer", "phone_number": "0971234567"},
    )
    assert customer.status_code == 201, customer.text
    cash_sale = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json={
            "client_operation_id": str(uuid4()),
            "items": [{"product_id": product["id"], "quantity": "2.000"}],
            "payment_method": "CASH", "discount_amount": "0.00",
        },
    )
    credit_sale = await client.post(
        f"/api/v1/businesses/{business_id}/sales",
        headers=auth(token),
        json={
            "client_operation_id": str(uuid4()),
            "items": [{"product_id": product["id"], "quantity": "1.000"}],
            "payment_method": "CUSTOMER_DEBT", "discount_amount": "0.00",
            "customer_id": customer.json()["id"],
            "due_date": (lusaka_today() - timedelta(days=1)).isoformat(),
        },
    )
    assert cash_sale.status_code == credit_sale.status_code == 201
    payment = await client.post(
        f"/api/v1/businesses/{business_id}/debts/{credit_sale.json()['debt_id']}/payments",
        headers=auth(token),
        json={
            "client_operation_id": str(uuid4()), "amount": "200.00", "payment_method": "CASH"
        },
    )
    assert payment.status_code == 201, payment.text
    expense = await post_expense(client, token, business_id, amount="300.00", description="Power bill")
    assert expense.status_code == 201

    # Historical profit must remain based on the sale snapshot.
    stored_product = db.get(Product, UUID(product["id"]))
    stored_product.cost_price = Decimal("499.00")
    stored_product.selling_price = Decimal("900.00")
    stored_product.name = "Renamed Report Item"
    db.commit()

    dashboard = await client.get(
        f"/api/v1/businesses/{business_id}/dashboard?range=today", headers=auth(token)
    )
    assert dashboard.status_code == 200, dashboard.text
    body = dashboard.json()
    assert (body["gross_sales"], body["sales_count"], body["gross_profit"]) == ("1500.00", 2, "900.00")
    assert (body["total_expenses"], body["net_operating_result"]) == ("300.00", "600.00")
    assert body["outstanding_customer_debt"] == "300.00"
    assert body["overdue_customer_debt"] == "300.00"
    assert body["low_stock_count"] == 2 and body["out_of_stock_count"] == 1
    assert len(body["recent_sales"]) == 2 and len(body["recent_expenses"]) == 1

    sales_report = await client.get(
        f"/api/v1/businesses/{business_id}/reports/sales?range=today", headers=auth(token)
    )
    assert sales_report.status_code == 200
    sales_body = sales_report.json()
    assert sales_body["average_sale_value"] == "750.00" and sales_body["gross_profit"] == "900.00"
    assert {item["payment_method"] for item in sales_body["payment_breakdown"]} == {"CASH", "CUSTOMER_DEBT"}
    assert sales_body["top_products"][0]["quantity"] == "3.000"
    assert sales_body["top_products"][0]["product_name"] == "Renamed Report Item"
    expenses_report = await client.get(
        f"/api/v1/businesses/{business_id}/reports/expenses?range=today", headers=auth(token)
    )
    assert expenses_report.status_code == 200
    assert expenses_report.json()["total_expenses"] == "300.00"
    performance = await client.get(
        f"/api/v1/businesses/{business_id}/reports/performance?range=today", headers=auth(token)
    )
    assert performance.status_code == 200
    assert performance.json()["net_operating_result"] == "600.00"
    assert performance.json()["gross_margin_percentage"] == "60.00"

    assert (
        await client.post(
            f"/api/v1/businesses/{business_id}/sales/{cash_sale.json()['id']}/void",
            headers=auth(token),
            json={"client_operation_id": str(uuid4()), "reason": "Till correction"},
        )
    ).status_code == 200
    assert (
        await client.post(
            f"/api/v1/businesses/{business_id}/expenses/{expense.json()['id']}/void",
            headers=auth(token),
            json={"client_operation_id": str(uuid4()), "reason": "Wrong invoice"},
        )
    ).status_code == 200
    after_void = (
        await client.get(f"/api/v1/businesses/{business_id}/dashboard?range=today", headers=auth(token))
    ).json()
    assert (after_void["gross_sales"], after_void["gross_profit"], after_void["total_expenses"]) == (
        "500.00", "300.00", "0.00"
    )


async def test_cashier_report_shaping_expired_read_only_and_tenant_isolation(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner, business_id, subscription = await active_business(client, db, "m7-policy-owner@example.com")
    cashier = await add_member(client, db, business_id, "m7-policy-cashier@example.com", MembershipRole.CASHIER)
    other, other_id, _ = await active_business(client, db, "m7-policy-other@example.com")
    assert (await post_expense(client, owner["access_token"], business_id, amount="22.00")).status_code == 201
    assert (await post_expense(client, other["access_token"], other_id, amount="999.00")).status_code == 201

    dashboard = await client.get(
        f"/api/v1/businesses/{business_id}/dashboard", headers=auth(cashier["access_token"])
    )
    assert dashboard.status_code == 200
    body = dashboard.json()
    for field in (
        "gross_profit", "total_expenses", "net_operating_result", "outstanding_customer_debt", "overdue_customer_debt", "recent_expenses"
    ):
        assert body[field] is None
    cashier_sales = await client.get(
        f"/api/v1/businesses/{business_id}/reports/sales", headers=auth(cashier["access_token"])
    )
    assert cashier_sales.status_code == 200 and cashier_sales.json()["gross_profit"] is None
    assert (
        await client.get(
            f"/api/v1/businesses/{business_id}/reports/expenses", headers=auth(cashier["access_token"])
        )
    ).status_code == 403
    assert (
        await client.get(
            f"/api/v1/businesses/{business_id}/reports/performance", headers=auth(cashier["access_token"])
        )
    ).status_code == 403

    owner_dashboard = (
        await client.get(f"/api/v1/businesses/{business_id}/dashboard", headers=auth(owner["access_token"]))
    ).json()
    assert owner_dashboard["total_expenses"] == "22.00"
    assert (
        await client.get(f"/api/v1/businesses/{other_id}/dashboard", headers=auth(owner["access_token"]))
    ).status_code == 404

    now = utc_now()
    subscription.starts_at = now - timedelta(days=60)
    subscription.current_period_start = now - timedelta(days=60)
    subscription.current_period_end = now - timedelta(days=10)
    subscription.grace_ends_at = now - timedelta(days=3)
    db.commit()
    assert (
        await client.get(f"/api/v1/businesses/{business_id}/dashboard", headers=auth(owner["access_token"]))
    ).status_code == 200
    assert (
        await client.get(f"/api/v1/businesses/{business_id}/reports/performance", headers=auth(owner["access_token"]))
    ).status_code == 200
    assert (
        await client.get(f"/api/v1/businesses/{business_id}/expenses", headers=auth(owner["access_token"]))
    ).status_code == 200
    assert (await post_expense(client, owner["access_token"], business_id)).status_code == 402


async def test_lusaka_period_boundaries_and_custom_validation() -> None:
    now = datetime(2026, 9, 3, 22, 30, tzinfo=UTC)
    today = resolve_period(ReportRange.TODAY, None, None, now=now)
    assert today.date_from.isoformat() == "2026-09-04"
    assert today.start_utc == datetime(2026, 9, 3, 22, 0, tzinfo=UTC)
    assert today.end_utc == datetime(2026, 9, 4, 22, 0, tzinfo=UTC)
    week = resolve_period(ReportRange.WEEK, None, None, now=now)
    assert week.date_from.isoformat() == "2026-08-31" and week.date_to.isoformat() == "2026-09-04"
    custom = resolve_period(None, today.date_from, today.date_to, now=now)
    assert custom.name == "custom"
    with pytest.raises(HTTPException):
        resolve_period(None, today.date_from, None, now=now)


async def test_every_expense_category_method_filters_and_grace_access(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner, business_id, subscription = await active_business(
        client, db, "m7-expense-values@example.com"
    )
    token = owner["access_token"]
    categories = [
        "STOCK_PURCHASE", "RENT", "UTILITIES", "TRANSPORT", "SALARIES_WAGES",
        "AIRTIME_DATA", "MARKETING", "MAINTENANCE", "EQUIPMENT", "FEES_CHARGES", "OTHER",
    ]
    methods = ["CASH", "MTN_MONEY", "AIRTEL_MONEY", "ZAMTEL_MONEY", "BANK_TRANSFER", "OTHER"]
    today = lusaka_today().isoformat()
    for index, category in enumerate(categories):
        response = await client.post(
            f"/api/v1/businesses/{business_id}/expenses",
            headers=auth(token),
            json={
                "client_operation_id": str(uuid4()),
                "category": category,
                "description": f"{category} launch record",
                "amount": f"{index + 1}.25",
                "payment_method": methods[index % len(methods)],
                "expense_date": today,
            },
        )
        assert response.status_code == 201, (category, response.text)

    all_items = await client.get(
        f"/api/v1/businesses/{business_id}/expenses?page_size=100", headers=auth(token)
    )
    assert all_items.status_code == 200 and all_items.json()["total"] == len(categories)
    rent = await client.get(
        f"/api/v1/businesses/{business_id}/expenses?category=RENT&search=RENT&date_from={today}&date_to={today}",
        headers=auth(token),
    )
    assert rent.status_code == 200 and rent.json()["total"] == 1
    cash = await client.get(
        f"/api/v1/businesses/{business_id}/expenses?payment_method=CASH&status=RECORDED",
        headers=auth(token),
    )
    assert cash.status_code == 200 and cash.json()["total"] == 2

    base = {
        "client_operation_id": str(uuid4()), "category": "OTHER", "description": "Invalid",
        "payment_method": "CASH", "expense_date": today,
    }
    for amount in ("0.00", "-1.00", "1.001"):
        assert (
            await client.post(
                f"/api/v1/businesses/{business_id}/expenses",
                headers=auth(token),
                json={**base, "client_operation_id": str(uuid4()), "amount": amount},
            )
        ).status_code == 422
    invalid_category = await client.post(
        f"/api/v1/businesses/{business_id}/expenses",
        headers=auth(token),
        json={**base, "client_operation_id": str(uuid4()), "category": "TAX_BRIBE", "amount": "1.00"},
    )
    assert invalid_category.status_code == 422

    now = utc_now()
    subscription.starts_at = now - timedelta(days=31)
    subscription.current_period_start = now - timedelta(days=31)
    subscription.current_period_end = now - timedelta(days=1)
    subscription.grace_ends_at = now + timedelta(days=2)
    db.commit()
    assert (await post_expense(client, token, business_id, amount="10.00")).status_code == 201


async def test_no_data_dashboard_reports_and_zero_margin(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner, business_id, _ = await active_business(client, db, "m7-empty@example.com")
    token = owner["access_token"]
    dashboard = (
        await client.get(f"/api/v1/businesses/{business_id}/dashboard", headers=auth(token))
    ).json()
    assert dashboard["gross_sales"] == dashboard["gross_profit"] == dashboard["total_expenses"] == "0.00"
    assert dashboard["sales_count"] == 0
    assert dashboard["recent_sales"] == dashboard["recent_expenses"] == []
    sales = (
        await client.get(f"/api/v1/businesses/{business_id}/reports/sales", headers=auth(token))
    ).json()
    assert sales["average_sale_value"] == "0.00"
    assert sales["payment_breakdown"] == sales["sales_by_day"] == sales["top_products"] == []
    performance = (
        await client.get(
            f"/api/v1/businesses/{business_id}/reports/performance", headers=auth(token)
        )
    ).json()
    assert performance["gross_margin_percentage"] == "0.00"
    assert performance["net_operating_result"] == "0.00"


async def test_sales_report_uses_lusaka_day_across_utc_year_boundary(
    client: httpx.AsyncClient, db: Session
) -> None:
    owner, business_id, _ = await active_business(client, db, "m7-timezone@example.com")
    token = owner["access_token"]
    product = await create_product(client, token, business_id, stock="10.000")

    sales = []
    for _ in range(2):
        response = await client.post(
            f"/api/v1/businesses/{business_id}/sales",
            headers=auth(token),
            json={
                "client_operation_id": str(uuid4()),
                "items": [{"product_id": product["id"], "quantity": "1.000"}],
                "payment_method": "CASH",
                "discount_amount": "0.00",
            },
        )
        assert response.status_code == 201
        sales.append(response.json())
    from app.models.sale import Sale

    first = db.get(Sale, UUID(sales[0]["id"]))
    second = db.get(Sale, UUID(sales[1]["id"]))
    first.sold_at = datetime(2026, 12, 31, 21, 59, 59, tzinfo=UTC)
    second.sold_at = datetime(2026, 12, 31, 22, 0, 0, tzinfo=UTC)
    db.commit()

    report = await client.get(
        f"/api/v1/businesses/{business_id}/reports/sales?date_from=2027-01-01&date_to=2027-01-01",
        headers=auth(token),
    )
    assert report.status_code == 200, report.text
    body = report.json()
    assert body["sales_count"] == 1 and body["gross_sales"] == "500.00"
    assert body["sales_by_day"] == [
        {"date": "2027-01-01", "sales_count": 1, "amount": "500.00"}
    ]

    year = resolve_period(
        ReportRange.TODAY,
        None,
        None,
        now=datetime(2026, 12, 31, 22, 30, tzinfo=UTC),
    )
    assert year.date_from.isoformat() == "2027-01-01"
    assert year.start_utc == datetime(2026, 12, 31, 22, 0, tzinfo=UTC)
