"""Add merchant_address to receipts (alamat toko dari struk).

Revision ID: 0009_merchant_address
Revises: 0008_scan_assets
Create Date: 2026-11-15
"""
from alembic import op
import sqlalchemy as sa

revision = "0009_merchant_address"
down_revision = "0008_scan_assets"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("receipts") as batch:
        batch.add_column(sa.Column("merchant_address", sa.String(length=300), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("receipts") as batch:
        batch.drop_column("merchant_address")
