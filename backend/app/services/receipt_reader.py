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
    # Ringkasan hasil tiap mesin OCR (untuk membandingkan ML Kit / RapidOCR / Tesseract).
    sources: list[dict] = field(default_factory=list)


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


def _needs_referee(reading: ReceiptReading, parsed_all) -> bool:
    """True bila bacaan terbaik belum konsisten, atau pembaca lain tidak sepakat soal total
    / jumlah barang."""
    if not is_consistent(reading.parsed):
        return True
    best = reading.parsed
    # Data kepala struk belum lengkap: bacaan pembanding mungkin menemukannya.
    if best.transaction_date is None or best.total_amount is None or not best.merchant_name:
        return True
    # Nama berakhir angka tunggal ("minyak goreng 1"): satuan di belakangnya mungkin hilang.
    if any(re.search(r"\s\d{1,2}$", item.name.strip()) for item in best.items):
        return True
    # Nama barang yang ejaannya jelek (kata tak dikenal, spasi rusak) perlu bacaan pembanding.
    for item in best.items:
        if _name_readability(item.name) < 0.8 or re.search(r"[a-z]{10,}", item.name.lower()):
            return True
    for _, other in parsed_all:
        if other is best or not other.items:
            continue
        if (other.total_amount is not None and best.total_amount is not None
                and abs(other.total_amount - best.total_amount) >= 1):
            return True
        if abs(len(other.items) - len(best.items)) > 1:
            return True
    return False


def _name_readability(name: str) -> float:
    """Porsi kata (>= 3 huruf) pada nama yang dikenal kosakata, 0-1."""
    from app.integrations.providers import get_normalizer

    repairer = getattr(get_normalizer(), "repairer", None)
    words = [w.lower() for w in re.findall(r"[A-Za-z]{3,}", name)]
    if repairer is None or not words:
        return 0.0
    return sum(1 for w in words if repairer.known(w)) / len(words)


