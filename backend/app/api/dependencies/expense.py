from typing import Annotated

from fastapi import Depends, HTTPException, status

from app.api.dependencies.business import BusinessAccess, require_business_write_access
from app.models.enums import MembershipRole


def require_expense_write_access(
    access: Annotated[BusinessAccess, Depends(require_business_write_access)],
) -> BusinessAccess:
    if access.membership.role not in {
        MembershipRole.OWNER,
        MembershipRole.MANAGER,
        MembershipRole.CASHIER,
    }:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    return access


def require_expense_void_access(
    access: Annotated[BusinessAccess, Depends(require_business_write_access)],
) -> BusinessAccess:
    if access.membership.role not in {MembershipRole.OWNER, MembershipRole.MANAGER}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    return access


ExpenseWriteAccess = Annotated[BusinessAccess, Depends(require_expense_write_access)]
ExpenseVoidAccess = Annotated[BusinessAccess, Depends(require_expense_void_access)]
