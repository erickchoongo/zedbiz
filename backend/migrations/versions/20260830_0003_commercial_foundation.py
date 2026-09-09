"""Add onboarding, subscriptions, payments, and audit logs.

Revision ID: 20260830_0003
Revises: 20260829_0002
Create Date: 2026-08-30
"""

from datetime import UTC, datetime
from typing import Sequence
from uuid import uuid4

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260830_0003"
down_revision: str | None = "20260829_0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _enum(*values: str, length: int) -> sa.Enum:
    return sa.Enum(*values, native_enum=False, create_constraint=False, length=length)


def upgrade() -> None:
    op.create_table(
        "subscription_plans",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("code", sa.String(length=32), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("price", sa.Numeric(precision=12, scale=2), nullable=False),
        sa.Column("billing_period", _enum("MONTHLY", length=16), nullable=False),
        sa.Column("grace_period_days", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("billing_period IN ('MONTHLY')", name="ck_subscription_plans_billing_period"),
        sa.CheckConstraint("grace_period_days >= 0", name="ck_subscription_plans_grace_nonnegative"),
        sa.CheckConstraint("price >= 0", name="ck_subscription_plans_price_nonnegative"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("code", name="uq_subscription_plans_code"),
    )
    op.create_index("ix_subscription_plans_code", "subscription_plans", ["code"], unique=False)

    op.create_table(
        "onboarding_records",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("fee_amount", sa.Numeric(precision=12, scale=2), nullable=False),
        sa.Column("currency", sa.String(length=3), server_default="ZMW", nullable=False),
        sa.Column("payment_status", _enum("UNPAID", "PAID", "WAIVED", length=16), server_default="UNPAID", nullable=False),
        sa.Column("payment_method", _enum("MTN_MONEY", "AIRTEL_MONEY", "ZAMTEL_MONEY", "BANK_TRANSFER", "CASH", "OTHER", length=24), nullable=True),
        sa.Column("payment_reference", sa.String(length=160), nullable=True),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("onboarding_status", _enum("NOT_STARTED", "IN_PROGRESS", "COMPLETED", "CANCELLED", length=20), server_default="NOT_STARTED", nullable=False),
        sa.Column("assigned_admin_user_id", sa.Uuid(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("fee_amount >= 0", name="ck_onboarding_records_fee_nonnegative"),
        sa.CheckConstraint("onboarding_status IN ('NOT_STARTED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')", name="ck_onboarding_status"),
        sa.CheckConstraint("payment_status IN ('UNPAID', 'PAID', 'WAIVED')", name="ck_onboarding_payment_status"),
        sa.ForeignKeyConstraint(["assigned_admin_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", name="uq_onboarding_records_business"),
    )

    op.create_table(
        "subscriptions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("plan_id", sa.Uuid(), nullable=False),
        sa.Column("status", _enum("PENDING", "ACTIVE", "GRACE_PERIOD", "EXPIRED", "CANCELLED", length=20), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("current_period_start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("current_period_end", sa.DateTime(timezone=True), nullable=False),
        sa.Column("grace_ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("current_period_end > current_period_start", name="ck_subscriptions_period_order"),
        sa.CheckConstraint("grace_ends_at >= current_period_end", name="ck_subscriptions_grace_order"),
        sa.CheckConstraint("status IN ('PENDING', 'ACTIVE', 'GRACE_PERIOD', 'EXPIRED', 'CANCELLED')", name="ck_subscriptions_status"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["plan_id"], ["subscription_plans.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", name="uq_subscriptions_business"),
    )
    op.create_index("ix_subscriptions_status_period_end", "subscriptions", ["status", "current_period_end"], unique=False)

    op.create_table(
        "subscription_payments",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("subscription_id", sa.Uuid(), nullable=False),
        sa.Column("amount", sa.Numeric(precision=12, scale=2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("payment_method", _enum("MTN_MONEY", "AIRTEL_MONEY", "ZAMTEL_MONEY", "BANK_TRANSFER", "CASH", "OTHER", length=24), nullable=False),
        sa.Column("payment_reference", sa.String(length=160), nullable=False),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("period_start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("period_end", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recorded_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("amount > 0", name="ck_subscription_payments_amount_positive"),
        sa.CheckConstraint("payment_method IN ('MTN_MONEY', 'AIRTEL_MONEY', 'ZAMTEL_MONEY', 'BANK_TRANSFER', 'CASH', 'OTHER')", name="ck_subscription_payments_method"),
        sa.CheckConstraint("period_end > period_start", name="ck_subscription_payments_period_order"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["recorded_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["subscription_id"], ["subscriptions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("payment_method", "payment_reference", name="uq_subscription_payments_reference"),
    )
    op.create_index("ix_subscription_payments_business_paid", "subscription_payments", ["business_id", "paid_at"], unique=False)

    bind = op.get_bind()
    metadata_type = postgresql.JSONB() if bind.dialect.name == "postgresql" else sa.JSON()
    op.create_table(
        "audit_logs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("actor_user_id", sa.Uuid(), nullable=True),
        sa.Column("business_id", sa.Uuid(), nullable=True),
        sa.Column("action", sa.String(length=100), nullable=False),
        sa.Column("entity_type", sa.String(length=80), nullable=False),
        sa.Column("entity_id", sa.Uuid(), nullable=True),
        sa.Column("metadata", metadata_type, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["actor_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_audit_logs_actor_created", "audit_logs", ["actor_user_id", "created_at"], unique=False)
    op.create_index("ix_audit_logs_business_created", "audit_logs", ["business_id", "created_at"], unique=False)

    now = datetime.now(UTC)
    onboarding = sa.table(
        "onboarding_records",
        sa.column("id", sa.Uuid()), sa.column("business_id", sa.Uuid()),
        sa.column("fee_amount", sa.Numeric(12, 2)), sa.column("currency", sa.String()),
        sa.column("payment_status", sa.String()), sa.column("onboarding_status", sa.String()),
        sa.column("created_at", sa.DateTime(timezone=True)), sa.column("updated_at", sa.DateTime(timezone=True)),
    )
    business_ids = [row[0] for row in bind.execute(sa.text("SELECT id FROM businesses"))]
    if business_ids:
        op.bulk_insert(
            onboarding,
            [
                {
                    "id": uuid4(), "business_id": business_id, "fee_amount": "200.00", "currency": "ZMW",
                    "payment_status": "UNPAID", "onboarding_status": "NOT_STARTED",
                    "created_at": now, "updated_at": now,
                }
                for business_id in business_ids
            ],
        )


def downgrade() -> None:
    op.drop_index("ix_audit_logs_business_created", table_name="audit_logs")
    op.drop_index("ix_audit_logs_actor_created", table_name="audit_logs")
    op.drop_table("audit_logs")
    op.drop_index("ix_subscription_payments_business_paid", table_name="subscription_payments")
    op.drop_table("subscription_payments")
    op.drop_index("ix_subscriptions_status_period_end", table_name="subscriptions")
    op.drop_table("subscriptions")
    op.drop_table("onboarding_records")
    op.drop_index("ix_subscription_plans_code", table_name="subscription_plans")
    op.drop_table("subscription_plans")
