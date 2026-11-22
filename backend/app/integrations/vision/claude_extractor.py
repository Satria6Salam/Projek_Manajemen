"""Membaca struk langsung dari foto dengan Claude (model vision) lewat Claude API.

Berbeda dengan OCR biasa (Tesseract / ML Kit) yang hanya mengubah piksel menjadi huruf
lalu ditebak strukturnya oleh parser, model vision membaca struk seperti manusia:
memahami tata letak, tulisan pudar, kertas terlipat, dan konteks (mis. "1|ù10" = "1x10").
Hasilnya langsung terstruktur (toko, alamat, tanggal, barang, total) sesuai skema JSON.

Aktif bila kredensial Anthropic tersedia (ANTHROPIC_API_KEY) dan VISION_EXTRACTION=claude.
Bila gagal / tidak dikonfigurasi, pemanggil memakai Tesseract + parser seperti biasa.
"""
from __future__ import annotations

import base64
import io
import json
import logging
import os
from datetime import datetime

from PIL import Image, ImageOps
from pydantic import BaseModel, ValidationError

from app.integrations.parser.base import ParsedItem, ParsedReceipt

logger = logging.getLogger("strukku")

# Sisi terpanjang gambar yang dikirim: cukup tajam untuk tulisan struk, hemat token.
MAX_SIDE = 1568

PROMPT = """Kamu membaca foto struk belanja Indonesia. Salin data PERSIS seperti tercetak.

Aturan:
- Angka rupiah memakai titik/koma sebagai pemisah ribuan: "38.000" = 38000, "12,500" = 12500.
  Desimal ",00" diabaikan ("5.000,00" = 5000).
- quantity = jumlah barang (mis. "x5" atau kolom Qty); unit_price = harga satuan ("@1.000");
  line_total = harga total baris. Bila struk hanya mencetak satu harga, isi line_total.
- Nama barang boleh terpotong ke baris berikutnya: gabungkan menjadi satu nama.
  Perbaiki karakter sampah cetakan bila maksudnya jelas (mis. "1|ù10" -> "1x10").
- Jangan memasukkan baris subtotal, total, pajak, diskon, bayar, kembali sebagai barang.
- transaction_date format YYYY-MM-DD, transaction_time HH:MM (24 jam). Tahun 2 digit "26" = 2026.
- JANGAN MENEBAK. Bila sebuah nilai tidak terbaca, isi null dan sebutkan kolomnya di
  unreadable_fields (mis. "transaction_time", "items[2].unit_price").
- transcription = salinan teks struk baris demi baris (untuk arsip).
"""

SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "merchant_name", "merchant_address", "transaction_date", "transaction_time", "items",
        "subtotal", "discount", "tax_and_charges", "total", "payment_method", "amount_paid",
        "change", "unreadable_fields", "transcription",
    ],
    "properties": {
        "merchant_name": {"type": ["string", "null"]},
        "merchant_address": {"type": ["string", "null"]},
        "transaction_date": {"type": ["string", "null"], "description": "YYYY-MM-DD"},
        "transaction_time": {"type": ["string", "null"], "description": "HH:MM"},
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["name", "quantity", "unit_price", "line_total"],
                "properties": {
                    "name": {"type": "string"},
                    "quantity": {"type": "integer"},
                    "unit_price": {"type": ["number", "null"]},
                    "line_total": {"type": ["number", "null"]},
                },
            },
        },
        "subtotal": {"type": ["number", "null"]},
        "discount": {"type": ["number", "null"]},
        "tax_and_charges": {"type": ["number", "null"]},
        "total": {"type": ["number", "null"]},
        "payment_method": {"type": ["string", "null"]},
        "amount_paid": {"type": ["number", "null"]},
        "change": {"type": ["number", "null"]},
        "unreadable_fields": {"type": "array", "items": {"type": "string"}},
        "transcription": {"type": "string"},
    },
}


class ExtractedItem(BaseModel):
    name: str
    quantity: int
    unit_price: float | None
    line_total: float | None


class ReceiptExtraction(BaseModel):
    merchant_name: str | None
    merchant_address: str | None
    transaction_date: str | None
    transaction_time: str | None
    items: list[ExtractedItem]
    subtotal: float | None
    discount: float | None
    tax_and_charges: float | None
    total: float | None
    payment_method: str | None
    amount_paid: float | None
    change: float | None
    unreadable_fields: list[str]
    transcription: str


