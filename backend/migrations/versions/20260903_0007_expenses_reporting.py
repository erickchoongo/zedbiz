"""Add the immutable expense ledger used by dashboards and reports.

Revision ID: 20260903_0007
Revises: 20260902_0006
Create Date: 2026-09-03
"""

from typing import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260903_0007"
down_revision: str | None = "20260902_0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _enum(*values: str, length: int) -> sa.Enum:
    return sa.Enum(*values, native_enum=False, create_constraint=False, length=length)


def upgrade() -> None:
    op.create_table(
        "expenses",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column(
            "category",
            _enum(
                "STOCK_PURCHASE", "RENT", "UTILITIES", "TRANSPORT", "SALARIES_WAGES",
                "AIRTIME_DATA", "MARKETING", "MAINTENANCE", "EQUIPMENT", "FEES_CHARGES",
                "OTHER", length=32,
            ),
            nullable=False,
        ),
        sa.Column("description", sa.String(240), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column(
            "payment_method",
            _enum(
                "MTN_MONEY", "AIRTEL_MONEY", "ZAMTEL_MONEY", "BANK_TRANSFER", "CASH", "OTHER",
                length=32,
            ),
            nullable=False,
        ),
        sa.Column("payment_reference", sa.String(160), nullable=True),
        sa.Column("expense_date", sa.Date(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("request_fingerprint", sa.String(64), nullable=False),
        sa.Column("recorded_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("status", _enum("RECORDED", "VOIDED", length=16), nullable=False),
        sa.Column("voided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("voided_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("void_reason", sa.Text(), nullable=True),
        sa.Column("void_client_operation_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("amount > 0", name="ck_expenses_amount_positive"),
        sa.CheckConstraint(
            "category IN ('STOCK_PURCHASE', 'RENT', 'UTILITIES', 'TRANSPORT', "
            "'SALARIES_WAGES', 'AIRTIME_DATA', 'MARKETING', 'MAINTENANCE', "
            "'EQUIPMENT', 'FEES_CHARGES', 'OTHER')",
            name="ck_expenses_category",
        ),
        sa.CheckConstraint(
            "payment_method IN ('MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', "
            "'BANK_TRANSFER', 'CASH', 'OTHER')",
            name="ck_expenses_payment_method",
        ),
        sa.CheckConstraint("status IN ('RECORDED', 'VOIDED')", name="ck_expenses_status"),
        sa.CheckConstraint("length(trim(description)) > 0", name="ck_expenses_description_nonblank"),
        sa.CheckConstraint(
            "(status = 'RECORDED' AND voided_at IS NULL AND voided_by_user_id IS NULL "
            "AND void_reason IS NULL AND void_client_operation_id IS NULL) OR "
            "(status = 'VOIDED' AND voided_at IS NOT NULL AND voided_by_user_id IS NOT NULL "
            "AND void_reason IS NOT NULL AND void_client_operation_id IS NOT NULL)",
            name="ck_expenses_void_consistency",
        ),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["recorded_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["voided_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("id", "business_id", name="uq_expenses_id_business"),
        sa.UniqueConstraint("business_id", "client_operation_id", name="uq_expenses_business_operation"),
        sa.UniqueConstraint("business_id", "void_client_operation_id", name="uq_expenses_business_void_operation"),
    )
    op.create_index("ix_expenses_business_date", "expenses", ["business_id", "expense_date"])
    op.create_index(
        "ix_expenses_business_status_date", "expenses", ["business_id", "status", "expense_date"]
    )
    op.create_index(
        "ix_expenses_business_category_date", "expenses", ["business_id", "category", "expense_date"]
    )
    op.create_index(
        "ix_expenses_business_payment_date", "expenses", ["business_id", "payment_method", "expense_date"]
    )
    op.create_index(
        "ix_expenses_business_recorder_date", "expenses", ["business_id", "recorded_by_user_id", "expense_date"]
    )


def downgrade() -> None:
    bind = op.get_bind()
    expense_count = bind.execute(sa.text("SELECT count(*) FROM expenses")).scalar_one()
    if expense_count:
        raise RuntimeError(
            "Cannot downgrade Milestone 7 while expense data exists. "
            "The downgrade refuses to delete financial history."
        )
    op.drop_index("ix_expenses_business_recorder_date", table_name="expenses")
    op.drop_index("ix_expenses_business_payment_date", table_name="expenses")
    op.drop_index("ix_expenses_business_category_date", table_name="expenses")
    op.drop_index("ix_expenses_business_status_date", table_name="expenses")
    op.drop_index("ix_expenses_business_date", table_name="expenses")
    op.drop_table("expenses")
