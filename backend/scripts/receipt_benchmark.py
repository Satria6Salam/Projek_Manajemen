"""Benchmark ekstraksi struk: OCR + parser diuji pada berbagai format dan kondisi foto.

Data uji:
- 4 struk nyata (tests/data/receipts/real) beserta kunci jawabannya.
- Struk sintetis berbagai format (Alfamart, kafe, supermarket ber-PLU, "Rp x = Rp",
  apotek dengan desimal ",00", warung) yang dibuat dari kode, sehingga isinya pasti diketahui.
Setiap struk diberi variasi kondisi foto: buram, goyang, pudar, gelap, berbayang, miring,
difoto di atas meja (perspektif), resolusi rendah, dan JPEG kualitas rendah.

Pemakaian (dari folder backend):
    python -m scripts.receipt_benchmark                 # semua kondisi
    python -m scripts.receipt_benchmark --quick         # subset cepat
    python -m scripts.receipt_benchmark --out hasil.json --workers 4
"""
from __future__ import annotations

import argparse
import io
import os
import json
import random
import re
import sys
import time
import zlib
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
REAL_DIR = ROOT / "tests" / "data" / "receipts" / "real"

CONDITIONS = ["clean", "blur", "blur_strong", "motion_mild", "motion", "faded", "dark", "shadow",
              "rotate", "photo", "lowres", "jpeg"]
QUICK_CONDITIONS = ["clean", "blur_strong", "faded", "dark", "photo", "lowres"]


# ============================================================ data sintetis
GROCERIES = [
    ("Beras Pandan Wangi 5kg", "BERAS PDN WANGI 5KG", 68500), ("Minyak Goreng Bimoli 2L", "BIMOLI MNYK GRG 2L", 38900),
    ("Gula Pasir Gulaku 1kg", "GULAKU GULA PSR 1KG", 17200), ("Telur Ayam Negeri 1kg", "TELUR AYAM NEG 1KG", 28500),
    ("Indomie Goreng Spesial", "INDOMIE GRG SPC", 3100), ("Sari Roti Tawar 200g", "SARI ROTI TWR 200G", 17500),
    ("Ultra Milk Coklat 250ml", "ULTRA MILK CKLT 250ML", 6500), ("Aqua Botol 600ml", "AQUA BTL 600ML", 3800),
    ("Teh Botol Sosro 450ml", "TEH BTL SOSRO 450ML", 5200), ("Kopi Kapal Api 165g", "KAPAL API SPC 165G", 13000),
    ("Sabun Mandi Lifebuoy 85g", "LIFEBUOY BAR 85G", 4200), ("Pepsodent 190g", "PEPSODENT PG 190G", 14900),
    ("Shampoo Sunsilk 170ml", "SUNSILK SHMP 170ML", 24500), ("Rinso Anti Noda 770g", "RINSO ANTI NODA 770G", 23900),
    ("Sunlight Jeruk Nipis 755ml", "SUNLIGHT JRK NPS 755", 16800), ("Tisu Paseo 250 Sheet", "PASEO FACIAL 250S", 12500),
    ("Paracetamol 500mg", "PARACETAMOL 500MG", 5000), ("Vitamin C 1000mg", "VIT C 1000MG", 35000),
    ("Minyak Kayu Putih 60ml", "KAYU PUTIH CAP LANG 60", 21500), ("Chitato Sapi Panggang 68g", "CHITATO SP PGG 68G", 11200),
    ("Oreo Vanilla 133g", "OREO VANILLA 133G", 9900), ("Pocari Sweat 500ml", "POCARI SWEAT 500ML", 7800),
    ("Kecap Bango 520ml", "BANGO KCP MANIS 520", 24800), ("Saos Sambal ABC 335ml", "ABC SMBL ASLI 335", 12700),
]
CAFE = [("Es Kopi Susu Aren", 25000), ("Americano", 22000), ("Croissant Butter", 22000), ("Nasi Goreng Spesial", 32000),
        ("Mie Ayam Bakso", 25000), ("Air Mineral", 8000), ("Es Teh Manis", 8000), ("Roti Bakar Coklat", 18000),
        ("Kentang Goreng", 20000), ("Matcha Latte", 28000)]