def encode_image(image: Image.Image) -> str:
    image = ImageOps.exif_transpose(image).convert("RGB")
    image.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    buf = io.BytesIO()
    image.save(buf, format="JPEG", quality=88)
    return base64.standard_b64encode(buf.getvalue()).decode("ascii")


def to_parsed(data: ReceiptExtraction) -> ParsedReceipt:
    when = None
    if data.transaction_date:
        try:
            when = datetime.strptime(
                f"{data.transaction_date} {data.transaction_time or '00:00'}"[:16], "%Y-%m-%d %H:%M"
            )
        except ValueError:
            try:
                when = datetime.strptime(data.transaction_date[:10], "%Y-%m-%d")
            except ValueError:
                when = None
    items = []
    for it in data.items:
        qty = max(it.quantity or 1, 1)
        total = it.line_total
        if total is None and it.unit_price is not None:
            total = it.unit_price * qty
        unit = it.unit_price if it.unit_price is not None else (total / qty if total is not None else None)
        items.append(ParsedItem(name=it.name.strip()[:255], price=total, quantity=qty, unit_price=unit))
    return ParsedReceipt(
        merchant_name=(data.merchant_name or "").strip() or None,
        merchant_address=(data.merchant_address or "").strip() or None,
        transaction_date=when,
        total_amount=data.total,
        items=items,
        subtotal_amount=data.subtotal,
        discount_amount=abs(data.discount or 0.0),
        has_charges=bool(data.tax_and_charges),
    )


class ClaudeReceiptExtractor:
    """Ekstraksi struk dengan Claude vision. `extract` mengembalikan None bila gagal."""

    label = "Claude (vision)"

    def __init__(self, model: str, effort: str = "medium", timeout: float = 60.0, api_key: str = ""):
        self.api_key = api_key
        self.model = model
        self.effort = effort
        self.timeout = timeout
        self._client = None

    def configured(self) -> bool:
        return bool(self.api_key or os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN"))

    def _get_client(self):
        if self._client is None:
            import anthropic  # impor di sini: server tetap jalan walau paket belum terpasang

            kwargs = {"api_key": self.api_key} if self.api_key else {}
            self._client = anthropic.Anthropic(timeout=self.timeout, max_retries=2, **kwargs)
        return self._client

    def extract(self, image: Image.Image) -> tuple[ParsedReceipt, ReceiptExtraction] | None:
        import anthropic

        try:
            response = self._get_client().beta.messages.create(
                model=self.model,
                max_tokens=16000,
                # Penolakan oleh pengaman (sangat jarang untuk struk) dialihkan otomatis ke
                # model cadangan yang sesuai, tanpa perlu permintaan ulang.
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
                output_config={
                    "effort": self.effort,
                    "format": {"type": "json_schema", "schema": SCHEMA},
                },
                messages=[{
                    "role": "user",
                    "content": [
                        {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                                     "data": encode_image(image)}},
                        {"type": "text", "text": PROMPT},
                    ],
                }],
            )
        except anthropic.AuthenticationError:
            logger.error("Claude vision: kredensial Anthropic tidak valid; memakai OCR biasa")
            return None
        except anthropic.RateLimitError:
            logger.warning("Claude vision: batas laju tercapai; memakai OCR biasa")
            return None
        except anthropic.APIStatusError as exc:
            logger.warning("Claude vision: error API %s; memakai OCR biasa", exc.status_code)
            return None
        except anthropic.APIConnectionError:
            logger.warning("Claude vision: tidak terhubung ke Claude API; memakai OCR biasa")
            return None

        if response.stop_reason in ("refusal", "max_tokens"):
            logger.warning("Claude vision: berhenti (%s); memakai OCR biasa", response.stop_reason)
            return None
        text = next((b.text for b in response.content if b.type == "text"), "")
        try:
            data = ReceiptExtraction.model_validate(json.loads(text))
        except (json.JSONDecodeError, ValidationError):
            logger.warning("Claude vision: keluaran tidak sesuai skema; memakai OCR biasa")
            return None
        return to_parsed(data), data
