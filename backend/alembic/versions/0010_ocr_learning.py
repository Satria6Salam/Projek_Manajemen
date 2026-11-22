"""Belajar dari koreksi pengguna: kamus koreksi OCR, data umpan balik, snapshot OCR.

Revision ID: 0010_ocr_learning
Revises: 0009_merchant_address
Create Date: 2026-11-22
"""
from alembic import op
import sqlalchemy as sa

revision = "0010_ocr_learning"
down_revision = "0009_merchant_address"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("scan_assets") as batch:
        batch.add_column(sa.Column("ocr_snapshot", sa.Text(), nullable=True))
    op.create_table(
        "ocr_corrections",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("scope", sa.String(length=200), nullable=False, server_default=""),
        sa.Column("ocr_key", sa.String(length=255), nullable=False),
        sa.Column("corrected", sa.String(length=255), nullable=False),
        sa.Column("hits", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("user_id", "kind", "scope", "ocr_key", name="uq_ocr_correction"),
    )
    op.create_index("ix_ocr_corrections_user_id", "ocr_corrections", ["user_id"])
    op.create_table(
        "scan_feedback",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("receipt_id", sa.Integer(), sa.ForeignKey("receipts.id", ondelete="SET NULL"), nullable=True),
        sa.Column("raw_text", sa.Text(), nullable=False),
        sa.Column("parsed_json", sa.Text(), nullable=False),
        sa.Column("final_json", sa.Text(), nullable=False),
        sa.Column("changed_fields", sa.String(length=200), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_scan_feedback_user_id", "scan_feedback", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_scan_feedback_user_id", table_name="scan_feedback")
    op.drop_table("scan_feedback")
    op.drop_index("ix_ocr_corrections_user_id", table_name="ocr_corrections")
    op.drop_table("ocr_corrections")
    with op.batch_alter_table("scan_assets") as batch:
        batch.drop_column("ocr_snapshot")