PHARMA = [("Paracetamol 500mg", 5000), ("Vitamin C 1000mg", 35000), ("Promag Tablet", 9500), ("Betadine 30ml", 27000),
          ("Minyak Telon 60ml", 23000), ("Masker Medis 50pcs", 30000), ("Antangin JRG", 4000)]


def rp(n: float, sep: str = ".") -> str:
    return f"{int(round(n)):,}".replace(",", sep)


def center(text: str, width: int) -> str:
    return text.center(width).rstrip()


def cols(left: str, right: str, width: int) -> str:
    gap = max(1, width - len(left) - len(right))
    return left + " " * gap + right


def _pick(rng: random.Random, pool, k):
    return rng.sample(pool, k)


def fmt_alfamart(rng: random.Random):
    w = 40
    picks = _pick(rng, GROCERIES, rng.randint(3, 6))
    items, lines = [], [center("ALFAMART", w), center("PT. SUMBER ALFARIA TRIJAYA, TBK", w),
                        center("JL. SOEKARNO HATTA NO.9 MALANG", w), center("NPWP: 01.336.238.9-054.000", w),
                        "22.11.2026-14:05  2.1.37  A1/KSR01", "-" * w]
    for _, short, price in picks:
        q = rng.choice([1, 1, 1, 2, 3])
        lines += [short, cols(f"   {q} x {rp(price, ',')}", rp(q * price, ","), w)]
        items.append({"name": short, "qty": q, "price": q * price})
    total = sum(i["price"] for i in items)
    pay = (total // 50000 + 1) * 50000
    lines += ["-" * w, cols(f"TOTAL ITEM  {len(items)}", "", w), cols("TOTAL BELANJA", rp(total, ","), w),
              cols("TUNAI", rp(pay, ","), w), cols("KEMBALIAN", rp(pay - total, ","), w), "",
              center("TERIMA KASIH. SELAMAT BELANJA KEMBALI", w)]
    return lines, {"merchant": "ALFAMART", "date": "2026-11-22", "total": total, "items": items}


def fmt_cafe(rng: random.Random):
    w = 34
    picks = _pick(rng, CAFE, rng.randint(2, 5))
    items, lines = [], [center("KOPI SENJA", w), center("Jl. Ijen No. 21, Malang", w),
                        "Sab, 22 Nov 2026          19:03", "Order #A102           Meja 7", "-" * w]
    for name, price in picks:
        q = rng.choice([1, 1, 2])
        lines.append(cols(f"{q} {name}", rp(q * price), w))
        items.append({"name": name, "qty": q, "price": q * price})
    sub = sum(i["price"] for i in items)
    service = round(sub * 0.05)
    tax = round((sub + service) * 0.10)
    total = sub + service + tax
    lines += ["-" * w, cols("Subtotal", rp(sub), w), cols("Service 5%", rp(service), w),
              cols("PB1 10%", rp(tax), w), cols("Grand Total", rp(total), w), "", center("Terima kasih!", w)]
    return lines, {"merchant": "KOPI SENJA", "date": "2026-11-22", "total": total, "items": items}


def fmt_supermarket(rng: random.Random):
    w = 42
    picks = _pick(rng, GROCERIES, rng.randint(3, 5))
    items, lines = [], [center("SUPERINDO GAJAYANA", w), center("Jl. Gajayana No. 5 Malang 65144", w),
                        "Tgl: 2026-11-22   Jam: 10:15   Ksr: 03", "-" * w]
    disc_total = 0
    for _, short, price in picks:
        q = rng.choice([1, 1, 2])
        plu = "899" + "".join(str(rng.randint(0, 9)) for _ in range(7))
        lines += [f"{plu} {short}", cols(f"          {q} @ {rp(price, ',')}", rp(q * price, ","), w)]
        items.append({"name": short, "qty": q, "price": q * price})
        if rng.random() < 0.3:
            d = rng.choice([500, 1000, 1500])
            disc_total += d
            lines.append(cols("   DISC", "-" + rp(d, ","), w))
    total = sum(i["price"] for i in items) - disc_total
    lines += ["-" * w, cols("TOTAL", rp(total, ","), w), cols("DEBIT BCA", rp(total, ","), w), "",
              center("HARGA SUDAH TERMASUK PPN", w)]
    return lines, {"merchant": "SUPERINDO GAJAYANA", "date": "2026-11-22", "total": total, "items": items}


def fmt_rp_equals(rng: random.Random):
    picks = _pick(rng, GROCERIES, rng.randint(2, 5))
    items, lines = [], ["TOKO BERKAH JAYA", "Jl. Mawar No. 3, Blitar", "Tanggal : 22/11/2026 08:41", "-" * 34]
    for long, _, price in picks:
        q = rng.choice([1, 1, 2, 3])
        lines += [long, f"{q} pcs x Rp {rp(price)} = Rp {rp(q * price)}"]
        items.append({"name": long, "qty": q, "price": q * price})
    total = sum(i["price"] for i in items)
    pay = (total // 10000 + 1) * 10000
    lines += ["-" * 34, f"Total   : Rp {rp(total)}", f"Bayar   : Rp {rp(pay)}", f"Kembali : Rp {rp(pay - total)}"]
    return lines, {"merchant": "TOKO BERKAH JAYA", "date": "2026-11-22", "total": total, "items": items}


def fmt_pharmacy(rng: random.Random):
    w = 46
    picks = _pick(rng, PHARMA, rng.randint(2, 4))
    items, lines = [], [center("APOTEK SEHAT SENTOSA", w), center("Jl. Veteran No. 8 Malang", w),
                        "No: INV/2026/11/0098", "22-11-2026 16:20", "-" * w,
                        "Nama Obat            Qty     Harga     Jumlah"]
    for name, price in picks:
        q = rng.choice([1, 1, 2, 3])
        left = f"{name[:20]:<20} {q:>3}"
        lines.append(cols(f"{left} {rp(price)},00", f"{rp(q * price)},00", w))
        items.append({"name": name[:20].strip(), "qty": q, "price": q * price})
    total = sum(i["price"] for i in items)
    lines += ["-" * w, cols("TOTAL", f"{rp(total)},00", w), cols("TUNAI", f"{rp(total)},00", w)]
    return lines, {"merchant": "APOTEK SEHAT SENTOSA", "date": "2026-11-22", "total": total, "items": items}


def fmt_warung(rng: random.Random):
    w = 32
    picks = _pick(rng, GROCERIES, rng.randint(3, 6))
    items, lines = [], [center("WARUNG BU SRI", w), center("Pasar Dinoyo Blok C-12", w), "22 November 2026", ""]
    for long, _, price in picks:
        name = long[:20]
        lines.append(cols(name, rp(price), w))
        items.append({"name": name.strip(), "qty": 1, "price": price})
    total = sum(i["price"] for i in items)
    lines += ["=" * w, cols("JUMLAH", rp(total), w), "", center("Matur nuwun", w)]
    return lines, {"merchant": "WARUNG BU SRI", "date": "2026-11-22", "total": total, "items": items}


FORMATS = {"alfamart": fmt_alfamart, "cafe": fmt_cafe, "supermarket": fmt_supermarket,
           "rp_equals": fmt_rp_equals, "pharmacy": fmt_pharmacy, "warung": fmt_warung}

_FONT_CANDIDATES = ["consola.ttf", "cour.ttf", "lucon.ttf", "DejaVuSansMono.ttf", "LiberationMono-Regular.ttf"]


def _font(size: int) -> ImageFont.ImageFont:
    for name in _FONT_CANDIDATES:
        for base in ("", "C:/Windows/Fonts/", "/usr/share/fonts/truetype/dejavu/"):
            try:
                return ImageFont.truetype(base + name, size)
            except OSError:
                continue
    return ImageFont.load_default()


def render(lines: list[str], width_chars: int = 42, font_size: int = 26) -> Image.Image:
    font = _font(font_size)
    char_w = font.getbbox("M")[2]
    line_h = int(font_size * 1.35)
    width = char_w * max(width_chars, max(len(line) for line in lines)) + 80
    height = line_h * len(lines) + 120
    img = Image.new("L", (width, height), 250)
    draw = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        draw.text((40, 60 + i * line_h), line, fill=25, font=font)
    return img.convert("RGB")


# ============================================================ kondisi foto
def degrade(img: Image.Image, condition: str, seed: int = 0) -> Image.Image:
    rng = np.random.default_rng(seed)
    img = img.convert("RGB")
    scale = img.width / 1000
    if condition == "clean":
        return img
    if condition == "blur":
        return img.filter(ImageFilter.GaussianBlur(1.6 * scale))
    if condition == "blur_strong":
        return img.filter(ImageFilter.GaussianBlur(2.6 * scale))
    if condition in ("motion", "motion_mild"):
        # motion_mild ~ tangan sedikit goyang; motion = goyang berat (uji batas).
        arr = np.asarray(img, dtype=np.float32)
        k = max(3, int((5 if condition == "motion_mild" else 9) * scale))
        out = sum(np.roll(arr, (i // 3, i), axis=(0, 1)) for i in range(k)) / k
        return Image.fromarray(out.clip(0, 255).astype(np.uint8))
    if condition == "faded":
        arr = np.asarray(img.filter(ImageFilter.GaussianBlur(0.7 * scale)), dtype=np.float32)
        arr = 255 - (255 - arr) * 0.33
        return Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    if condition == "dark":
        arr = np.asarray(img, dtype=np.float32) * 0.36
        arr += rng.normal(0, 7, arr.shape)
        return Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    if condition == "shadow":
        arr = np.asarray(img, dtype=np.float32)
        h, w = arr.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w]
        grad = 0.28 + 0.72 * np.clip((xx / w + yy / h) / 1.3, 0, 1)
        return Image.fromarray((arr * grad[..., None]).clip(0, 255).astype(np.uint8))
    if condition == "rotate":
        return img.rotate(7, resample=Image.BICUBIC, expand=True, fillcolor=(120, 110, 100))
    if condition == "lowres":
        w = 430
        return img.resize((w, int(img.height * w / img.width)), Image.BILINEAR)
    if condition == "jpeg":
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=12)
        return Image.open(io.BytesIO(buf.getvalue())).convert("RGB")
    if condition == "photo":
        return _phone_photo(img, rng)
    raise ValueError(condition)


def _phone_photo(img: Image.Image, rng) -> Image.Image:
    """Struk difoto di atas meja: latar kayu, perspektif, cahaya tidak rata, sedikit buram."""
    cw, ch = 1500, 2000
    bg = np.zeros((ch, cw, 3), dtype=np.float32)
    bg[..., 0], bg[..., 1], bg[..., 2] = 92, 70, 52
    bg += rng.normal(0, 10, (ch, 1, 1)) + rng.normal(0, 6, bg.shape)
    canvas = Image.fromarray(bg.clip(0, 255).astype(np.uint8))
    target_h = int(ch * 0.78)
    r = img.resize((int(img.width * target_h / img.height), target_h), Image.LANCZOS)
    if r.width > cw * 0.8:
        r = img.resize((int(cw * 0.8), int(img.height * cw * 0.8 / img.width)), Image.LANCZOS)
    x0, y0 = (cw - r.width) // 2, (ch - r.height) // 2
    canvas.paste(r, (x0, y0))
    # Perspektif: sisi atas lebih sempit (kamera condong).
    inset = r.width * 0.09
    src = [(x0 + inset, y0), (x0 + r.width - inset, y0), (x0 + r.width, y0 + r.height), (x0, y0 + r.height)]
    dst = [(x0, y0), (x0 + r.width, y0), (x0 + r.width, y0 + r.height), (x0, y0 + r.height)]
    coeffs = _perspective_coeffs(dst, src)
    canvas = canvas.transform(canvas.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC, fillcolor=(92, 70, 52))
    canvas = canvas.rotate(3, resample=Image.BICUBIC, fillcolor=(92, 70, 52))
    arr = np.asarray(canvas, dtype=np.float32)
    yy, xx = np.mgrid[0:ch, 0:cw]
    light = 0.62 + 0.38 * np.clip(1 - ((xx - cw * 0.3) ** 2 + (yy - ch * 0.25) ** 2) / (cw * ch * 0.9), 0, 1)
    arr = arr * light[..., None]
    out = Image.fromarray(arr.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.1))
    buf = io.BytesIO()
    out.save(buf, format="JPEG", quality=70)
    return Image.open(io.BytesIO(buf.getvalue())).convert("RGB")


def _perspective_coeffs(src, dst):
    m = []
    for (x, y), (u, v) in zip(src, dst):
        m.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        m.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(m, dtype=np.float64)
    b = np.array([c for p in dst for c in p], dtype=np.float64)
    return np.linalg.solve(a, b).tolist()


# ============================================================ penilaian
def norm(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", (text or "").lower())).strip()


def similar(a: str, b: str) -> float:
    return SequenceMatcher(None, norm(a), norm(b)).ratio()


@dataclass
class Score:
    merchant: bool = False
    date: bool = False
    total: bool = False
    items_gt: int = 0
    items_pred: int = 0
    items_correct: int = 0      # nama cocok DAN harga benar
    names_found: int = 0        # nama cocok (harga boleh salah)
    qty_correct: int = 0
    seconds: float = 0.0
    errors: list = field(default_factory=list)


def score(gt: dict, parsed, seconds: float) -> Score:
    s = Score(seconds=seconds)
    m = norm(parsed.merchant_name or "")
    s.merchant = bool(m) and (norm(gt["merchant"]) in m or similar(m, gt["merchant"]) >= 0.8)
    s.date = parsed.transaction_date is not None and parsed.transaction_date.strftime("%Y-%m-%d") == gt["date"]
    s.total = parsed.total_amount is not None and abs(parsed.total_amount - gt["total"]) < 1
    preds = list(parsed.items)
    s.items_gt, s.items_pred = len(gt["items"]), len(preds)
    used: set[int] = set()
    for g in gt["items"]:
        best, best_i = 0.0, None
        for i, p in enumerate(preds):
            if i in used:
                continue
            r = similar(p.name, g["name"])
            if r > best:
                best, best_i = r, i
        if best_i is not None and best >= 0.72:
            used.add(best_i)
            p = preds[best_i]
            s.names_found += 1
            # Nama harus nyaris sama (tanpa sisa qty/nomor/angka harga), kecuali foto HP asli
            # yang kunci jawabannya hanya menilai angka (check_names: false).
            name_ok = best >= 0.85 or gt.get("check_names") is False
            if p.price is not None and abs(p.price - g["price"]) < 1 and name_ok:
                s.items_correct += 1
            elif not name_ok:
                s.errors.append(f"nama '{g['name']}': {p.name!r}")
            else:
                s.errors.append(f"harga '{g['name']}': {p.price} != {g['price']}")
            if p.quantity == g["qty"]:
                s.qty_correct += 1
            else:
                s.errors.append(f"qty '{g['name']}': {p.quantity} != {g['qty']}")
        else:
            s.errors.append(f"hilang: {g['name']}")
    for i, p in enumerate(preds):
        if i not in used:
            s.errors.append(f"lebih: {p.name} ({p.price})")
    if not s.merchant:
        s.errors.append(f"toko: {parsed.merchant_name!r}")
    if not s.date:
        s.errors.append(f"tanggal: {parsed.transaction_date}")
    if not s.total:
        s.errors.append(f"total: {parsed.total_amount} != {gt['total']}")
    return s


# ============================================================ jalankan
def build_cases(conditions: list[str], per_format: int) -> list[dict]:
    cases = []
    truth = json.loads((REAL_DIR / "ground_truth.json").read_text(encoding="utf-8"))
    for fname, gt in truth.items():
        for cond in conditions:
            cases.append({"id": f"real/{fname}/{cond}", "group": "real", "source": str(REAL_DIR / fname),
                          "gt": gt, "condition": cond})
    for fmt, maker in FORMATS.items():
        for n in range(per_format):
            for cond in conditions:
                cases.append({"id": f"{fmt}#{n}/{cond}", "group": fmt, "format": fmt, "n": n,
                              "condition": cond})
    return cases


_ENGINE = None


def _worker_init():
    global _ENGINE
    from app.core.config import settings
    from app.integrations.ocr.tesseract import TesseractOCR
    from app.integrations.parser.regex_parser import RegexReceiptParser
    from app.integrations.providers import OCR_REGISTRY
    _ENGINE = (OCR_REGISTRY[os.environ.get("BENCH_OCR", settings.OCR_ENGINE)](), RegexReceiptParser())


def run_case(case: dict) -> dict:
    from app.services.receipt_reader import read_receipt
    if _ENGINE is None:
        _worker_init()
    ocr, parser = _ENGINE
    if case["group"] == "real":
        base, gt = Image.open(case["source"]).convert("RGB"), case["gt"]
    else:
        rng = random.Random(f"{case['format']}-{case['n']}")
        lines, gt = FORMATS[case["format"]](rng)
        base = render(lines)
        # Struk sintetis dicetak ukuran nyata (~1000 px), seperti foto struk asli.
        base = base.resize((1000, int(base.height * 1000 / base.width)), Image.LANCZOS)
    img = degrade(base, case["condition"], seed=zlib.crc32(case["id"].encode()) % 10_000)
    t0 = time.perf_counter()
    reading = read_receipt(img, ocr, parser)
    parsed = reading.parsed
    s = score(gt, parsed, time.perf_counter() - t0)
    wrong = (not s.total) or s.items_correct < s.items_gt or s.items_pred > s.items_gt
    flagged = (not reading.consistent) or bool(reading.review_fields) or any(i.price_corrected or i.suspicious for i in parsed.items)
    return {"id": case["id"], "group": case["group"], "condition": case["condition"], **s.__dict__,
            "raw_text": reading.raw_text, "reading": reading.label, "corrections": parsed.corrections,
            "wrong": wrong, "silent": wrong and not flagged}


def summarize(rows: list[dict], key: str) -> list[tuple]:
    groups: dict[str, list[dict]] = {}
    for r in rows:
        groups.setdefault(r[key], []).append(r)
    out = []
    for name, rs in groups.items():
        gt = sum(r["items_gt"] for r in rs)
        pred = sum(r["items_pred"] for r in rs)
        ok = sum(r["items_correct"] for r in rs)
        prec = ok / pred if pred else 0.0
        rec = ok / gt if gt else 0.0
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        out.append((name, len(rs), sum(r["merchant"] for r in rs) / len(rs), sum(r["date"] for r in rs) / len(rs),
                    sum(r["total"] for r in rs) / len(rs), rec, prec, f1,
                    sum(r.get("silent", False) for r in rs) / len(rs), sum(r["seconds"] for r in rs) / len(rs)))
    return out


def print_table(title: str, rows: list[tuple]) -> None:
    print(f"\n{title}")
    print(f"{'':<13}{'n':>4} {'toko':>6} {'tgl':>6} {'total':>6} {'recall':>7} {'presisi':>8} {'F1':>6} "
          f"{'salah-diam':>10} {'detik':>6}")
    for name, n, m, d, t, rec, prec, f1, silent, sec in rows:
        print(f"{name:<13}{n:>4} {m:>6.0%} {d:>6.0%} {t:>6.0%} {rec:>7.0%} {prec:>8.0%} {f1:>6.0%} "
              f"{silent:>10.0%} {sec:>6.1f}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--quick", action="store_true", help="subset kondisi foto")
    ap.add_argument("--per-format", type=int, default=2)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--out", type=Path, default=None, help="simpan hasil rinci (JSON)")
    ap.add_argument("--only", default="", help="filter id, mis. 'cafe' atau 'real'")
    args = ap.parse_args()
    conditions = QUICK_CONDITIONS if args.quick else CONDITIONS
    cases = [c for c in build_cases(conditions, args.per_format) if args.only in c["id"]]
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=args.workers, initializer=_worker_init) as pool:
        rows = list(pool.map(run_case, cases, chunksize=2))
    rows.sort(key=lambda r: r["id"])
    print_table("PER KONDISI FOTO", summarize(rows, "condition"))
    print_table("PER FORMAT STRUK", summarize(rows, "group"))
    print_table("KESELURUHAN", summarize([{**r, "all": "semua"} for r in rows], "all"))
    print(f"\n{len(rows)} gambar, {time.time() - t0:.0f} detik")
    if args.out:
        args.out.write_text(json.dumps(rows, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
        print(f"hasil rinci: {args.out}")


if __name__ == "__main__":
    sys.exit(main())
