"""Add atomic sales, immutable sale items, numbering counters, and sale movements.

Revision ID: 20260830_0005
Revises: 20260830_0004
Create Date: 2026-08-30
"""

from typing import Sequence
from uuid import UUID

import sqlalchemy as sa
from alembic import op

revision: str = "20260830_0005"
down_revision: str | None = "20260830_0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _enum(*values: str, length: int) -> sa.Enum:
    return sa.Enum(*values, native_enum=False, create_constraint=False, length=length)


def upgrade() -> None:
    with op.batch_alter_table("inventory_movements") as batch:
        batch.drop_constraint("ck_inventory_movements_type", type_="check")
        batch.drop_constraint("ck_inventory_movements_quantity_equation", type_="check")
        batch.create_check_constraint(
            "ck_inventory_movements_type",
            "movement_type IN ('OPENING_STOCK', 'STOCK_ADDED', 'MANUAL_ADJUSTMENT', 'DAMAGED', 'LOST', 'SALE', 'SALE_VOID')",
        )
        batch.create_check_constraint(
            "ck_inventory_movements_quantity_equation",
            "round(quantity_after, 3) = round(quantity_before + quantity_delta, 3)",
        )

    op.create_table(
        "sale_counters",
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("next_value", sa.Integer(), nullable=False),
        sa.CheckConstraint("next_value > 0", name="ck_sale_counters_next_positive"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("business_id"),
    )
    bind = op.get_bind()
    business_ids = [UUID(str(row[0])) for row in bind.execute(sa.text("SELECT id FROM businesses"))]
    counter = sa.table("sale_counters", sa.column("business_id", sa.Uuid()), sa.column("next_value", sa.Integer()))
    if business_ids:
        op.bulk_insert(counter, [{"business_id": business_id, "next_value": 1} for business_id in business_ids])

    op.create_table(
        "sales",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("sale_number", sa.String(32), nullable=False),
        sa.Column("status", _enum("COMPLETED", "VOIDED", length=16), nullable=False),
        sa.Column("subtotal", sa.Numeric(12, 2), nullable=False),
        sa.Column("discount_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("total_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("total_cost", sa.Numeric(12, 2), nullable=False),
        sa.Column("gross_profit", sa.Numeric(12, 2), nullable=False),
        sa.Column("payment_method", _enum("CASH", "MTN_MONEY", "AIRTEL_MONEY", "ZAMTEL_MONEY", "BANK_TRANSFER", "OTHER", length=24), nullable=False),
        sa.Column("payment_reference", sa.String(160), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("request_fingerprint", sa.String(64), nullable=False),
        sa.Column("sold_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("sold_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("voided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("voided_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("void_reason", sa.Text(), nullable=True),
        sa.Column("void_client_operation_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("status IN ('COMPLETED', 'VOIDED')", name="ck_sales_status"),
        sa.CheckConstraint("payment_method IN ('CASH', 'MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', 'BANK_TRANSFER', 'OTHER')", name="ck_sales_payment_method"),
        sa.CheckConstraint("subtotal >= 0", name="ck_sales_subtotal_nonnegative"),
        sa.CheckConstraint("discount_amount >= 0", name="ck_sales_discount_nonnegative"),
        sa.CheckConstraint("discount_amount <= subtotal", name="ck_sales_discount_within_subtotal"),
        sa.CheckConstraint("total_amount = subtotal - discount_amount", name="ck_sales_total_equation"),
        sa.CheckConstraint("total_cost >= 0", name="ck_sales_cost_nonnegative"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sold_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["voided_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "sale_number", name="uq_sales_business_number"),
        sa.UniqueConstraint("business_id", "client_operation_id", name="uq_sales_business_operation"),
        sa.UniqueConstraint("business_id", "void_client_operation_id", name="uq_sales_business_void_operation"),
        sa.UniqueConstraint("id", "business_id", name="uq_sales_id_business"),
    )
    op.create_index("ix_sales_business_sold_at", "sales", ["business_id", "sold_at"])
    op.create_index("ix_sales_business_status_sold", "sales", ["business_id", "status", "sold_at"])
    op.create_index("ix_sales_business_payment_sold", "sales", ["business_id", "payment_method", "sold_at"])

    op.create_table(
        "sale_items",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("product_name_snapshot", sa.String(200), nullable=False),
        sa.Column("sku_snapshot", sa.String(80), nullable=True),
        sa.Column("track_inventory_snapshot", sa.Boolean(), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("unit_selling_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("unit_cost", sa.Numeric(12, 2), nullable=False),
        sa.Column("line_subtotal", sa.Numeric(12, 2), nullable=False),
        sa.Column("line_cost", sa.Numeric(12, 2), nullable=False),
        sa.Column("line_profit", sa.Numeric(12, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_sale_items_quantity_positive"),
        sa.CheckConstraint("unit_selling_price >= 0", name="ck_sale_items_price_nonnegative"),
        sa.CheckConstraint("unit_cost >= 0", name="ck_sale_items_cost_nonnegative"),
        sa.CheckConstraint("line_subtotal >= 0", name="ck_sale_items_subtotal_nonnegative"),
        sa.CheckConstraint("line_cost >= 0", name="ck_sale_items_line_cost_nonnegative"),
        sa.CheckConstraint("line_profit = line_subtotal - line_cost", name="ck_sale_items_profit_equation"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["sale_id", "business_id"], ["sales.id", "sales.business_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_sale_items_sale", "sale_items", ["sale_id"])
    op.create_index("ix_sale_items_business_product", "sale_items", ["business_id", "product_id"])


def downgrade() -> None:
    op.drop_index("ix_sale_items_business_product", table_name="sale_items")
    op.drop_index("ix_sale_items_sale", table_name="sale_items")
    op.drop_table("sale_items")
    op.drop_index("ix_sales_business_payment_sold", table_name="sales")
    op.drop_index("ix_sales_business_status_sold", table_name="sales")
    op.drop_index("ix_sales_business_sold_at", table_name="sales")
    op.drop_table("sales")
    op.drop_table("sale_counters")
    op.execute("DELETE FROM inventory_movements WHERE movement_type IN ('SALE', 'SALE_VOID')")
    with op.batch_alter_table("inventory_movements") as batch:
        batch.drop_constraint("ck_inventory_movements_type", type_="check")
        batch.drop_constraint("ck_inventory_movements_quantity_equation", type_="check")
        batch.create_check_constraint(
            "ck_inventory_movements_type",
            "movement_type IN ('OPENING_STOCK', 'STOCK_ADDED', 'MANUAL_ADJUSTMENT', 'DAMAGED', 'LOST')",
        )
        batch.create_check_constraint(
            "ck_inventory_movements_quantity_equation",
            "quantity_after = quantity_before + quantity_delta",
        )