def _vote_words(base: str, variants: list[str]) -> str:
    """Voting per kata: kata pada `base` yang tidak dikenal diganti kata sejajar dari bacaan
    mesin lain bila kata itu dikenal ("Segar t" vs "Serabut" -> "Serabut")."""
    from difflib import SequenceMatcher

    from app.integrations.providers import get_normalizer

    repairer = getattr(get_normalizer(), "repairer", None)
    if repairer is None or not variants:
        return base

    size = re.compile(r"^[\d.,/x@%-]+([a-z]{1,4})?$")

    def ok(word: str) -> bool:
        """Kata "kuat": dikenal kosakata, atau angka/ukuran murni ("2.54MM", "10")."""
        low = word.lower().strip(".,:;()")
        if not low:
            return True
        if low.isalpha():
            return len(low) >= 3 and repairer.known(low)
        return bool(size.match(low))

    tokens = base.split()
    for variant in variants:
        other = variant.split()
        matcher = SequenceMatcher(None, [t.lower() for t in tokens], [t.lower() for t in other], autojunk=False)
        out: list[str] = []
        for op, i1, i2, j1, j2 in matcher.get_opcodes():
            mine, theirs = tokens[i1:i2], other[j1:j2]
            if op == "replace" and not all(ok(t) for t in mine) and theirs                     and all(ok(t) for t in theirs) and sum(ok(t) for t in mine) < len(theirs) and any(t.isalpha() and len(t) >= 3 for t in theirs)                     and abs(len(" ".join(mine)) - len(" ".join(theirs))) <= max(3, len(" ".join(mine)) // 2):
                out.extend(theirs)
            else:
                out.extend(mine)
        tokens = out
    return " ".join(tokens)


def _fuse_item_names(parsed: ParsedReceipt, others: list[ParsedReceipt]) -> None:
    """Untuk tiap barang, cari barang yang sama (harga sama, nama mirip) di bacaan mesin lain.
    1. pakai versi nama yang paling banyak berisi kata dikenal;
    2. lalu voting per kata: kata yang masih rusak diganti kata sejajar yang dikenal dari mesin lain."""
    from difflib import SequenceMatcher

    for item in parsed.items:
        if item.price is None:
            continue
        best_name, best_score = item.name, _name_readability(item.name)
        matches: list[str] = []
        for other in others:
            for cand in other.items:
                if cand.price is None or abs(cand.price - item.price) >= 1:
                    continue
                if SequenceMatcher(None, cand.name.lower(), item.name.lower()).ratio() < 0.45:
                    continue
                matches.append(cand.name)
                score = _name_readability(cand.name)
                # Versi lain harus jelas lebih terbaca dan tidak jauh lebih pendek (nama terpotong).
                if score > best_score + 0.1 and len(cand.name) >= 0.7 * len(item.name):
                    best_name, best_score = cand.name, score
        variants = [n for n in matches + [item.name] if n != best_name]
        item.name = _vote_words(best_name, variants)


def _repair_names(parsed: ParsedReceipt) -> None:
    """Pulihkan huruf yang hilang pada nama barang ("ula Pasir" -> "Gula Pasir")."""
    from app.integrations.providers import get_normalizer  # hindari impor melingkar

    repairer = getattr(get_normalizer(), "repairer", None)
    if repairer is None:
        return
    for item in parsed.items:
        original = item.name
        fixed = repairer.repair_display(item.name)
        if fixed != item.name:
            item.name = fixed
            item.name_corrected = True
        item.uncertain_words = uncertain_words(fixed, original, repairer)


def uncertain_words(name: str, original: str, repairer) -> list[str]:
    """Kata yang perlu dicek pengguna: hasil koreksi otomatis, atau kata (>= 3 huruf) yang
    tidak dikenal kosakata, termasuk huruf yang tercampur angka ("Gifuct", "1Hu10")."""
    # Kata hasil pemecahan kata gabungan ("SolderParagon") tetap ada di teks asli -> bukan ragu.
    joined = re.sub(r"\s+", "", original.lower())
    out: list[str] = []
    for word in name.split():
        low = word.lower().strip(".,:;()")
        if not low:
            continue
        changed = low not in joined
        letters = sum(ch.isalpha() for ch in low)
        if low.isalpha():
            unknown = len(low) >= 3 and not repairer.known(low)
        else:
            unknown = letters >= 2 and not re.fullmatch(r"[\d.,/x@%-]+[a-z]{0,4}", low)
        if (changed or unknown) and word not in out:
            out.append(word)
    return out


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


_FIELD_GROUP = {"merchant": "merchant", "date": "date", "time": "date", "total": "total",
                "subtotal": "total", "item": "items"}


def _read_with_vision(image: Image.Image, vision) -> ReceiptReading | None:
    """Baca dengan Claude vision. None = tidak aktif / gagal (pemanggil memakai OCR biasa)."""
    if vision is None:
        return None
    try:
        result = vision.extract(image)
    except Exception:  # pragma: no cover - jalur cadangan harus tetap jalan apa pun errornya
        import logging

        logging.getLogger("strukku").exception("Claude vision gagal; memakai OCR biasa")
        return None
    if result is None or not (result[0].items or result[0].total_amount is not None):
        return None
    parsed, data = result
    ocr = OcrResult(data.transcription, [], False, [OcrCandidate(data.transcription, 0.0, False, vision.label)])
    reading = ReceiptReading(parsed, data.transcription, ocr, vision.label)
    reading.consistent, reading.confidence, reading.review_fields = assess(parsed)
    # Kolom yang dilaporkan Claude tidak terbaca -> wajib dicek pengguna.
    for field_name in data.unreadable_fields:
        key = field_name.lower()
        group = next((g for k, g in _FIELD_GROUP.items() if k in key), None)
        if group and group not in reading.review_fields:
            reading.review_fields.append(group)
            reading.confidence[group] = MEDIUM if reading.confidence.get(group) == HIGH else reading.confidence.get(group, LOW)
        m = re.search(r"items?\[(\d+)\]", key)
        if m and int(m.group(1)) < len(parsed.items):
            parsed.items[int(m.group(1))].suspicious = True
    return reading


def read_receipt(
    image: Image.Image,
    ocr: OCREngine,
    parser: ReceiptParser,
    device_text: str | None = None,
    vision=None,
) -> ReceiptReading:
    """Baca struk dari foto; `device_text` = teks ML Kit dari HP (opsional).

    Urutan: Claude vision (bila dikonfigurasi) -> Tesseract + ML Kit + parser.
    """
    reading = _read_with_vision(image, vision)
    if reading is not None:
        return reading

    result = ocr.extract(image)
    candidates = list(result.candidates or [])
    if not candidates:
        candidates = [OcrCandidate(result.text, 0.0, result.enhanced, "tesseract")]
    if device_text and device_text.strip():
        candidates.append(OcrCandidate(device_text[:MAX_DEVICE_TEXT], 0.0, False, "ML Kit (HP)"))

    parsed_all: list[tuple[OcrCandidate, ParsedReceipt]] = []

    def pick(cands):
        best: tuple[float, float, ReceiptReading] | None = None
        parsed_all.clear()
        for cand in cands:
            parsed = parser.parse(cand.text)
            parsed_all.append((cand, parsed))
            # Seri: utamakan Tesseract (spasi antarkata lebih rapi pada cetakan bersih).
            key = (plausibility(parsed), 0 if cand.label == "RapidOCR" else 1, cand.ocr_score)
            if best is None or key > best[0]:
                best = (key, ReceiptReading(parsed, cand.text, result, cand.label))
        return best[1]

    reading = pick(candidates)
    # Tesseract sebagai penengah: dipanggil hanya bila bacaan RapidOCR/ML Kit belum
    # konsisten atau saling berbeda (struk jelas tidak perlu menunggu Tesseract).
    lazy = getattr(ocr, "tesseract_candidates", None)
    if lazy and _needs_referee(reading, parsed_all):
        more = lazy(image)
        if more:
            candidates += more
            reading = pick(candidates)
    # Belum konsisten (mis. kolom harga di kanan tidak terbaca): coba mode baca lain.
    extra = getattr(ocr, "extra_candidates", None)
    if extra and not is_consistent(reading.parsed):
        candidates += extra(image)
        reading = pick(candidates)
    result.candidates = candidates
    # Angka dari bacaan paling konsisten; nama tiap barang dari mesin yang ejaannya paling
    # terbaca (ML Kit / RapidOCR / Tesseract saling melengkapi).
    _fuse_item_names(reading.parsed, [p for c, p in parsed_all if c.text != reading.raw_text])
    reading.sources = [
        {"label": c.label, "plausibility": round(plausibility(p), 1), "items": len(p.items),
         "total": p.total_amount, "consistent": is_consistent(p)}
        for c, p in parsed_all
    ]
    _repair_names(reading.parsed)
    reading.ocr.enhanced = next((c.enhanced for c in candidates if c.text == reading.raw_text), result.enhanced)
    reading.consistent, reading.confidence, reading.review_fields = assess(reading.parsed)
    return reading
