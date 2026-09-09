from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies.business import BusinessAccess, BusinessMemberAccess, require_business_write_access
from app.db.session import get_db
from app.models.enums import MembershipRole
from app.models.product import Product


@dataclass(frozen=True)
class ProductAccess:
    product: Product
    business_access: BusinessAccess


def require_inventory_mutator(
    access: Annotated[BusinessAccess, Depends(require_business_write_access)],
) -> BusinessAccess:
    if access.membership.role not in {MembershipRole.OWNER, MembershipRole.MANAGER}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    return access


InventoryMutatorAccess = Annotated[BusinessAccess, Depends(require_inventory_mutator)]


def get_product_access(
    product_id: UUID,
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> ProductAccess:
    product = db.scalar(
        select(Product).where(Product.id == product_id, Product.business_id == access.business.id)
    )
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
    return ProductAccess(product=product, business_access=access)


def get_product_mutation_access(
    product_id: UUID,
    access: InventoryMutatorAccess,
    db: Annotated[Session, Depends(get_db)],
) -> ProductAccess:
    product = db.scalar(
        select(Product).where(Product.id == product_id, Product.business_id == access.business.id)
    )
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
    return ProductAccess(product=product, business_access=access)


ProductMemberAccess = Annotated[ProductAccess, Depends(get_product_access)]
ProductMutationAccess = Annotated[ProductAccess, Depends(get_product_mutation_access)]
