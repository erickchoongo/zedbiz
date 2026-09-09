from typing import Annotated

from fastapi import Depends, HTTPException, status

from app.api.dependencies.business import BusinessAccess, require_business_write_access
from app.models.enums import MembershipRole


def require_sale_write_access(
    access: Annotated[BusinessAccess, Depends(require_business_write_access)],
) -> BusinessAccess:
    if access.membership.role not in {MembershipRole.OWNER, MembershipRole.MANAGER, MembershipRole.CASHIER}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    return access


def require_sale_void_access(
    access: Annotated[BusinessAccess, Depends(require_business_write_access)],
) -> BusinessAccess:
    if access.membership.role not in {MembershipRole.OWNER, MembershipRole.MANAGER}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    return access


SaleWriteAccess = Annotated[BusinessAccess, Depends(require_sale_write_access)]
SaleVoidAccess = Annotated[BusinessAccess, Depends(require_sale_void_access)]
