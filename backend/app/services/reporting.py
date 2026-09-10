from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import HTTPException
from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session

from app.core.time import ensure_utc, utc_now
from app.models.debt import Debt
from app.models.enums import DebtStatus, ExpenseStatus, SaleStatus
from app.models.expense import Expense
from app.models.product import Product
from app.models.sale import Sale
from app.models.sale_item import SaleItem
from app.schemas.reporting import ReportRange
from app.services.inventory import InventoryService

ZERO = Decimal("0.00")
MONEY = Decimal("0.01")


@dataclass(frozen=True)
class ReportPeriod:
    name: str
    date_from: date
    date_to: date
    start_utc: datetime
    end_utc: datetime
    timezone_name: str


@dataclass(frozen=True)
class SalesTotals:
    gross_sales: Decimal
    sales_count: int
    gross_profit: Decimal


@dataclass(frozen=True)
class ExpenseTotals:
    total_expenses: Decimal
    expense_count: int


def lusaka_zone():
    try:
        return ZoneInfo("Africa/Lusaka")
    except ZoneInfoNotFoundError:
        return timezone(timedelta(hours=2), name="Africa/Lusaka")


def resolve_period(
    range_name: ReportRange | None,
    date_from: date | None,
    date_to: date | None,
    *,
    now: datetime | None = None,
) -> ReportPeriod:
    if (date_from is None) != (date_to is None):
        raise HTTPException(status_code=422, detail="date_from and date_to must be provided together")
    if date_from is not None and date_to is not None:
        if date_from > date_to:
            raise HTTPException(status_code=422, detail="date_from must be before date_to")
        if (date_to - date_from).days > 366 or date_to == date.max:
            raise HTTPException(status_code=422, detail='Report date range must not exceed 367 days')
        start_date, end_date, name = date_from, date_to, "custom"
    else:
        current = ensure_utc(now or utc_now()).astimezone(lusaka_zone()).date()
        selected = range_name or ReportRange.TODAY
        if selected == ReportRange.TODAY:
            start_date, end_date = current, current
        elif selected == ReportRange.YESTERDAY:
            start_date = end_date = current - timedelta(days=1)
        elif selected == ReportRange.WEEK:
            start_date, end_date = current - timedelta(days=current.weekday()), current
        else:
            start_date, end_date = current.replace(day=1), current
        name = selected.value

    zone = lusaka_zone()
    start_utc = datetime.combine(start_date, time.min, zone).astimezone(UTC)
    end_utc = datetime.combine(end_date + timedelta(days=1), time.min, zone).astimezone(UTC)
    return ReportPeriod(name, start_date, end_date, start_utc, end_utc, "Africa/Lusaka")


