from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.dependencies.business import BusinessMemberAccess
from app.db.session import get_db
from app.models.enums import MembershipRole
from app.schemas.reporting import (
    CategoryBreakdownResponse,
    DailyExpensesResponse,
    DailySalesResponse,
    DashboardResponse,
    ExpensePaymentBreakdownResponse,
    ExpensesReportResponse,
    LargestExpenseResponse,
    PaymentBreakdownResponse,
    PerformanceReportResponse,
    PeriodResponse,
    RecentExpenseResponse,
    RecentSaleResponse,
    ReportRange,
    SalesReportResponse,
    TopProductResponse,
)
from app.services.reporting import ReportPeriod, ReportingService, resolve_period
from app.services.debts import lusaka_today

router = APIRouter()


def _period(value: ReportPeriod) -> PeriodResponse:
    return PeriodResponse(
        range=value.name,
        date_from=value.date_from,
        date_to=value.date_to,
        timezone=value.timezone_name,
    )


def _resolve(
    range_name: ReportRange | None,
    date_from: date | None,
    date_to: date | None,
) -> ReportPeriod:
    return resolve_period(range_name, date_from, date_to)


@router.get("/dashboard", response_model=DashboardResponse)
def dashboard(
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
    range_name: ReportRange | None = Query(None, alias="range"),
    date_from: date | None = None,
    date_to: date | None = None,
) -> DashboardResponse:
    period = _resolve(range_name, date_from, date_to)
    service = ReportingService(db)
    sales = service.sales_totals(access.business.id, period)
    low_stock, out_of_stock = service.inventory_totals(access.business.id)
    recent_sales = service.recent_sales(access.business.id, period)
    privileged = access.membership.role in {MembershipRole.OWNER, MembershipRole.MANAGER}

    expenses = service.expense_totals(access.business.id, period) if privileged else None
    outstanding, overdue = (
        service.debt_totals(access.business.id, today=lusaka_today())
        if privileged
        else (None, None)
    )
    recent_expenses = service.recent_expenses(access.business.id, period) if privileged else None
    after_expenses = (
        (sales.gross_profit - expenses.total_expenses).quantize(Decimal("0.01"))
        if expenses is not None
        else None
    )
    return DashboardResponse(
        business_id=access.business.id,
        currency=access.business.currency,
        period=_period(period),
        gross_sales=sales.gross_sales,
        sales_count=sales.sales_count,
        gross_profit=sales.gross_profit if privileged else None,
        total_expenses=expenses.total_expenses if expenses else None,
        net_operating_result=after_expenses,
        outstanding_customer_debt=outstanding,
        overdue_customer_debt=overdue,
        low_stock_count=low_stock,
        out_of_stock_count=out_of_stock,
        recent_sales=[
            RecentSaleResponse(
                id=item.id,
                sale_number=item.sale_number,
                total_amount=item.total_amount,
                payment_method=item.payment_method,
                sold_at=item.sold_at,
                status=item.status,
            )
            for item in recent_sales
        ],
        recent_expenses=(
            [
                RecentExpenseResponse(
                    id=item.id,
                    description=item.description,
                    category=item.category,
                    amount=item.amount,
                    expense_date=item.expense_date,
                    payment_method=item.payment_method,
                )
                for item in recent_expenses
            ]
            if recent_expenses is not None
            else None
        ),
    )


@router.get("/reports/sales", response_model=SalesReportResponse)
def sales_report(
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
    range_name: ReportRange | None = Query(None, alias="range"),
    date_from: date | None = None,
    date_to: date | None = None,
) -> SalesReportResponse:
    period = _resolve(range_name, date_from, date_to)
    service = ReportingService(db)
    totals = service.sales_totals(access.business.id, period)
    privileged = access.membership.role in {MembershipRole.OWNER, MembershipRole.MANAGER}
    average = (
        (totals.gross_sales / totals.sales_count).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        )
        if totals.sales_count
        else Decimal("0.00")
    )
    return SalesReportResponse(
        business_id=access.business.id,
        currency=access.business.currency,
        period=_period(period),
        gross_sales=totals.gross_sales,
        sales_count=totals.sales_count,
        average_sale_value=average,
        gross_profit=totals.gross_profit if privileged else None,
        payment_breakdown=[
            PaymentBreakdownResponse(payment_method=method, sales_count=count, amount=amount)
            for method, count, amount in service.payment_breakdown(access.business.id, period)
        ],
        sales_by_day=[
            DailySalesResponse(date=day, sales_count=count, amount=amount)
            for day, count, amount in service.sales_by_day(access.business.id, period)
        ],
        top_products=[
            TopProductResponse(product_id=product_id, product_name=name, quantity=quantity, revenue=revenue)
            for product_id, name, quantity, revenue in service.top_products(access.business.id, period)
        ],
    )


def _require_profit_role(access: BusinessMemberAccess) -> None:
    if access.membership.role not in {MembershipRole.OWNER, MembershipRole.MANAGER}:
        raise HTTPException(status_code=403, detail="Expense and profitability reports require an owner or manager role")


@router.get("/reports/expenses", response_model=ExpensesReportResponse)
def expenses_report(
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
    range_name: ReportRange | None = Query(None, alias="range"),
    date_from: date | None = None,
    date_to: date | None = None,
) -> ExpensesReportResponse:
    _require_profit_role(access)
    period = _resolve(range_name, date_from, date_to)
    service = ReportingService(db)
    totals = service.expense_totals(access.business.id, period)
    return ExpensesReportResponse(
        business_id=access.business.id,
        currency=access.business.currency,
        period=_period(period),
        total_expenses=totals.total_expenses,
        expense_count=totals.expense_count,
        category_breakdown=[
            CategoryBreakdownResponse(category=category, expense_count=count, amount=amount)
            for category, count, amount in service.category_breakdown(access.business.id, period)
        ],
        payment_breakdown=[
            ExpensePaymentBreakdownResponse(payment_method=method, expense_count=count, amount=amount)
            for method, count, amount in service.expense_payment_breakdown(access.business.id, period)
        ],
        expenses_by_day=[
            DailyExpensesResponse(date=day, expense_count=count, amount=amount)
            for day, count, amount in service.expenses_by_day(access.business.id, period)
        ],
        largest_expenses=[
            LargestExpenseResponse(
                id=item.id,
                description=item.description,
                category=item.category,
                amount=item.amount,
                expense_date=item.expense_date,
                payment_method=item.payment_method,
            )
            for item in service.largest_expenses(access.business.id, period)
        ],
    )


@router.get("/reports/performance", response_model=PerformanceReportResponse)
def performance_report(
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
    range_name: ReportRange | None = Query(None, alias="range"),
    date_from: date | None = None,
    date_to: date | None = None,
) -> PerformanceReportResponse:
    _require_profit_role(access)
    period = _resolve(range_name, date_from, date_to)
    service = ReportingService(db)
    sales = service.sales_totals(access.business.id, period)
    expenses = service.expense_totals(access.business.id, period)
    return PerformanceReportResponse(
        business_id=access.business.id,
        currency=access.business.currency,
        period=_period(period),
        gross_sales=sales.gross_sales,
        gross_profit=sales.gross_profit,
        expenses=expenses.total_expenses,
        net_operating_result=(sales.gross_profit - expenses.total_expenses).quantize(Decimal("0.01")),
        gross_margin_percentage=service.gross_margin(sales.gross_sales, sales.gross_profit),
    )
