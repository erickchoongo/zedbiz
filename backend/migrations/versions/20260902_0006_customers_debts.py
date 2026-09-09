"""Add customers, customer-credit debts, and append-only repayments.

Revision ID: 20260902_0006
Revises: 20260830_0005
Create Date: 2026-09-02
"""

from typing import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260902_0006"
down_revision: str | None = "20260830_0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _enum(*values: str, length: int) -> sa.Enum:
    return sa.Enum(*values, native_enum=False, create_constraint=False, length=length)


def upgrade() -> None:
    op.create_table(
        "customers",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("phone_number", sa.String(16), nullable=True),
        sa.Column("email", sa.String(320), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("length(trim(name)) > 0", name="ck_customers_name_nonempty"),
        sa.CheckConstraint(
            "phone_number IS NULL OR "
            "(length(phone_number) BETWEEN 9 AND 16 AND substr(phone_number, 1, 1) = '+')",
            name="ck_customers_phone_e164_shape",
        ),
        sa.CheckConstraint(
            "email IS NULL OR (length(trim(email)) > 0 AND email = lower(trim(email)))",
            name="ck_customers_email_normalized",
        ),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("id", "business_id", name="uq_customers_id_business"),
    )
    op.create_index(
        "ix_customers_business_active_name",
        "customers",
        ["business_id", "is_active", "name"],
    )
    op.create_index(
        "ix_customers_business_phone",
        "customers",
        ["business_id", "phone_number"],
    )
    op.create_index(
        "ix_customers_business_email",
        "customers",
        ["business_id", "email"],
    )

    with op.batch_alter_table("sales") as batch:
        batch.drop_constraint("ck_sales_payment_method", type_="check")
        batch.add_column(sa.Column("customer_id", sa.Uuid(), nullable=True))
        batch.create_foreign_key(
            "fk_sales_customer_business",
            "customers",
            ["customer_id", "business_id"],
            ["id", "business_id"],
            ondelete="RESTRICT",
        )
        batch.create_check_constraint(
            "ck_sales_payment_method",
            "payment_method IN "
            "('CASH', 'MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', "
            "'BANK_TRANSFER', 'OTHER', 'CUSTOMER_DEBT')",
        )
        batch.create_check_constraint(
            "ck_sales_customer_debt_customer",
            "payment_method <> 'CUSTOMER_DEBT' OR customer_id IS NOT NULL",
        )

    op.create_table(
        "debts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=False),
        sa.Column("original_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("amount_paid", sa.Numeric(12, 2), nullable=False),
        sa.Column("outstanding_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column(
            "status",
            _enum("OPEN", "PARTIALLY_PAID", "PAID", "VOIDED", length=24),
            nullable=False,
        ),
        sa.Column("due_date", sa.Date(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("settled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("voided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("voided_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint(
            "status IN ('OPEN', 'PARTIALLY_PAID', 'PAID', 'VOIDED')",
            name="ck_debts_status",
        ),
        sa.CheckConstraint("original_amount > 0", name="ck_debts_original_positive"),
        sa.CheckConstraint("amount_paid >= 0", name="ck_debts_paid_nonnegative"),
        sa.CheckConstraint("outstanding_amount >= 0", name="ck_debts_outstanding_nonnegative"),
        sa.CheckConstraint("amount_paid <= original_amount", name="ck_debts_paid_within_original"),
        sa.CheckConstraint(
            "(status = 'VOIDED' AND round(amount_paid, 2) = 0 "
            "AND round(outstanding_amount, 2) = 0) "
            "OR (status <> 'VOIDED' AND "
            "round(outstanding_amount, 2) = round(original_amount - amount_paid, 2))",
            name="ck_debts_balance_equation",
        ),
        sa.CheckConstraint(
            "(status = 'OPEN' AND round(amount_paid, 2) = 0 "
            "AND round(outstanding_amount, 2) = round(original_amount, 2) "
            "AND settled_at IS NULL AND voided_at IS NULL AND voided_by_user_id IS NULL) "
            "OR (status = 'PARTIALLY_PAID' AND amount_paid > 0 AND outstanding_amount > 0 "
            "AND settled_at IS NULL AND voided_at IS NULL AND voided_by_user_id IS NULL) "
            "OR (status = 'PAID' AND round(amount_paid, 2) = round(original_amount, 2) "
            "AND round(outstanding_amount, 2) = 0 AND settled_at IS NOT NULL "
            "AND voided_at IS NULL AND voided_by_user_id IS NULL) "
            "OR (status = 'VOIDED' AND round(amount_paid, 2) = 0 "
            "AND round(outstanding_amount, 2) = 0 AND settled_at IS NULL "
            "AND voided_at IS NOT NULL AND voided_by_user_id IS NOT NULL)",
            name="ck_debts_status_balance_consistency",
        ),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["customer_id", "business_id"],
            ["customers.id", "customers.business_id"],
            name="fk_debts_customer_business",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["sale_id", "business_id"],
            ["sales.id", "sales.business_id"],
            name="fk_debts_sale_business",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["voided_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "sale_id", name="uq_debts_business_sale"),
        sa.UniqueConstraint("id", "business_id", name="uq_debts_id_business"),
    )
    op.create_index(
        "ix_debts_business_status_due",
        "debts",
        ["business_id", "status", "due_date"],
    )
    op.create_index(
        "ix_debts_business_customer_created",
        "debts",
        ["business_id", "customer_id", "created_at"],
    )

    op.create_table(
        "debt_payments",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("debt_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column(
            "payment_method",
            _enum(
                "CASH",
                "MTN_MONEY",
                "AIRTEL_MONEY",
                "ZAMTEL_MONEY",
                "BANK_TRANSFER",
                "OTHER",
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("payment_reference", sa.String(160), nullable=True),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("request_fingerprint", sa.String(64), nullable=False),
        sa.Column("received_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("amount > 0", name="ck_debt_payments_amount_positive"),
        sa.CheckConstraint(
            "payment_method IN "
            "('CASH', 'MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', 'BANK_TRANSFER', 'OTHER')",
            name="ck_debt_payments_method",
        ),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["debt_id", "business_id"],
            ["debts.id", "debts.business_id"],
            name="fk_debt_payments_debt_business",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["customer_id", "business_id"],
            ["customers.id", "customers.business_id"],
            name="fk_debt_payments_customer_business",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(["received_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "business_id",
            "client_operation_id",
            name="uq_debt_payments_business_operation",
        ),
        sa.UniqueConstraint("id", "business_id", name="uq_debt_payments_id_business"),
    )
    op.create_index(
        "ix_debt_payments_business_debt_paid",
        "debt_payments",
        ["business_id", "debt_id", "paid_at"],
    )
    op.create_index(
        "ix_debt_payments_business_customer_paid",
        "debt_payments",
        ["business_id", "customer_id", "paid_at"],
    )


def downgrade() -> None:
    bind = op.get_bind()
    credit_sale_count = bind.execute(
        sa.text("SELECT count(*) FROM sales WHERE payment_method = 'CUSTOMER_DEBT'")
    ).scalar_one()
    customer_count = bind.execute(sa.text("SELECT count(*) FROM customers")).scalar_one()
    debt_count = bind.execute(sa.text("SELECT count(*) FROM debts")).scalar_one()
    debt_payment_count = bind.execute(sa.text("SELECT count(*) FROM debt_payments")).scalar_one()
    if credit_sale_count or customer_count or debt_count or debt_payment_count:
        raise RuntimeError(
            "Cannot downgrade Milestone 6 while customer-credit data exists. "
            "The downgrade refuses to delete or reinterpret financial history."
        )

    op.drop_index("ix_debt_payments_business_customer_paid", table_name="debt_payments")
    op.drop_index("ix_debt_payments_business_debt_paid", table_name="debt_payments")
    op.drop_table("debt_payments")

    op.drop_index("ix_debts_business_customer_created", table_name="debts")
    op.drop_index("ix_debts_business_status_due", table_name="debts")
    op.drop_table("debts")

    with op.batch_alter_table("sales") as batch:
        batch.drop_constraint("ck_sales_customer_debt_customer", type_="check")
        batch.drop_constraint("ck_sales_payment_method", type_="check")
        batch.drop_constraint("fk_sales_customer_business", type_="foreignkey")
        batch.drop_column("customer_id")
        batch.create_check_constraint(
            "ck_sales_payment_method",
            "payment_method IN "
            "('CASH', 'MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', 'BANK_TRANSFER', 'OTHER')",
        )

    op.drop_index("ix_customers_business_email", table_name="customers")
    op.drop_index("ix_customers_business_phone", table_name="customers")
    op.drop_index("ix_customers_business_active_name", table_name="customers")
    op.drop_table("customers")
