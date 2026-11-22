from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.timeutils import utcnow
from app.db.session import Base


class ScanAsset(Base):
    __tablename__ = "scan_assets"
    __table_args__ = (
        Index("ix_scan_assets_expires_at_owner_id", "expires_at", "owner_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    storage_key: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
    # Hasil OCR + parser saat pindai (JSON); dibandingkan dengan hasil koreksi pengguna saat disimpan.
    ocr_snapshot: Mapped[str | None] = mapped_column(Text, nullable=True)
