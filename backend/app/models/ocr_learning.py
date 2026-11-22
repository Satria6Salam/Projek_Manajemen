"""Belajar dari koreksi pengguna pada hasil pindai struk.

OcrCorrection = kamus koreksi per pengguna:
  - kind "merchant": nama toko hasil OCR -> nama toko yang benar,
  - kind "item": nama barang hasil OCR di toko tertentu -> nama barang yang benar.
  Dipakai otomatis pada pindai berikutnya.

ScanFeedback = struk yang sudah dikoreksi pengguna (teks OCR + hasil parser + hasil akhir).
  Menjadi data uji nyata untuk mengukur & menjaga akurasi parser (scripts/feedback_eval.py).
"""
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.timeutils import utcnow
from app.db.session import Base


class OcrCorrection(Base):
    __tablename__ = "ocr_corrections"
    __table_args__ = (UniqueConstraint("user_id", "kind", "scope", "ocr_key", name="uq_ocr_correction"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)  # merchant | item
    # Untuk "item": nama toko (dinormalkan) tempat koreksi terjadi; "" = berlaku di semua toko.
    scope: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    ocr_key: Mapped[str] = mapped_column(String(255), nullable=False)
    corrected: Mapped[str] = mapped_column(String(255), nullable=False)
    hits: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)


class ScanFeedback(Base):
    __tablename__ = "scan_feedback"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    receipt_id: Mapped[int | None] = mapped_column(ForeignKey("receipts.id", ondelete="SET NULL"), nullable=True)
    raw_text: Mapped[str] = mapped_column(Text, nullable=False)
    parsed_json: Mapped[str] = mapped_column(Text, nullable=False)  # hasil parser saat pindai
    final_json: Mapped[str] = mapped_column(Text, nullable=False)  # hasil setelah dikoreksi pengguna
    changed_fields: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
