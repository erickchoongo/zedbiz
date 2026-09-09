from uuid import UUID

from sqlalchemy import CheckConstraint, ForeignKey, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class SaleCounter(Base):
    __tablename__ = "sale_counters"
    __table_args__ = (CheckConstraint("next_value > 0", name="ck_sale_counters_next_positive"),)

    business_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), primary_key=True
    )
    next_value: Mapped[int] = mapped_column(nullable=False, default=1)

    business = relationship("Business", back_populates="sale_counter")
