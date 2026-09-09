import hashlib
import json
from dataclasses import dataclass
from datetime import date
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.core.time import utc_now
from app.models.enums import ExpenseCategory, ExpenseStatus, MembershipRole, PaymentMethod
from app.models.expense import Expense
from app.models.user import User
from app.schemas.expense import ExpenseCreateRequest, ExpenseVoidRequest
from app.services.commercial import add_audit


@dataclass(frozen=True)
class ExpenseWithPeople:
    expense: Expense
    recorded_by_name: str | None
    voided_by_name: str | None = None


@dataclass(frozen=True)
class ExpensePage:
    items: list[ExpenseWithPeople]
    total: int


class ExpenseService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create(self, business_id: UUID, request: ExpenseCreateRequest, actor: User) -> ExpenseWithPeople:
        fingerprint = self._fingerprint(request)
        existing = self._by_operation(business_id, request.client_operation_id)
        if existing is not None:
            self._validate_retry(existing, fingerprint)
            return self._with_people(existing)

        expense = Expense(
            business_id=business_id,
            category=request.category,
            description=request.description,
            amount=request.amount,
            payment_method=request.payment_method,
            payment_reference=request.payment_reference,
            expense_date=request.expense_date,
            notes=request.notes,
            client_operation_id=request.client_operation_id,
            request_fingerprint=fingerprint,
            recorded_by_user_id=actor.id,
            status=ExpenseStatus.RECORDED,
        )
        self.db.add(expense)
        try:
            self.db.commit()
            self.db.refresh(expense)
        except IntegrityError as exc:
            self.db.rollback()
            concurrent = self._by_operation(business_id, request.client_operation_id)
            if concurrent is not None:
                self._validate_retry(concurrent, fingerprint)
                return self._with_people(concurrent)
            raise HTTPException(status_code=409, detail="Expense conflicted with another transaction") from exc
        except Exception:
            self.db.rollback()
            raise
        return self._with_people(expense)

    def list(
        self,
        business_id: UUID,
        *,
        role: MembershipRole,
        actor_user_id: UUID,
        page: int,
        page_size: int,
        search: str | None,
        category: ExpenseCategory | None,
        payment_method: PaymentMethod | None,
        status: ExpenseStatus | None,
        date_from: date | None,
        date_to: date | None,
        recorded_by_user_id: UUID | None,
    ) -> ExpensePage:
        filters = [Expense.business_id == business_id]
        if role == MembershipRole.CASHIER:
            filters.append(Expense.recorded_by_user_id == actor_user_id)
        elif recorded_by_user_id is not None:
            filters.append(Expense.recorded_by_user_id == recorded_by_user_id)
        if search:
            pattern = f"%{search.strip()}%"
            filters.append(or_(Expense.description.ilike(pattern), Expense.payment_reference.ilike(pattern)))
        if category:
            filters.append(Expense.category == category)
        if payment_method:
            filters.append(Expense.payment_method == payment_method)
        if status:
            filters.append(Expense.status == status)
        if date_from:
            filters.append(Expense.expense_date >= date_from)
        if date_to:
            filters.append(Expense.expense_date <= date_to)
        total = self.db.scalar(select(func.count()).select_from(Expense).where(*filters)) or 0
        rows = self.db.scalars(
            select(Expense)
            .options(selectinload(Expense.recorded_by), selectinload(Expense.voided_by))
            .where(*filters)
            .order_by(Expense.expense_date.desc(), Expense.created_at.desc(), Expense.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        return ExpensePage([self._with_people(row) for row in rows], total)

    def get(
        self,
        business_id: UUID,
        expense_id: UUID,
        *,
        role: MembershipRole | None = None,
        actor_user_id: UUID | None = None,
    ) -> ExpenseWithPeople:
        filters = [Expense.id == expense_id, Expense.business_id == business_id]
        if role == MembershipRole.CASHIER:
            filters.append(Expense.recorded_by_user_id == actor_user_id)
        expense = self.db.scalar(
            select(Expense)
            .options(selectinload(Expense.recorded_by), selectinload(Expense.voided_by))
            .where(*filters)
        )
        if expense is None:
            raise HTTPException(status_code=404, detail="Expense not found")
        return self._with_people(expense)

    def void(
        self,
        business_id: UUID,
        expense_id: UUID,
        request: ExpenseVoidRequest,
        actor: User,
    ) -> ExpenseWithPeople:
        operation_expense = self.db.scalar(
            select(Expense).where(
                Expense.business_id == business_id,
                Expense.void_client_operation_id == request.client_operation_id,
            )
        )
        if operation_expense is not None:
            if operation_expense.id == expense_id and operation_expense.void_reason == request.reason:
                return self.get(business_id, expense_id)
            raise HTTPException(status_code=409, detail="Void operation ID was already used for a different request")

        expense = self.db.scalar(
            select(Expense)
            .where(Expense.id == expense_id, Expense.business_id == business_id)
            .with_for_update()
        )
        if expense is None:
            raise HTTPException(status_code=404, detail="Expense not found")
        if expense.status != ExpenseStatus.RECORDED:
            raise HTTPException(status_code=409, detail="Expense has already been voided")

        expense.status = ExpenseStatus.VOIDED
        expense.voided_at = utc_now()
        expense.voided_by_user_id = actor.id
        expense.void_reason = request.reason
        expense.void_client_operation_id = request.client_operation_id
        add_audit(
            self.db,
            actor_user_id=actor.id,
            business_id=business_id,
            action="expense.voided",
            entity_type="expense",
            entity_id=expense.id,
            metadata={"reason": request.reason},
        )
        try:
            self.db.commit()
        except IntegrityError as exc:
            self.db.rollback()
            concurrent = self.db.scalar(
                select(Expense).where(
                    Expense.business_id == business_id,
                    Expense.void_client_operation_id == request.client_operation_id,
                )
            )
            if concurrent is not None and concurrent.id == expense_id and concurrent.void_reason == request.reason:
                return self.get(business_id, expense_id)
            raise HTTPException(status_code=409, detail="Void conflicted with another transaction") from exc
        except Exception:
            self.db.rollback()
            raise
        return self.get(business_id, expense_id)

    def _by_operation(self, business_id: UUID, operation_id: UUID) -> Expense | None:
        return self.db.scalar(
            select(Expense)
            .options(selectinload(Expense.recorded_by), selectinload(Expense.voided_by))
            .where(Expense.business_id == business_id, Expense.client_operation_id == operation_id)
        )

    @staticmethod
    def _with_people(expense: Expense) -> ExpenseWithPeople:
        return ExpenseWithPeople(
            expense=expense,
            recorded_by_name=expense.recorded_by.full_name if expense.recorded_by else None,
            voided_by_name=expense.voided_by.full_name if expense.voided_by else None,
        )

    @staticmethod
    def _fingerprint(request: ExpenseCreateRequest) -> str:
        payload = {
            "category": request.category.value,
            "description": request.description,
            "amount": format(request.amount, ".2f"),
            "payment_method": request.payment_method.value,
            "payment_reference": request.payment_reference,
            "expense_date": request.expense_date.isoformat(),
            "notes": request.notes,
        }
        return hashlib.sha256(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()).hexdigest()

    @staticmethod
    def _validate_retry(expense: Expense, fingerprint: str) -> None:
        if expense.request_fingerprint != fingerprint:
            raise HTTPException(status_code=409, detail="Client operation ID was already used for a different expense")
