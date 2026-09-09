from typing import Annotated

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.dependencies.auth import CurrentUser
from app.api.dependencies.business import BusinessMemberAccess
from app.api.dependencies.product import InventoryMutatorAccess, ProductMemberAccess, ProductMutationAccess
from app.db.session import get_db
from app.models.enums import InventoryMovementType
from app.models.product import Product
from app.schemas.product import (
    InventoryMovementListResponse, InventoryMovementResponse, ProductCreateRequest,
    ProductListResponse, ProductResponse, ProductUpdateRequest, StockAddRequest,
    StockAdjustRequest, StockReductionRequest,
)
from app.services.inventory import InventoryService, MovementWithActor

router = APIRouter()


def _product(product: Product) -> ProductResponse:
    low = bool(product.is_active and product.track_inventory and product.stock_quantity <= product.low_stock_threshold)
    return ProductResponse.model_validate({**product.__dict__, "is_low_stock": low, "sale_version": product.sale_version})


def _movement(row: MovementWithActor) -> InventoryMovementResponse:
    return InventoryMovementResponse.model_validate(
        {**row.movement.__dict__, "performed_by_name": row.actor_name}
    )


@router.post("", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
def create_product(request: ProductCreateRequest, access: InventoryMutatorAccess,
                   current_user: CurrentUser, db: Annotated[Session, Depends(get_db)]) -> ProductResponse:
    return _product(InventoryService(db).create_product(access.business.id, request, current_user))


@router.get("", response_model=ProductListResponse)
def list_products(access: BusinessMemberAccess, db: Annotated[Session, Depends(get_db)],
                  page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
                  search: str | None = Query(None, max_length=200), is_active: bool | None = None,
                  low_stock: bool | None = None, track_inventory: bool | None = None) -> ProductListResponse:
    result = InventoryService(db).list_products(access.business.id, page=page, page_size=page_size,
        search=search, is_active=is_active, low_stock=low_stock, track_inventory=track_inventory)
    return ProductListResponse(items=[_product(item) for item in result.items], page=page, page_size=page_size, total=result.total)


@router.get("/{product_id}", response_model=ProductResponse)
def get_product(access: ProductMemberAccess) -> ProductResponse:
    return _product(access.product)


@router.patch("/{product_id}", response_model=ProductResponse)
def update_product(request: ProductUpdateRequest, access: ProductMutationAccess,
                   db: Annotated[Session, Depends(get_db)]) -> ProductResponse:
    return _product(InventoryService(db).update_product(access.product, request))


@router.post("/{product_id}/deactivate", response_model=ProductResponse)
def deactivate_product(access: ProductMutationAccess, current_user: CurrentUser,
                       db: Annotated[Session, Depends(get_db)]) -> ProductResponse:
    return _product(InventoryService(db).set_active(access.product, False, current_user))


@router.post("/{product_id}/reactivate", response_model=ProductResponse)
def reactivate_product(access: ProductMutationAccess, current_user: CurrentUser,
                       db: Annotated[Session, Depends(get_db)]) -> ProductResponse:
    return _product(InventoryService(db).set_active(access.product, True, current_user))


def _single_movement(movement: object, current_user: CurrentUser) -> InventoryMovementResponse:
    return _movement(MovementWithActor(movement=movement, actor_name=current_user.full_name))  # type: ignore[arg-type]


@router.post("/{product_id}/stock/add", response_model=InventoryMovementResponse)
def add_stock(request: StockAddRequest, access: ProductMutationAccess, current_user: CurrentUser,
              db: Annotated[Session, Depends(get_db)]) -> InventoryMovementResponse:
    item = InventoryService(db).add_stock(access.product.id, access.product.business_id, request, current_user)
    return _single_movement(item, current_user)


@router.post("/{product_id}/stock/adjust", response_model=InventoryMovementResponse)
def adjust_stock(request: StockAdjustRequest, access: ProductMutationAccess, current_user: CurrentUser,
                 db: Annotated[Session, Depends(get_db)]) -> InventoryMovementResponse:
    item = InventoryService(db).adjust_stock(access.product.id, access.product.business_id, request, current_user)
    return _single_movement(item, current_user)


def _reduce(request: StockReductionRequest, access: ProductMutationAccess, current_user: CurrentUser,
            db: Session, movement_type: InventoryMovementType) -> InventoryMovementResponse:
    item = InventoryService(db).reduce_stock(access.product.id, access.product.business_id, request, current_user, movement_type)
    return _single_movement(item, current_user)


@router.post("/{product_id}/stock/damaged", response_model=InventoryMovementResponse)
def damaged_stock(request: StockReductionRequest, access: ProductMutationAccess, current_user: CurrentUser,
                  db: Annotated[Session, Depends(get_db)]) -> InventoryMovementResponse:
    return _reduce(request, access, current_user, db, InventoryMovementType.DAMAGED)


@router.post("/{product_id}/stock/lost", response_model=InventoryMovementResponse)
def lost_stock(request: StockReductionRequest, access: ProductMutationAccess, current_user: CurrentUser,
               db: Annotated[Session, Depends(get_db)]) -> InventoryMovementResponse:
    return _reduce(request, access, current_user, db, InventoryMovementType.LOST)


@router.get("/{product_id}/inventory-movements", response_model=InventoryMovementListResponse)
def movement_history(access: ProductMemberAccess, db: Annotated[Session, Depends(get_db)],
                     page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
                     movement_type: InventoryMovementType | None = None) -> InventoryMovementListResponse:
    result = InventoryService(db).movement_history(access.product.id, access.product.business_id,
        page=page, page_size=page_size, movement_type=movement_type)
    return InventoryMovementListResponse(items=[_movement(row) for row in result.items], page=page, page_size=page_size, total=result.total)
