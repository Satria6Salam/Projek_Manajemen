"""Memilih bacaan OCR terbaik berdasarkan hasil parsing, lalu menilai keyakinannya.

Ada beberapa sumber bacaan untuk satu foto:
- Tesseract di server (foto asli, foto diperjelas, dan mode baca lain bila perlu),
- teks Google ML Kit yang sudah dibaca di HP (dikirim aplikasi bersama foto).
Bacaan dengan keyakinan OCR tertinggi belum tentu yang paling benar, jadi setiap
bacaan di-parse lalu dinilai: berapa barang berharga yang terbaca, apakah total,
tanggal, dan nama toko ditemukan, dan apakah jumlah harga barang cocok dengan
subtotal/total struk (tanda paling kuat bahwa angka-angkanya terbaca benar).

Hasil akhirnya juga diberi tingkat keyakinan per kolom (tinggi/sedang/rendah)
supaya aplikasi bisa menandai bagian yang perlu dicek pengguna, alih-alih
menampilkan angka yang salah tanpa tanda.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from PIL import Image

from app.integrations.ocr.base import OCREngine, OcrCandidate, OcrResult
from app.integrations.parser.base import ParsedReceipt, ReceiptParser

MAX_DEVICE_TEXT = 20_000
HIGH, MEDIUM, LOW = "tinggi", "sedang", "rendah"


@dataclass
class ReceiptReading:
    parsed: ParsedReceipt
    raw_text: str
    ocr: OcrResult
    label: str = ""
    consistent: bool = False
    confidence: dict[str, str] = field(default_factory=dict)
    review_fields: list[str] = field(default_factory=list)


def plausibility(parsed: ParsedReceipt) -> float:
    priced = [i for i in parsed.items if i.price is not None]
    score = 2.0 * min(len(priced), 25)
    if parsed.total_amount is not None:
        score += 4
    if parsed.transaction_date is not None:
        score += 2
    if parsed.merchant_name:
        score += 1
    if priced:
        items_sum = sum(i.price for i in priced)
        targets = [t for t in (parsed.subtotal_amount, parsed.total_amount) if t is not None]
        if parsed.total_amount is not None:
            targets.append(parsed.total_amount + parsed.discount_amount)
        if any(abs(items_sum - t) < 1 for t in targets):
            score += 10
        elif parsed.total_amount is not None and items_sum > parsed.total_amount * 1.5 and not parsed.has_charges:
            score -= 4  # barang "berlebih": kemungkinan angka/baris sampah ikut terbaca
    # Koreksi otomatis berarti ada angka yang tadinya tidak konsisten.
    score -= 0.5 * len(parsed.corrections)
    return score


def _repair_names(parsed: ParsedReceipt) -> None:
    """Pulihkan huruf yang hilang pada nama barang ("ula Pasir" -> "Gula Pasir")."""
    from app.integrations.providers import get_normalizer  # hindari impor melingkar

    repairer = getattr(get_normalizer(), "repairer", None)
    if repairer is None:
        return
    for item in parsed.items:
        fixed = repairer.repair_display(item.name)
        if fixed != item.name:
            item.name = fixed
            item.name_corrected = True


def is_consistent(parsed: ParsedReceipt) -> bool:
    """Jumlah harga barang sama dengan subtotal/total -> angka hampir pasti terbaca benar."""
    priced = [i.price for i in parsed.items if i.price is not None]
    if not priced or parsed.total_amount is None:
        return False
    s = sum(priced)
    targets = [parsed.total_amount, parsed.total_amount + parsed.discount_amount]
    if parsed.subtotal_amount is not None:
        targets.append(parsed.subtotal_amount)
    return any(abs(s - t) < 1 for t in targets)


_PRICE_IN_NAME = re.compile(r"\d[.,]\d{3}|^\d+\s+\d+\s|[.,]\s?[a-z]\d\b", re.I)


def mark_suspicious(parsed: ParsedReceipt) -> None:
    """Tandai barang yang tampak janggal walau angkanya konsisten.

    - Harga bukan kelipatan 50 (harga rupiah hampir selalu berakhiran 00/50): sering
      berarti satu digit salah baca, mis. 16.068 untuk 16.000.
    - Nama berisi sisa angka/harga ("1 3 Aqua 600ml", "Promag Tablet 1 9.500,e0").
    """
    for item in parsed.items:
        odd_price = item.price is not None and item.price % 50 != 0
        junk_name = bool(_PRICE_IN_NAME.search(item.name))
        item.suspicious = odd_price or junk_name


def assess(parsed: ParsedReceipt) -> tuple[bool, dict[str, str], list[str]]:
    """Tingkat keyakinan per kolom + daftar kolom yang perlu dicek pengguna."""
    mark_suspicious(parsed)
    consistent = is_consistent(parsed)
    corrected_items = any(i.price_corrected or i.suspicious for i in parsed.items)
    total_corrected = any(c.startswith("total") for c in parsed.corrections)

    if parsed.total_amount is None:
        total = LOW
    elif consistent and not total_corrected:
        total = HIGH
    elif consistent:
        total = MEDIUM  # cocok, tapi setelah dikoreksi otomatis
    else:
        total = LOW

    if not parsed.items:
        items = LOW
    elif consistent and not corrected_items:
        items = HIGH
    elif consistent:
        items = MEDIUM
    else:
        items = LOW

    now = datetime.now()
    if parsed.transaction_date is None:
        date = LOW
    elif now - timedelta(days=400) <= parsed.transaction_date <= now + timedelta(days=1):
        date = HIGH
    else:
        date = MEDIUM  # terbaca, tapi jauh dari hari ini (bisa salah baca digit tahun)

    merchant = HIGH if parsed.merchant_name else LOW
    confidence = {"merchant": merchant, "date": date, "total": total, "items": items}
    review = [k for k, v in confidence.items() if v != HIGH]
    return consistent, confidence, review


def read_receipt(
    image: Image.Image,
    ocr: OCREngine,
    parser: ReceiptParser,
    device_text: str | None = None,
) -> ReceiptReading:
    """Baca struk dari foto; `device_text` = teks ML Kit dari HP (opsional)."""
    result = ocr.extract(image)
    candidates = list(result.candidates or [])
    if not candidates:
        candidates = [OcrCandidate(result.text, 0.0, result.enhanced, "tesseract")]
    if device_text and device_text.strip():
        candidates.append(OcrCandidate(device_text[:MAX_DEVICE_TEXT], 0.0, False, "ML Kit (HP)"))

    def pick(cands):
        best: tuple[float, float, ReceiptReading] | None = None
        for cand in cands:
            parsed = parser.parse(cand.text)
            key = (plausibility(parsed), cand.ocr_score)
            if best is None or key > best[:2]:
                best = (*key, ReceiptReading(parsed, cand.text, result, cand.label))
        return best[2]

    reading = pick(candidates)
    # Belum konsisten (mis. kolom harga di kanan tidak terbaca): coba mode baca lain.
    extra = getattr(ocr, "extra_candidates", None)
    if extra and not is_consistent(reading.parsed):
        candidates += extra(image)
        reading = pick(candidates)
    result.candidates = candidates
    _repair_names(reading.parsed)
    reading.ocr.enhanced = next((c.enhanced for c in candidates if c.text == reading.raw_text), result.enhanced)
    reading.consistent, reading.confidence, reading.review_fields = assess(reading.parsed)
    return reading
