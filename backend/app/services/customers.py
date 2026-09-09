from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import Session

from app.models.customer import Customer
from app.models.debt import Debt
from app.models.enums import DebtStatus
from app.models.user import User
from app.schemas.customer import CustomerCreateRequest, CustomerUpdateRequest
from app.services.commercial import add_audit


ZERO = Decimal("0.00")
ACTIVE_DEBT_STATUSES = (DebtStatus.OPEN, DebtStatus.PARTIALLY_PAID)


@dataclass(frozen=True)
class CustomerWithBalances:
    customer: Customer
    total_outstanding: Decimal
    total_overdue: Decimal
    open_debt_count: int


@dataclass(frozen=True)
class CustomerPage:
    items: list[CustomerWithBalances]
    total: int


class CustomerService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create(
        self,
        business_id: UUID,
        request: CustomerCreateRequest,
    ) -> Customer:
        customer = Customer(
            business_id=business_id,
            name=request.name,
            phone_number=request.phone_number,
            email=str(request.email) if request.email is not None else None,
            notes=request.notes,
            is_active=True,
        )
        self.db.add(customer)
        try:
            self.db.commit()
            self.db.refresh(customer)
        except Exception:
            self.db.rollback()
            raise
        return customer

    def list(
        self,
        business_id: UUID,
        *,
        today: date,
        page: int,
        page_size: int,
        search: str | None,
        is_active: bool | None,
        outstanding_only: bool | None,
    ) -> CustomerPage:
        aggregate = self._aggregate_subquery(business_id, today)
        filters = [Customer.business_id == business_id]
        if search:
            pattern = f"%{search.strip()}%"
            filters.append(
                or_(
                    Customer.name.ilike(pattern),
                    Customer.phone_number.ilike(pattern),
                    Customer.email.ilike(pattern),
                )
            )
        if is_active is not None:
            filters.append(Customer.is_active.is_(is_active))
        if outstanding_only is True:
            filters.append(func.coalesce(aggregate.c.total_outstanding, ZERO) > ZERO)
        elif outstanding_only is False:
            filters.append(func.coalesce(aggregate.c.total_outstanding, ZERO) == ZERO)

        total = self.db.scalar(
            select(func.count())
            .select_from(Customer)
            .outerjoin(aggregate, aggregate.c.customer_id == Customer.id)
            .where(*filters)
        ) or 0
        rows = self.db.execute(
            select(
                Customer,
                func.coalesce(aggregate.c.total_outstanding, ZERO),
                func.coalesce(aggregate.c.total_overdue, ZERO),
                func.coalesce(aggregate.c.open_debt_count, 0),
            )
            .outerjoin(aggregate, aggregate.c.customer_id == Customer.id)
            .where(*filters)
            .order_by(Customer.name, Customer.id)
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        return CustomerPage(
            items=[
                CustomerWithBalances(
                    customer=row[0],
                    total_outstanding=self._money(row[1]),
                    total_overdue=self._money(row[2]),
                    open_debt_count=int(row[3]),
                )
                for row in rows
            ],
            total=int(total),
        )

    def with_balances(self, customer: Customer, *, today: date) -> CustomerWithBalances:
        aggregate = self._aggregate_subquery(customer.business_id, today)
        row = self.db.execute(
            select(
                func.coalesce(aggregate.c.total_outstanding, ZERO),
                func.coalesce(aggregate.c.total_overdue, ZERO),
                func.coalesce(aggregate.c.open_debt_count, 0),
            ).where(aggregate.c.customer_id == customer.id)
        ).one_or_none()
        if row is None:
            return CustomerWithBalances(customer, ZERO, ZERO, 0)
        return CustomerWithBalances(
            customer=customer,
            total_outstanding=self._money(row[0]),
            total_overdue=self._money(row[1]),
            open_debt_count=int(row[2]),
        )

    def update(self, customer: Customer, request: CustomerUpdateRequest) -> Customer:
        values = request.model_dump(exclude_unset=True)
        if "email" in values and values["email"] is not None:
            values["email"] = str(values["email"])
        for field, value in values.items():
            setattr(customer, field, value)
        try:
            self.db.commit()
            self.db.refresh(customer)
        except Exception:
            self.db.rollback()
            raise
        return customer

    def set_active(self, customer: Customer, active: bool, actor: User) -> Customer:
        if customer.is_active == active:
            return customer
        customer.is_active = active
        add_audit(
            self.db,
            actor_user_id=actor.id,
            business_id=customer.business_id,
            action="customer.reactivated" if active else "customer.deactivated",
            entity_type="customer",
            entity_id=customer.id,
            metadata={},
        )
        try:
            self.db.commit()
            self.db.refresh(customer)
        except Exception:
            self.db.rollback()
            raise
        return customer

    @staticmethod
    def _money(value: object) -> Decimal:
        return Decimal(str(value or 0)).quantize(Decimal("0.01"))

    @staticmethod
    def _aggregate_subquery(business_id: UUID, today: date):  # type: ignore[no-untyped-def]
        active = and_(
            Debt.status.in_(ACTIVE_DEBT_STATUSES),
            Debt.outstanding_amount > ZERO,
        )
        overdue = and_(active, Debt.due_date.is_not(None), Debt.due_date < today)
        return (
            select(
                Debt.customer_id.label("customer_id"),
                func.sum(case((active, Debt.outstanding_amount), else_=ZERO)).label("total_outstanding"),
                func.sum(case((overdue, Debt.outstanding_amount), else_=ZERO)).label("total_overdue"),
                func.sum(case((active, 1), else_=0)).label("open_debt_count"),
            )
            .where(Debt.business_id == business_id)
            .group_by(Debt.customer_id)
            .subquery()
        )
