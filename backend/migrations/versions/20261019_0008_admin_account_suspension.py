"""Add independent platform-admin suspension metadata for users, businesses and memberships.

Revision ID: 20261019_0008
Revises: 20260903_0007
Create Date: 2026-10-19

This migration only adds nullable metadata. Application authorization must check
suspended_at separately; this migration does not itself enforce access rules.
"""

from typing import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20261019_0008"
down_revision: str | None = "20260903_0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    for table in ("users", "businesses", "business_memberships"):
        op.add_column(table, sa.Column("suspended_at", sa.DateTime(timezone=True), nullable=True))
        op.add_column(table, sa.Column("suspension_reason", sa.Text(), nullable=True))
        op.add_column(table, sa.Column("suspended_by_user_id", sa.Uuid(), nullable=True))
        op.create_foreign_key(
            f"fk_{table}_suspended_by_user_id_users",
            table,
            "users",
            ["suspended_by_user_id"],
            ["id"],
            ondelete="SET NULL",
        )


def downgrade() -> None:
    bind = op.get_bind()
    for table in ("users", "businesses", "business_memberships"):
        active_suspensions = bind.execute(
            sa.text(f"SELECT COUNT(*) FROM {table} WHERE suspended_at IS NOT NULL")
        ).scalar_one()
        if active_suspensions:
            raise RuntimeError(
                f"Cannot downgrade account suspension migration: {table} "
                "contains suspended records. Resolve them before downgrading."
            )
    for table in ("business_memberships", "businesses", "users"):
        op.drop_constraint(f"fk_{table}_suspended_by_user_id_users", table, type_="foreignkey")
        op.drop_column(table, "suspended_by_user_id")
        op.drop_column(table, "suspension_reason")
        op.drop_column(table, "suspended_at")
