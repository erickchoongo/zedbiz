from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import HTTPException
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.business import Business
from app.models.customer import Customer
from app.models.debt import Debt
from app.models.debt_payment import DebtPayment
from app.models.enums import DebtStatus
from app.models.sale import Sale
from app.models.user import User
from app.schemas.debt import DebtPaymentCreateRequest


ZERO = Decimal("0.00")
MONEY = Decimal("0.01")
ACTIVE_DEBT_STATUSES = (DebtStatus.OPEN, DebtStatus.PARTIALLY_PAID)


def lusaka_today(now: datetime | None = None) -> date:
    current = now or utc_now()
    try:
        zone = ZoneInfo("Africa/Lusaka")
    except ZoneInfoNotFoundError:
        # Zambia has used UTC+02:00 year-round since 1942; this is a safe
        # fallback for minimal Windows installations without the IANA database.
        zone = timezone(timedelta(hours=2))
    return current.astimezone(zone).date()


def is_debt_overdue(debt: Debt, *, today: date) -> bool:
    return bool(
        debt.status in ACTIVE_DEBT_STATUSES
        and debt.outstanding_amount > ZERO
        and debt.due_date is not None
        and debt.due_date < today
    )


@dataclass(frozen=True)
class DebtWithPeople:
    debt: Debt
    customer_name: str
    customer_phone_number: str | None
    sale_number: str
    created_by_name: str | None


@dataclass(frozen=True)
class DebtPage:
    items: list[DebtWithPeople]
    total: int


@dataclass(frozen=True)
class DebtTotals:
    total_outstanding: Decimal
    total_overdue: Decimal
    customers_owing: int
    open_debt_count: int


@dataclass(frozen=True)
class PaymentWithPerson:
    payment: DebtPayment
    customer_name: str
    received_by_name: str | None


@dataclass(frozen=True)
class PaymentPage:
    items: list[PaymentWithPerson]
    total: int


@dataclass(frozen=True)
class PaymentResult:
    payment: PaymentWithPerson
    debt: DebtWithPeople