class ReportingService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def sales_totals(self, business_id: UUID, period: ReportPeriod) -> SalesTotals:
        row = self.db.execute(
            select(
                func.coalesce(func.sum(Sale.total_amount), ZERO),
                func.count(Sale.id),
                func.coalesce(func.sum(Sale.gross_profit), ZERO),
            ).where(*self._sale_filters(business_id, period))
        ).one()
        return SalesTotals(self._money(row[0]), int(row[1]), self._money(row[2]))

    def expense_totals(self, business_id: UUID, period: ReportPeriod) -> ExpenseTotals:
        row = self.db.execute(
            select(func.coalesce(func.sum(Expense.amount), ZERO), func.count(Expense.id)).where(
                *self._expense_filters(business_id, period)
            )
        ).one()
        return ExpenseTotals(self._money(row[0]), int(row[1]))

    def debt_totals(self, business_id: UUID, *, today: date) -> tuple[Decimal, Decimal]:
        active = and_(
            Debt.status.in_((DebtStatus.OPEN, DebtStatus.PARTIALLY_PAID)),
            Debt.outstanding_amount > ZERO,
        )
        overdue = and_(active, Debt.due_date.is_not(None), Debt.due_date < today)
        # CASE keeps the query portable across SQLite and PostgreSQL while the
        # business predicate remains explicit on the aggregate source.
        from sqlalchemy import case

        values = self.db.execute(
            select(
                func.coalesce(func.sum(case((active, Debt.outstanding_amount), else_=ZERO)), ZERO),
                func.coalesce(func.sum(case((overdue, Debt.outstanding_amount), else_=ZERO)), ZERO),
            ).where(Debt.business_id == business_id)
        ).one()
        return self._money(values[0]), self._money(values[1])

    def inventory_totals(self, business_id: UUID) -> tuple[int, int]:
        totals = InventoryService(self.db).summary(business_id)
        return totals.low_stock_count, totals.out_of_stock_count

    def recent_sales(self, business_id: UUID, period: ReportPeriod, *, limit: int = 5) -> list[Sale]:
        return list(
            self.db.scalars(
                select(Sale)
                .where(*self._sale_filters(business_id, period))
                .order_by(Sale.sold_at.desc(), Sale.id.desc())
                .limit(limit)
            ).all()
        )

    def recent_expenses(self, business_id: UUID, period: ReportPeriod, *, limit: int = 5) -> list[Expense]:
        return list(
            self.db.scalars(
                select(Expense)
                .where(*self._expense_filters(business_id, period))
                .order_by(Expense.expense_date.desc(), Expense.created_at.desc(), Expense.id.desc())
                .limit(limit)
            ).all()
        )

    def payment_breakdown(self, business_id: UUID, period: ReportPeriod) -> list[tuple[object, int, Decimal]]:
        rows = self.db.execute(
            select(Sale.payment_method, func.count(Sale.id), func.sum(Sale.total_amount))
            .where(*self._sale_filters(business_id, period))
            .group_by(Sale.payment_method)
            .order_by(Sale.payment_method)
        ).all()
        return [(row[0], int(row[1]), self._money(row[2])) for row in rows]

    def sales_by_day(self, business_id: UUID, period: ReportPeriod) -> list[tuple[date, int, Decimal]]:
        values: dict[date, tuple[int, Decimal]] = defaultdict(lambda: (0, ZERO))
        for sold_at, amount in self.db.execute(
            select(Sale.sold_at, Sale.total_amount)
            .where(*self._sale_filters(business_id, period))
            .order_by(Sale.sold_at)
        ).all():
            local_date = ensure_utc(sold_at).astimezone(lusaka_zone()).date()
            count, total = values[local_date]
            values[local_date] = (count + 1, total + Decimal(str(amount)))
        return [(day, count, self._money(amount)) for day, (count, amount) in sorted(values.items())]

    def top_products(self, business_id: UUID, period: ReportPeriod, *, limit: int = 10) -> list[tuple]:
        rows = self.db.execute(
            select(
                SaleItem.product_id,
                func.coalesce(func.max(Product.name), func.min(SaleItem.product_name_snapshot)),
                func.sum(SaleItem.quantity),
                func.sum(SaleItem.line_subtotal),
            )
            .join(
                Sale,
                and_(Sale.id == SaleItem.sale_id, Sale.business_id == SaleItem.business_id),
            )
            .outerjoin(
                Product,
                and_(Product.id == SaleItem.product_id, Product.business_id == SaleItem.business_id),
            )
            .where(SaleItem.business_id == business_id, *self._sale_filters(business_id, period))
            .group_by(SaleItem.product_id)
            .order_by(func.sum(SaleItem.line_subtotal).desc(), SaleItem.product_id)
            .limit(limit)
        ).all()
        return [
            (row[0], row[1], Decimal(str(row[2])).quantize(Decimal("0.001")), self._money(row[3]))
            for row in rows
        ]

    def category_breakdown(self, business_id: UUID, period: ReportPeriod) -> list[tuple[object, int, Decimal]]:
        rows = self.db.execute(
            select(Expense.category, func.count(Expense.id), func.sum(Expense.amount))
            .where(*self._expense_filters(business_id, period))
            .group_by(Expense.category)
            .order_by(func.sum(Expense.amount).desc(), Expense.category)
        ).all()
        return [(row[0], int(row[1]), self._money(row[2])) for row in rows]

    def expense_payment_breakdown(
        self, business_id: UUID, period: ReportPeriod
    ) -> list[tuple[object, int, Decimal]]:
        rows = self.db.execute(
            select(Expense.payment_method, func.count(Expense.id), func.sum(Expense.amount))
            .where(*self._expense_filters(business_id, period))
            .group_by(Expense.payment_method)
            .order_by(Expense.payment_method)
        ).all()
        return [(row[0], int(row[1]), self._money(row[2])) for row in rows]

    def expenses_by_day(self, business_id: UUID, period: ReportPeriod) -> list[tuple[date, int, Decimal]]:
        rows = self.db.execute(
            select(Expense.expense_date, func.count(Expense.id), func.sum(Expense.amount))
            .where(*self._expense_filters(business_id, period))
            .group_by(Expense.expense_date)
            .order_by(Expense.expense_date)
        ).all()
        return [(row[0], int(row[1]), self._money(row[2])) for row in rows]

    def largest_expenses(self, business_id: UUID, period: ReportPeriod, *, limit: int = 10) -> list[Expense]:
        return list(
            self.db.scalars(
                select(Expense)
                .where(*self._expense_filters(business_id, period))
                .order_by(Expense.amount.desc(), Expense.expense_date.desc(), Expense.id)
                .limit(limit)
            ).all()
        )

    @staticmethod
    def gross_margin(gross_sales: Decimal, gross_profit: Decimal) -> Decimal:
        if gross_sales == ZERO:
            return ZERO
        return ((gross_profit / gross_sales) * Decimal("100")).quantize(MONEY, rounding=ROUND_HALF_UP)

    @staticmethod
    def _sale_filters(business_id: UUID, period: ReportPeriod) -> list:
        return [
            Sale.business_id == business_id,
            Sale.status == SaleStatus.COMPLETED,
            Sale.sold_at >= period.start_utc,
            Sale.sold_at < period.end_utc,
        ]

    @staticmethod
    def _expense_filters(business_id: UUID, period: ReportPeriod) -> list:
        return [
            Expense.business_id == business_id,
            Expense.status == ExpenseStatus.RECORDED,
            Expense.expense_date >= period.date_from,
            Expense.expense_date <= period.date_to,
        ]

    @staticmethod
    def _money(value: object) -> Decimal:
        return Decimal(str(value or 0)).quantize(MONEY)
