from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status as http_status
from sqlalchemy.orm import Session

from app.api.dependencies.auth import CurrentUser
from app.api.dependencies.business import BusinessMemberAccess
from app.api.dependencies.expense import ExpenseVoidAccess, ExpenseWriteAccess
from app.db.session import get_db
from app.models.enums import ExpenseCategory, ExpenseStatus, MembershipRole, PaymentMethod
from app.schemas.expense import ExpenseCreateRequest, ExpenseListResponse, ExpenseResponse, ExpenseVoidRequest
from app.services.expenses import ExpenseService, ExpenseWithPeople

router = APIRouter()


@router.post("/reconcile", response_model=ExpenseResponse)
def reconcile_expense(request: ExpenseCreateRequest, access: BusinessMemberAccess,
                      db: Annotated[Session, Depends(get_db)]) -> ExpenseResponse:
    """Recover acceptance without requiring a currently writable subscription."""
    service = ExpenseService(db)
    expense = service._by_operation(access.business.id, request.client_operation_id)
    if expense is None:
        raise HTTPException(status_code=404, detail="Saved expense has not been accepted")
    service._validate_retry(expense, service._fingerprint(request))
    return _response(service.get(access.business.id, expense.id,
        role=access.membership.role, actor_user_id=access.membership.user_id))


def _response(result: ExpenseWithPeople) -> ExpenseResponse:
    return ExpenseResponse.model_validate(
        {
            **result.expense.__dict__,
            "recorded_by_name": result.recorded_by_name,
            "voided_by_name": result.voided_by_name,
        }
    )


@router.post("", response_model=ExpenseResponse, status_code=http_status.HTTP_201_CREATED)
def create_expense(
    request: ExpenseCreateRequest,
    access: ExpenseWriteAccess,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ExpenseResponse:
    if access.membership.role == MembershipRole.CASHIER and request.notes is not None:
        raise HTTPException(status_code=403, detail="Cashiers cannot add private expense notes")
    result = ExpenseService(db).create(access.business.id, request, current_user)
    if (
        access.membership.role == MembershipRole.CASHIER
        and result.expense.recorded_by_user_id != current_user.id
    ):
        raise HTTPException(status_code=409, detail="Expense operation ID is already in use")
    return _response(result)


@router.get("", response_model=ExpenseListResponse)
def list_expenses(
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: str | None = Query(None, max_length=120),
    category: ExpenseCategory | None = None,
    payment_method: PaymentMethod | None = None,
    status: ExpenseStatus | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
    recorded_by_user_id: UUID | None = None,
) -> ExpenseListResponse:
    if payment_method == PaymentMethod.CUSTOMER_DEBT:
        raise HTTPException(status_code=422, detail="CUSTOMER_DEBT is not a valid expense payment method")
    if date_from and date_to and date_from > date_to:
        raise HTTPException(status_code=422, detail="date_from must be before date_to")
    if access.membership.role == MembershipRole.CASHIER and recorded_by_user_id not in {
        None,
        access.membership.user_id,
    }:
        raise HTTPException(status_code=403, detail="Cashiers may only view expenses they recorded")
    result = ExpenseService(db).list(
        access.business.id,
        role=access.membership.role,
        actor_user_id=access.membership.user_id,
        page=page,
        page_size=page_size,
        search=search,
        category=category,
        payment_method=payment_method,
        status=status,
        date_from=date_from,
        date_to=date_to,
        recorded_by_user_id=recorded_by_user_id,
    )
    return ExpenseListResponse(
        items=[_response(item) for item in result.items],
        page=page,
        page_size=page_size,
        total=result.total,
    )


@router.get("/{expense_id}", response_model=ExpenseResponse)
def get_expense(
    expense_id: UUID,
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> ExpenseResponse:
    return _response(
        ExpenseService(db).get(
            access.business.id,
            expense_id,
            role=access.membership.role,
            actor_user_id=access.membership.user_id,
        )
    )


@router.post("/{expense_id}/void", response_model=ExpenseResponse)
def void_expense(
    expense_id: UUID,
    request: ExpenseVoidRequest,
    access: ExpenseVoidAccess,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ExpenseResponse:
    return _response(ExpenseService(db).void(access.business.id, expense_id, request, current_user))
