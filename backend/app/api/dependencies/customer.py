from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies.business import BusinessAccess, BusinessMemberAccess, require_business_write_access
from app.db.session import get_db
from app.models.customer import Customer
from app.models.enums import MembershipRole


@dataclass(frozen=True)
class CustomerAccess:
    customer: Customer
    business_access: BusinessAccess


def require_customer_create_access(
    access: Annotated[BusinessAccess, Depends(require_business_write_access)],
) -> BusinessAccess:
    if access.membership.role not in {
        MembershipRole.OWNER,
        MembershipRole.MANAGER,
        MembershipRole.CASHIER,
    }:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    return access


def require_customer_admin_access(
    access: Annotated[BusinessAccess, Depends(require_business_write_access)],
) -> BusinessAccess:
    if access.membership.role not in {MembershipRole.OWNER, MembershipRole.MANAGER}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient business role")
    return access


def get_customer_access(
    customer_id: UUID,
    access: BusinessMemberAccess,
    db: Annotated[Session, Depends(get_db)],
) -> CustomerAccess:
    customer = db.scalar(
        select(Customer).where(
            Customer.id == customer_id,
            Customer.business_id == access.business.id,
        )
    )
    if customer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")
    return CustomerAccess(customer=customer, business_access=access)


def get_customer_mutation_access(
    customer_id: UUID,
    access: Annotated[BusinessAccess, Depends(require_customer_admin_access)],
    db: Annotated[Session, Depends(get_db)],
) -> CustomerAccess:
    customer = db.scalar(
        select(Customer).where(
            Customer.id == customer_id,
            Customer.business_id == access.business.id,
        )
    )
    if customer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")
    return CustomerAccess(customer=customer, business_access=access)


CustomerCreateAccess = Annotated[BusinessAccess, Depends(require_customer_create_access)]
CustomerMemberAccess = Annotated[CustomerAccess, Depends(get_customer_access)]
CustomerMutationAccess = Annotated[CustomerAccess, Depends(get_customer_mutation_access)]
