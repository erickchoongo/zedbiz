from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status as http_status
from sqlalchemy.orm import Session

from app.api.dependencies.auth import CurrentUser
from app.api.dependencies.business import BusinessMemberAccess
from app.api.dependencies.debt import DebtPaymentAccess
from app.db.session import get_db
from app.models.enums import DebtStatus, MembershipRole
from app.schemas.debt import (
    DebtDetailResponse,
    DebtListItemResponse,
    DebtListResponse,
    DebtPaymentCreateRequest,
    DebtPaymentCreateResponse,
    DebtPaymentListResponse,
    DebtPaymentResponse,
    DebtReminderResponse,
    DebtSummaryResponse,
)
from app.services.debts import (
    DebtService,
    DebtWithPeople,
    PaymentWithPerson,
    is_debt_overdue,
    lusaka_today,
)


router = APIRouter()


def _debt_item(result: DebtWithPeople) -> DebtListItemResponse:
    debt = result.debt
    return DebtListItemResponse.model_validate(
        {
            **debt.__dict__,
            "customer_name": result.customer_name,
            "customer_phone_number": result.customer_phone_number,
            "sale_number": result.sale_number,
            "is_overdue": is_debt_overdue(debt, today=lusaka_today()),
        }
    )


def _debt_detail(result: DebtWithPeople, role: MembershipRole) -> DebtDetailResponse:
    debt = result.debt
    return DebtDetailResponse.model_validate(
        {
            **debt.__dict__,
            "customer_name": result.customer_name,
            "customer_phone_number": result.customer_phone_number,
            "sale_number": result.sale_number,
            "created_by_name": result.created_by_name,
            "notes": debt.notes if role in {MembershipRole.OWNER, MembershipRole.MANAGER} else None,
            "is_overdue": is_debt_overdue(debt, today=lusaka_today()),
        }
    )


def _payment_item(result: PaymentWithPerson, role: MembershipRole) -> DebtPaymentResponse:
    payment = result.payment
    return DebtPaymentResponse.model_validate(
        {
            **payment.__dict__,
            "customer_name": result.customer_name,
            "received_by_name": result.received_by_name,
            "notes": payment.notes if role in {MembershipRole.OWNER, MembershipRole.MANAGER} else None,
        }
    )


@router.get("", response_model=DebtListResponse)
def list_debts(
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    status: DebtStatus | None = None,
    overdue_only: bool | None = None,
    customer_id: UUID | None = None,
    due_date_from: date | None = None,
    due_date_to: date | None = None,
    search: str | None = Query(None, max_length=200),
) -> DebtListResponse:
    if due_date_from and due_date_to and due_date_from > due_date_to:
        raise HTTPException(status_code=422, detail="due_date_from must be before due_date_to")
    result = DebtService(db).list(
        access.business.id,
        today=lusaka_today(),
        page=page,
        page_size=page_size,
        status=status,
        overdue_only=overdue_only,
        customer_id=customer_id,
        due_date_from=due_date_from,
        due_date_to=due_date_to,
        search=search,
    )
    return DebtListResponse(
        items=[_debt_item(item) for item in result.items],
        page=page,
        page_size=page_size,
        total=result.total,
    )


@router.get("/summary", response_model=DebtSummaryResponse)
def debt_summary(
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> DebtSummaryResponse:
    result = DebtService(db).summary(access.business.id, today=lusaka_today())
    return DebtSummaryResponse.model_validate(result.__dict__)


@router.get("/{debt_id}", response_model=DebtDetailResponse)
def get_debt(
    debt_id: UUID,
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> DebtDetailResponse:
    return _debt_detail(
        DebtService(db).get(access.business.id, debt_id),
        access.membership.role,
    )


@router.get("/{debt_id}/payments", response_model=DebtPaymentListResponse)
def list_debt_payments(
    debt_id: UUID,
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
) -> DebtPaymentListResponse:
    result = DebtService(db).list_payments(
        access.business.id,
        debt_id,
        page=page,
        page_size=page_size,
    )
    return DebtPaymentListResponse(
        items=[_payment_item(item, access.membership.role) for item in result.items],
        page=page,
        page_size=page_size,
        total=result.total,
    )


@router.post(
    "/{debt_id}/payments",
    response_model=DebtPaymentCreateResponse,
    status_code=http_status.HTTP_201_CREATED,
)
def record_debt_payment(
    debt_id: UUID,
    request: DebtPaymentCreateRequest,
    access: DebtPaymentAccess,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> DebtPaymentCreateResponse:
    if access.membership.role == MembershipRole.CASHIER and request.notes is not None:
        raise HTTPException(status_code=403, detail="Cashiers cannot set internal repayment notes")
    result = DebtService(db).record_payment(access.business.id, debt_id, request, current_user)
    return DebtPaymentCreateResponse(
        payment=_payment_item(result.payment, access.membership.role),
        debt=_debt_detail(result.debt, access.membership.role),
    )


@router.get("/{debt_id}/reminder", response_model=DebtReminderResponse)
def get_debt_reminder(
    debt_id: UUID,
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> DebtReminderResponse:
    result, message = DebtService(db).reminder(access.business, debt_id)
    return DebtReminderResponse(
        debt_id=result.debt.id,
        customer_id=result.debt.customer_id,
        customer_name=result.customer_name,
        phone_number=result.customer_phone_number,
        outstanding_amount=result.debt.outstanding_amount,
        due_date=result.debt.due_date,
        message=message,
    )
