from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, Enum, ForeignKey, Index, Numeric, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.time import utc_now
from app.db.base import Base
from app.models.enums import InventoryMovementType


class InventoryMovement(Base):
    __tablename__ = "inventory_movements"
    __table_args__ = (
        UniqueConstraint("business_id", "client_operation_id", name="uq_inventory_movements_business_operation"),
        CheckConstraint(
            "movement_type IN ('OPENING_STOCK', 'STOCK_ADDED', 'MANUAL_ADJUSTMENT', 'DAMAGED', 'LOST', 'SALE', 'SALE_VOID')",
            name="ck_inventory_movements_type",
        ),
        CheckConstraint("quantity_after >= 0", name="ck_inventory_movements_after_nonnegative"),
        CheckConstraint(
            "round(quantity_after, 3) = round(quantity_before + quantity_delta, 3)",
            name="ck_inventory_movements_quantity_equation",
        ),
        CheckConstraint("unit_cost IS NULL OR unit_cost >= 0", name="ck_inventory_movements_unit_cost"),
        Index("ix_inventory_movements_product_created", "product_id", "created_at"),
        Index("ix_inventory_movements_business_created", "business_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    business_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
    )
    product_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False
    )
    movement_type: Mapped[InventoryMovementType] = mapped_column(
        Enum(InventoryMovementType, native_enum=False, create_constraint=False, length=24), nullable=False
    )
    quantity_delta: Mapped[Decimal] = mapped_column(Numeric(18, 3), nullable=False)
    quantity_before: Mapped[Decimal] = mapped_column(Numeric(18, 3), nullable=False)
    quantity_after: Mapped[Decimal] = mapped_column(Numeric(18, 3), nullable=False)
    unit_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    reference_type: Mapped[str | None] = mapped_column(String(80))
    reference_id: Mapped[UUID | None] = mapped_column(Uuid)
    reason: Mapped[str | None] = mapped_column(Text)
    performed_by_user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    client_operation_id: Mapped[UUID | None] = mapped_column(Uuid)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utc_now)

    product = relationship("Product", back_populates="inventory_movements")
    performed_by = relationship("User")
