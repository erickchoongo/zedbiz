from uuid import UUID

from sqlalchemy.orm import Session

from app.models.business import Business
from app.models.business_membership import BusinessMembership
from app.models.enums import MembershipRole
from app.models.user import User
from app.models.onboarding_record import OnboardingRecord
from app.models.sale_counter import SaleCounter
from app.repositories.businesses import BusinessRepository, BusinessWithRole
from app.schemas.business import BusinessCreateRequest, BusinessUpdateRequest


class BusinessService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.businesses = BusinessRepository(db)

    def create_for_owner(self, request: BusinessCreateRequest, owner: User) -> BusinessWithRole:
        business = Business(**request.model_dump())
        self.businesses.add(business)
        try:
            self.db.flush()
            membership = BusinessMembership(
                user_id=owner.id,
                business_id=business.id,
                role=MembershipRole.OWNER,
            )
            self.db.add(membership)
            self.db.add(OnboardingRecord(business_id=business.id))
            self.db.add(SaleCounter(business_id=business.id, next_value=1))
            self.db.commit()
            self.db.refresh(business)
        except Exception:
            self.db.rollback()
            raise
        return BusinessWithRole(business=business, role=MembershipRole.OWNER)

    def list_for_user(self, user_id: UUID) -> list[BusinessWithRole]:
        return self.businesses.list_for_user(user_id)

    def update(self, business: Business, request: BusinessUpdateRequest) -> Business:
        for field, value in request.model_dump(exclude_unset=True).items():
            setattr(business, field, value)
        try:
            self.db.commit()
            self.db.refresh(business)
        except Exception:
            self.db.rollback()
            raise
        return business