class DebtService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list(
        self,
        business_id: UUID,
        *,
        today: date,
        page: int,
        page_size: int,
        status: DebtStatus | None,
        overdue_only: bool | None,
        customer_id: UUID | None,
        due_date_from: date | None,
        due_date_to: date | None,
        search: str | None,
    ) -> DebtPage:
        filters = [Debt.business_id == business_id]
        if status is not None:
            filters.append(Debt.status == status)
        overdue = self._overdue_expression(today)
        if overdue_only is True:
            filters.append(overdue)
        elif overdue_only is False:
            filters.append(~overdue)
        if customer_id is not None:
            filters.append(Debt.customer_id == customer_id)
        if due_date_from is not None:
            filters.append(Debt.due_date >= due_date_from)
        if due_date_to is not None:
            filters.append(Debt.due_date <= due_date_to)
        if search:
            pattern = f"%{search.strip()}%"
            filters.append(or_(Customer.name.ilike(pattern), Customer.phone_number.ilike(pattern)))

        joined = (
            select(Debt)
            .join(
                Customer,
                and_(Customer.id == Debt.customer_id, Customer.business_id == Debt.business_id),
            )
            .where(*filters)
        )
        total = self.db.scalar(select(func.count()).select_from(joined.subquery())) or 0
        priority = case(
            (overdue, 0),
            (Debt.status.in_(ACTIVE_DEBT_STATUSES), 1),
            (Debt.status == DebtStatus.PAID, 2),
            else_=3,
        )
        null_due = case((Debt.due_date.is_(None), 1), else_=0)
        statement = (
            self._people_statement()
            .where(*filters)
            .order_by(priority, null_due, Debt.due_date, Debt.created_at, Debt.id)
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        return DebtPage(items=self._people_rows(statement), total=int(total))

    def get(self, business_id: UUID, debt_id: UUID) -> DebtWithPeople:
        rows = self._people_rows(
            self._people_statement().where(Debt.id == debt_id, Debt.business_id == business_id)
        )
        if not rows:
            raise HTTPException(status_code=404, detail="Debt not found")
        return rows[0]

    def recent_for_customer(
        self,
        business_id: UUID,
        customer_id: UUID,
        *,
        limit: int = 5,
    ) -> list[DebtWithPeople]:
        return self._people_rows(
            self._people_statement()
            .where(Debt.business_id == business_id, Debt.customer_id == customer_id)
            .order_by(Debt.created_at.desc(), Debt.id.desc())
            .limit(limit)
        )

    def summary(self, business_id: UUID, *, today: date) -> DebtTotals:
        active = and_(
            Debt.status.in_(ACTIVE_DEBT_STATUSES),
            Debt.outstanding_amount > ZERO,
        )
        overdue = and_(active, Debt.due_date.is_not(None), Debt.due_date < today)
        row = self.db.execute(
            select(
                func.coalesce(func.sum(case((active, Debt.outstanding_amount), else_=ZERO)), ZERO),
                func.coalesce(func.sum(case((overdue, Debt.outstanding_amount), else_=ZERO)), ZERO),
                func.count(func.distinct(case((active, Debt.customer_id), else_=None))),
                func.coalesce(func.sum(case((active, 1), else_=0)), 0),
            ).where(Debt.business_id == business_id)
        ).one()
        return DebtTotals(
            total_outstanding=self._money(row[0]),
            total_overdue=self._money(row[1]),
            customers_owing=int(row[2]),
            open_debt_count=int(row[3]),
        )

    def list_payments(
        self,
        business_id: UUID,
        debt_id: UUID,
        *,
        page: int,
        page_size: int,
    ) -> PaymentPage:
        # The scoped existence check distinguishes a foreign/missing debt from a
        # valid debt with no payments without leaking tenant data.
        self.get(business_id, debt_id)
        filters = [DebtPayment.business_id == business_id, DebtPayment.debt_id == debt_id]
        total = self.db.scalar(
            select(func.count()).select_from(DebtPayment).where(*filters)
        ) or 0
        rows = self.db.execute(
            self._payment_statement()
            .where(*filters)
            .order_by(DebtPayment.paid_at.desc(), DebtPayment.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        return PaymentPage(items=self._payment_rows(rows), total=int(total))

    def record_payment(
        self,
        business_id: UUID,
        debt_id: UUID,
        request: DebtPaymentCreateRequest,
        actor: User,
    ) -> PaymentResult:
        fingerprint = self._payment_fingerprint(debt_id, request)
        existing = self._payment_by_operation(business_id, request.client_operation_id)
        if existing is not None:
            self._validate_payment_retry(existing, fingerprint)
            return PaymentResult(
                payment=self._payment_with_person(existing.id, business_id),
                debt=self.get(business_id, existing.debt_id),
            )

        debt = self.db.scalar(
            select(Debt)
            .where(Debt.id == debt_id, Debt.business_id == business_id)
            .with_for_update()
        )
        if debt is None:
            raise HTTPException(status_code=404, detail="Debt not found")
        # A same-operation request may have committed while this transaction
        # waited for the debt row lock. Recheck before evaluating the updated
        # balance so a concurrent retry remains idempotent even when the first
        # payment fully settled the debt.
        concurrent_retry = self._payment_by_operation(
            business_id, request.client_operation_id
        )
        if concurrent_retry is not None:
            self._validate_payment_retry(concurrent_retry, fingerprint)
            return PaymentResult(
                payment=self._payment_with_person(concurrent_retry.id, business_id),
                debt=self.get(business_id, concurrent_retry.debt_id),
            )
        if debt.status == DebtStatus.VOIDED:
            raise HTTPException(status_code=409, detail="A voided debt cannot receive repayments")
        if debt.status == DebtStatus.PAID or debt.outstanding_amount == ZERO:
            raise HTTPException(status_code=409, detail="This debt has already been paid")
        if request.amount > debt.outstanding_amount:
            raise HTTPException(
                status_code=409,
                detail=f"Payment exceeds the outstanding balance of {debt.outstanding_amount:.2f}",
            )

        now = utc_now()
        payment = DebtPayment(
            business_id=business_id,
            debt_id=debt.id,
            customer_id=debt.customer_id,
            amount=request.amount,
            payment_method=request.payment_method,
            payment_reference=request.payment_reference,
            client_operation_id=request.client_operation_id,
            request_fingerprint=fingerprint,
            received_by_user_id=actor.id,
            paid_at=now,
            notes=request.notes,
        )
        debt.amount_paid = (debt.amount_paid + request.amount).quantize(MONEY)
        debt.outstanding_amount = (debt.original_amount - debt.amount_paid).quantize(MONEY)
        if debt.outstanding_amount == ZERO:
            debt.status = DebtStatus.PAID
            debt.settled_at = now
        else:
            debt.status = DebtStatus.PARTIALLY_PAID
            debt.settled_at = None
        self.db.add(payment)
        try:
            self.db.commit()
            self.db.refresh(payment)
        except IntegrityError as exc:
            self.db.rollback()
            concurrent = self._payment_by_operation(business_id, request.client_operation_id)
            if concurrent is not None:
                self._validate_payment_retry(concurrent, fingerprint)
                return PaymentResult(
                    payment=self._payment_with_person(concurrent.id, business_id),
                    debt=self.get(business_id, concurrent.debt_id),
                )
            raise HTTPException(status_code=409, detail="Repayment conflicted with another update") from exc
        except Exception:
            self.db.rollback()
            raise
        return PaymentResult(
            payment=self._payment_with_person(payment.id, business_id),
            debt=self.get(business_id, debt.id),
        )

    def reminder(self, business: Business, debt_id: UUID) -> tuple[DebtWithPeople, str]:
        result = self.get(business.id, debt_id)
        debt = result.debt
        if debt.status not in ACTIVE_DEBT_STATUSES or debt.outstanding_amount <= ZERO:
            raise HTTPException(status_code=409, detail="Debt has no outstanding balance")
        amount = f"K{debt.outstanding_amount:.2f}" if business.currency == "ZMW" else f"{business.currency} {debt.outstanding_amount:.2f}"
        lines = [
            f"Hello {result.customer_name},",
            "",
            f"This is a reminder from {business.name} that your outstanding balance is {amount}.",
        ]
        if debt.due_date is not None:
            due = f"{debt.due_date.day} {debt.due_date.strftime('%B %Y')}"
            lines.extend(["", f"Due date: {due}."])
        lines.extend(["", "Thank you."])
        return result, "\n".join(lines)

    def _people_statement(self):  # type: ignore[no-untyped-def]
        return (
            select(Debt, Customer.name, Customer.phone_number, Sale.sale_number, User.full_name)
            .join(
                Customer,
                and_(Customer.id == Debt.customer_id, Customer.business_id == Debt.business_id),
            )
            .join(Sale, and_(Sale.id == Debt.sale_id, Sale.business_id == Debt.business_id))
            .join(User, User.id == Debt.created_by_user_id)
        )

    def _people_rows(self, statement) -> list[DebtWithPeople]:  # type: ignore[no-untyped-def]
        return [
            DebtWithPeople(
                debt=row[0],
                customer_name=row[1],
                customer_phone_number=row[2],
                sale_number=row[3],
                created_by_name=row[4],
            )
            for row in self.db.execute(statement).all()
        ]

    def _payment_statement(self):  # type: ignore[no-untyped-def]
        return (
            select(DebtPayment, Customer.name, User.full_name)
            .join(
                Customer,
                and_(
                    Customer.id == DebtPayment.customer_id,
                    Customer.business_id == DebtPayment.business_id,
                ),
            )
            .join(User, User.id == DebtPayment.received_by_user_id)
        )

    @staticmethod
    def _payment_rows(rows) -> list[PaymentWithPerson]:  # type: ignore[no-untyped-def]
        return [
            PaymentWithPerson(payment=row[0], customer_name=row[1], received_by_name=row[2])
            for row in rows
        ]

    def _payment_with_person(self, payment_id: UUID, business_id: UUID) -> PaymentWithPerson:
        rows = self._payment_rows(
            self.db.execute(
                self._payment_statement().where(
                    DebtPayment.id == payment_id,
                    DebtPayment.business_id == business_id,
                )
            ).all()
        )
        if not rows:
            raise HTTPException(status_code=404, detail="Repayment not found")
        return rows[0]

    def _payment_by_operation(self, business_id: UUID, operation_id: UUID) -> DebtPayment | None:
        return self.db.scalar(
            select(DebtPayment).where(
                DebtPayment.business_id == business_id,
                DebtPayment.client_operation_id == operation_id,
            )
        )

    @staticmethod
    def _payment_fingerprint(debt_id: UUID, request: DebtPaymentCreateRequest) -> str:
        canonical = {
            "amount": format(request.amount, ".2f"),
            "debt_id": str(debt_id),
            "notes": request.notes,
            "payment_method": request.payment_method.value,
            "payment_reference": request.payment_reference,
        }
        raw = json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode()
        return hashlib.sha256(raw).hexdigest()

    @staticmethod
    def _validate_payment_retry(payment: DebtPayment, fingerprint: str) -> None:
        if payment.request_fingerprint != fingerprint:
            raise HTTPException(
                status_code=409,
                detail="Client operation ID was already used for a different repayment",
            )

    @staticmethod
    def _money(value: object) -> Decimal:
        return Decimal(str(value or 0)).quantize(MONEY)

    @staticmethod
    def _overdue_expression(today: date):  # type: ignore[no-untyped-def]
        return and_(
            Debt.status.in_(ACTIVE_DEBT_STATUSES),
            Debt.outstanding_amount > ZERO,
            Debt.due_date.is_not(None),
            Debt.due_date < today,
        )
