from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.dependencies.business import BusinessMemberAccess
from app.db.session import get_db
from app.models.product import Product
from app.schemas.product import InventorySummaryResponse, ProductListResponse, ProductResponse
from app.services.inventory import InventoryService

router = APIRouter()


def _response(item: Product) -> ProductResponse:
    return ProductResponse.model_validate({**item.__dict__, "is_low_stock": True, "sale_version": item.sale_version})


@router.get("/low-stock", response_model=ProductListResponse)
def low_stock(access: BusinessMemberAccess, db: Annotated[Session, Depends(get_db)],
              page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100)) -> ProductListResponse:
    result = InventoryService(db).list_products(access.business.id, page=page, page_size=page_size,
        search=None, is_active=True, low_stock=True, track_inventory=True)
    return ProductListResponse(items=[_response(item) for item in result.items], page=page, page_size=page_size, total=result.total)


@router.get("/summary", response_model=InventorySummaryResponse)
def summary(access: BusinessMemberAccess, db: Annotated[Session, Depends(get_db)]) -> InventorySummaryResponse:
    totals = InventoryService(db).summary(access.business.id)
    return InventorySummaryResponse(
        total_active_products=totals.total_active_products,
        low_stock_count=totals.low_stock_count,
        out_of_stock_count=totals.out_of_stock_count,
    )
