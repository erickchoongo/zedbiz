import hashlib
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Index, Numeric, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.mixins import TimestampMixin


class Product(TimestampMixin, Base):
    @property
    def sale_version(self) -> str:
        """Content token for sale-critical state; excludes stock, cost and cosmetics."""
        value = f"v1:{self.id}:{self.business_id}:{self.selling_price:.2f}:{int(self.track_inventory)}:{int(self.is_active)}"
        return hashlib.sha256(value.encode()).hexdigest()

    __tablename__ = "products"
    __table_args__ = (
        UniqueConstraint("business_id", "sku", name="uq_products_business_sku"),
        UniqueConstraint("business_id", "barcode", name="uq_products_business_barcode"),
        CheckConstraint("length(trim(name)) > 0", name="ck_products_name_nonempty"),
        CheckConstraint("cost_price >= 0", name="ck_products_cost_nonnegative"),
        CheckConstraint("selling_price >= 0", name="ck_products_selling_nonnegative"),
        CheckConstraint("stock_quantity >= 0", name="ck_products_stock_nonnegative"),
        CheckConstraint("low_stock_threshold >= 0", name="ck_products_threshold_nonnegative"),
        CheckConstraint(
            "track_inventory OR (stock_quantity = 0 AND low_stock_threshold = 0)",
            name="ck_products_service_has_no_stock",
        ),
        Index("ix_products_business_active_name", "business_id", "is_active", "name"),
        Index("ix_products_business_stock", "business_id", "track_inventory", "stock_quantity"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    business_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    sku: Mapped[str | None] = mapped_column(String(80))
    barcode: Mapped[str | None] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(Text)
    cost_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0.00"))
    selling_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    stock_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3), nullable=False, default=Decimal("0.000"))
    low_stock_threshold: Mapped[Decimal] = mapped_column(
        Numeric(18, 3), nullable=False, default=Decimal("0.000")
    )
    track_inventory: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")

    business = relationship("Business", back_populates="products")
    inventory_movements = relationship("InventoryMovement", back_populates="product")
