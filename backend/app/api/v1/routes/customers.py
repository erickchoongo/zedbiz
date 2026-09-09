from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.dependencies.auth import CurrentUser
from app.api.dependencies.business import BusinessMemberAccess
from app.api.dependencies.customer import CustomerCreateAccess, CustomerMemberAccess, CustomerMutationAccess
from app.db.session import get_db
from app.models.enums import MembershipRole
from app.schemas.customer import (
    CustomerCreateRequest,
    CustomerDetailResponse,
    CustomerListItemResponse,
    CustomerListResponse,
    CustomerUpdateRequest,
)
from app.schemas.debt import DebtListItemResponse
from app.services.customers import CustomerService, CustomerWithBalances
from app.services.debts import DebtService, DebtWithPeople, is_debt_overdue, lusaka_today


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


def _customer_item(result: CustomerWithBalances) -> CustomerListItemResponse:
    return CustomerListItemResponse.model_validate(
        {
            **result.customer.__dict__,
            "total_outstanding": result.total_outstanding,
            "total_overdue": result.total_overdue,
            "open_debt_count": result.open_debt_count,
        }
    )


def _customer_detail(
    db: Session,
    result: CustomerWithBalances,
    *,
    role: MembershipRole,
) -> CustomerDetailResponse:
    customer = result.customer
    debts = DebtService(db).recent_for_customer(customer.business_id, customer.id)
    return CustomerDetailResponse.model_validate(
        {
            **customer.__dict__,
            "notes": customer.notes if role in {MembershipRole.OWNER, MembershipRole.MANAGER} else None,
            "total_outstanding": result.total_outstanding,
            "total_overdue": result.total_overdue,
            "open_debt_count": result.open_debt_count,
            "recent_debts": [_debt_item(debt) for debt in debts],
        }
    )


@router.post("", response_model=CustomerDetailResponse, status_code=status.HTTP_201_CREATED)
def create_customer(
    request: CustomerCreateRequest,
    access: CustomerCreateAccess,
    db: Annotated[Session, Depends(get_db)],
) -> CustomerDetailResponse:
    if access.membership.role == MembershipRole.CASHIER and request.notes is not None:
        raise HTTPException(status_code=403, detail="Cashiers cannot set internal customer notes")
    service = CustomerService(db)
    customer = service.create(access.business.id, request)
    return _customer_detail(
        db,
        service.with_balances(customer, today=lusaka_today()),
        role=access.membership.role,
    )


@router.get("", response_model=CustomerListResponse)
def list_customers(
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: str | None = Query(None, max_length=200),
    is_active: bool | None = None,
    outstanding_only: bool | None = None,
) -> CustomerListResponse:
    result = CustomerService(db).list(
        access.business.id,
        today=lusaka_today(),
        page=page,
        page_size=page_size,
        search=search,
        is_active=is_active,
        outstanding_only=outstanding_only,
    )
    return CustomerListResponse(
        items=[_customer_item(item) for item in result.items],
        page=page,
        page_size=page_size,
        total=result.total,
    )


@router.get("/{customer_id}", response_model=CustomerDetailResponse)
def get_customer(
    access: CustomerMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> CustomerDetailResponse:
    service = CustomerService(db)
    return _customer_detail(
        db,
        service.with_balances(access.customer, today=lusaka_today()),
        role=access.business_access.membership.role,
    )


@router.patch("/{customer_id}", response_model=CustomerDetailResponse)
def update_customer(
    request: CustomerUpdateRequest,
    access: CustomerMutationAccess,
    db: Annotated[Session, Depends(get_db)],
) -> CustomerDetailResponse:
    service = CustomerService(db)
    customer = service.update(access.customer, request)
    return _customer_detail(
        db,
        service.with_balances(customer, today=lusaka_today()),
        role=access.business_access.membership.role,
    )


def _set_active(
    active: bool,
    access: CustomerMutationAccess,
    actor: CurrentUser,
    db: Session,
) -> CustomerDetailResponse:
    service = CustomerService(db)
    customer = service.set_active(access.customer, active, actor)
    return _customer_detail(
        db,
        service.with_balances(customer, today=lusaka_today()),
        role=access.business_access.membership.role,
    )


@router.post("/{customer_id}/deactivate", response_model=CustomerDetailResponse)
def deactivate_customer(
    access: CustomerMutationAccess,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> CustomerDetailResponse:
    return _set_active(False, access, current_user, db)


@router.post("/{customer_id}/reactivate", response_model=CustomerDetailResponse)
def reactivate_customer(
    access: CustomerMutationAccess,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> CustomerDetailResponse:
    return _set_active(True, access, current_user, db)
