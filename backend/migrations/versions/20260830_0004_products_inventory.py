"""Add products and append-only inventory movements.

Revision ID: 20260830_0004
Revises: 20260830_0003
Create Date: 2026-08-30
"""

from typing import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260830_0004"
down_revision: str | None = "20260830_0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "products",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("sku", sa.String(80), nullable=True),
        sa.Column("barcode", sa.String(120), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("cost_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("selling_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("stock_quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("low_stock_threshold", sa.Numeric(18, 3), nullable=False),
        sa.Column("track_inventory", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("length(trim(name)) > 0", name="ck_products_name_nonempty"),
        sa.CheckConstraint("cost_price >= 0", name="ck_products_cost_nonnegative"),
        sa.CheckConstraint("selling_price >= 0", name="ck_products_selling_nonnegative"),
        sa.CheckConstraint("stock_quantity >= 0", name="ck_products_stock_nonnegative"),
        sa.CheckConstraint("low_stock_threshold >= 0", name="ck_products_threshold_nonnegative"),
        sa.CheckConstraint("track_inventory OR (stock_quantity = 0 AND low_stock_threshold = 0)", name="ck_products_service_has_no_stock"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "sku", name="uq_products_business_sku"),
        sa.UniqueConstraint("business_id", "barcode", name="uq_products_business_barcode"),
    )
    op.create_index("ix_products_business_active_name", "products", ["business_id", "is_active", "name"])
    op.create_index("ix_products_business_stock", "products", ["business_id", "track_inventory", "stock_quantity"])

    movement_type = sa.Enum("OPENING_STOCK", "STOCK_ADDED", "MANUAL_ADJUSTMENT", "DAMAGED", "LOST", native_enum=False, create_constraint=False, length=24)
    op.create_table(
        "inventory_movements",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("movement_type", movement_type, nullable=False),
        sa.Column("quantity_delta", sa.Numeric(18, 3), nullable=False),
        sa.Column("quantity_before", sa.Numeric(18, 3), nullable=False),
        sa.Column("quantity_after", sa.Numeric(18, 3), nullable=False),
        sa.Column("unit_cost", sa.Numeric(12, 2), nullable=True),
        sa.Column("reference_type", sa.String(80), nullable=True),
        sa.Column("reference_id", sa.Uuid(), nullable=True),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("performed_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("movement_type IN ('OPENING_STOCK', 'STOCK_ADDED', 'MANUAL_ADJUSTMENT', 'DAMAGED', 'LOST')", name="ck_inventory_movements_type"),
        sa.CheckConstraint("quantity_after >= 0", name="ck_inventory_movements_after_nonnegative"),
        sa.CheckConstraint("quantity_after = quantity_before + quantity_delta", name="ck_inventory_movements_quantity_equation"),
        sa.CheckConstraint("unit_cost IS NULL OR unit_cost >= 0", name="ck_inventory_movements_unit_cost"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["performed_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "client_operation_id", name="uq_inventory_movements_business_operation"),
    )
    op.create_index("ix_inventory_movements_product_created", "inventory_movements", ["product_id", "created_at"])
    op.create_index("ix_inventory_movements_business_created", "inventory_movements", ["business_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_inventory_movements_business_created", table_name="inventory_movements")
    op.drop_index("ix_inventory_movements_product_created", table_name="inventory_movements")
    op.drop_table("inventory_movements")
    op.drop_index("ix_products_business_stock", table_name="products")
    op.drop_index("ix_products_business_active_name", table_name="products")
    op.drop_table("products")
