from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, ForeignKeyConstraint, Index, Numeric, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.time import utc_now
from app.db.base import Base


class SaleItem(Base):
    __tablename__ = "sale_items"
    __table_args__ = (
        ForeignKeyConstraint(["sale_id", "business_id"], ["sales.id", "sales.business_id"], ondelete="CASCADE"),
        CheckConstraint("quantity > 0", name="ck_sale_items_quantity_positive"),
        CheckConstraint("unit_selling_price >= 0", name="ck_sale_items_price_nonnegative"),
        CheckConstraint("unit_cost >= 0", name="ck_sale_items_cost_nonnegative"),
        CheckConstraint("line_subtotal >= 0", name="ck_sale_items_subtotal_nonnegative"),
        CheckConstraint("line_cost >= 0", name="ck_sale_items_line_cost_nonnegative"),
        CheckConstraint("line_profit = line_subtotal - line_cost", name="ck_sale_items_profit_equation"),
        Index("ix_sale_items_sale", "sale_id"),
        Index("ix_sale_items_business_product", "business_id", "product_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    sale_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    business_id: Mapped[UUID] = mapped_column(Uuid, nullable=False)
    product_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False)
    product_name_snapshot: Mapped[str] = mapped_column(String(200), nullable=False)
    sku_snapshot: Mapped[str | None] = mapped_column(String(80))
    track_inventory_snapshot: Mapped[bool] = mapped_column(Boolean, nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3), nullable=False)
    unit_selling_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    line_subtotal: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    line_cost: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    line_profit: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utc_now)

    sale = relationship("Sale", back_populates="items", foreign_keys=[sale_id, business_id])
    product = relationship("Product")
