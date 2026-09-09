from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies.business import BusinessAccess, BusinessMemberAccess, require_business_write_access
from app.db.session import get_db
from app.models.debt import Debt
from app.models.enums import MembershipRole


@dataclass(frozen=True)
class DebtAccess:
    debt: Debt
    business_access: BusinessAccess


def require_debt_payment_access(
    access: Annotated[BusinessAccess, Depends(require_business_write_access)],
) -> BusinessAccess:
    if access.membership.role not in {
        MembershipRole.OWNER,
        MembershipRole.MANAGER,
        MembershipRole.CASHIER,
    }:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    return access


def get_debt_access(
    debt_id: UUID,
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> DebtAccess:
    debt = db.scalar(
        select(Debt).where(
            Debt.id == debt_id,
            Debt.business_id == access.business.id,
        )
    )
    if debt is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Debt not found")
    return DebtAccess(debt=debt, business_access=access)


DebtPaymentAccess = Annotated[BusinessAccess, Depends(require_debt_payment_access)]
DebtMemberAccess = Annotated[DebtAccess, Depends(get_debt_access)]
