from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status as http_status
from sqlalchemy.orm import Session

from app.api.dependencies.auth import CurrentUser
from app.api.dependencies.business import BusinessMemberAccess
from app.api.dependencies.sale import SaleVoidAccess, SaleWriteAccess
from app.db.session import get_db
from app.models.enums import MembershipRole, PaymentMethod, SaleStatus
from app.schemas.sale import (
    ReceiptResponse, SaleCreateRequest, SaleItemResponse, SaleListItemResponse,
    SaleListResponse, SaleResponse, SaleVoidRequest,
)
from app.services.sales import SaleWithPeople, SalesService

router = APIRouter()


@router.post("/reconcile", response_model=SaleResponse)
def reconcile_sale(request: SaleCreateRequest, access: BusinessMemberAccess,
                   db: Annotated[Session, Depends(get_db)]) -> SaleResponse:
    """Read-only recovery of an acknowledged or lost-response operation."""
    service = SalesService(db)
    sale = service._by_operation(access.business.id, request.client_operation_id)
    if sale is None:
        raise HTTPException(status_code=404, detail="Saved sale has not been accepted")
    service._validate_sale_retry(sale, service._fingerprint(request, service._aggregate(request)))
    return _response(service.get(access.business.id, sale.id), access.membership.role)


def _response(result: SaleWithPeople, role: MembershipRole) -> SaleResponse:
    privileged = role in {MembershipRole.OWNER, MembershipRole.MANAGER}
    sale = result.sale
    items = [
        SaleItemResponse.model_validate({
            **item.__dict__,
            "unit_cost": item.unit_cost if privileged else None,
            "line_cost": item.line_cost if privileged else None,
            "line_profit": item.line_profit if privileged else None,
        }) for item in sale.items
    ]
    return SaleResponse.model_validate({
        **sale.__dict__, "sold_by_name": result.sold_by_name,
        "voided_by_name": result.voided_by_name, "items": items,
        "total_cost": sale.total_cost if privileged else None,
        "gross_profit": sale.gross_profit if privileged else None,
        "customer_name": sale.customer.name if sale.customer is not None else None,
        "debt_id": sale.debt.id if sale.debt is not None else None,
        "debt_status": sale.debt.status if sale.debt is not None else None,
        "debt_due_date": sale.debt.due_date if sale.debt is not None else None,
        "debt_outstanding_amount": sale.debt.outstanding_amount if sale.debt is not None else None,
    })


@router.post("", response_model=SaleResponse, status_code=http_status.HTTP_201_CREATED)
def create_sale(request: SaleCreateRequest, access: SaleWriteAccess, current_user: CurrentUser,
                db: Annotated[Session, Depends(get_db)]) -> SaleResponse:
    return _response(SalesService(db).create(access.business.id, request, current_user), access.membership.role)


@router.get("", response_model=SaleListResponse)
def list_sales(
    access: BusinessMemberAccess, db: Annotated[Session, Depends(get_db)],
    page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
    search: str | None = Query(None, max_length=100), payment_method: PaymentMethod | None = None,
    status: SaleStatus | None = None, date_from: datetime | None = None,
    date_to: datetime | None = None, sold_by_user_id: UUID | None = None,
) -> SaleListResponse:
    if date_from and date_to and date_from > date_to:
        raise HTTPException(status_code=422, detail="date_from must be before date_to")
    if access.membership.role == MembershipRole.CASHIER and sold_by_user_id not in {None, access.membership.user_id}:
        raise HTTPException(status_code=403, detail="Cashiers may only filter sales by themselves")
    result = SalesService(db).list(access.business.id, page=page, page_size=page_size, search=search,
        payment_method=payment_method, status=status, date_from=date_from, date_to=date_to,
        sold_by_user_id=sold_by_user_id)
    return SaleListResponse(
        items=[SaleListItemResponse(id=row.sale.id, client_operation_id=row.sale.client_operation_id, sale_number=row.sale.sale_number,
            status=row.sale.status, total_amount=row.sale.total_amount,
            payment_method=row.sale.payment_method, sold_at=row.sale.sold_at,
            sold_by_name=row.sold_by_name) for row in result.items],
        page=page, page_size=page_size, total=result.total,
    )


@router.get("/{sale_id}", response_model=SaleResponse)
def get_sale(sale_id: UUID, access: BusinessMemberAccess,
             db: Annotated[Session, Depends(get_db)]) -> SaleResponse:
    return _response(SalesService(db).get(access.business.id, sale_id), access.membership.role)


@router.get("/{sale_id}/receipt", response_model=ReceiptResponse)
def get_receipt(sale_id: UUID, access: BusinessMemberAccess,
                db: Annotated[Session, Depends(get_db)]) -> ReceiptResponse:
    return SalesService(db).receipt(access.business, sale_id)


@router.post("/{sale_id}/void", response_model=SaleResponse)
def void_sale(sale_id: UUID, request: SaleVoidRequest, access: SaleVoidAccess,
              current_user: CurrentUser, db: Annotated[Session, Depends(get_db)]) -> SaleResponse:
    return _response(SalesService(db).void(access.business.id, sale_id, request, current_user), access.membership.role)
