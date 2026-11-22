"""Parser struk berbasis aturan (regex) untuk format minimarket Indonesia.

Format baris barang yang dikenali, contoh:
    ROTI TAWAR 500G            22.500
    SUSU UHT 1L   2 x 9.000    18.000
    SUSU UHT 1L   2  9.000     18.000
    VITAMIN C 10 TABLET                      (nama di satu baris)
      1 x 15.000               15.000        (harga di baris berikutnya)
"""
import re
from dataclasses import replace
from datetime import datetime

from app.integrations.parser.base import ParsedItem, ParsedReceipt, ReceiptParser

MIN_PRICE = 100
MAX_PRICE = 100_000_000

_NUMBER_TOKEN = re.compile(r"^-?(?:rp\.?)?-?\d[\d.,]*$", re.IGNORECASE)
_QTY_PREFIX = re.compile(r"^(\d{1,3})\s*[xX×@*]{1,2}$|^[xX×@*]{1,2}$|^[xX×@*]{1,2}(\d{1,3})$")
# Angka "1" yang sering terbaca OCR sebagai huruf.
_MISREAD_ONE = {"l", "i", "il", "li", "ll", "al", "|", "!", "]", "["}  # tanpa "1L" (= 1 liter)
# Nomor urut di awal nama barang: "2 USB", "3. Kabel", "Al Headphone" (1 salah baca).
_ROW_NUMBER = re.compile(r"^(\d{1,3}|al|il|l|i|\|)[.):]?\s+(?=\S*[A-Za-z]{2})", re.IGNORECASE)
# Judul kolom tabel barang, mis. "No. Nama Barang Qty Harga Jumlah".
_ITEM_HEADER = re.compile(
    r"^\s*(no\.?\s+)?(nama\s+barang|nama\s+item|item|barang|deskripsi|description)\b.*\b(qty|harga|jumlah|price|total)\b",
    re.IGNORECASE,
)
_ADDRESS = re.compile(
    r"\b(j[l1i]\.|jl\b|jln\b|jalan\b|kec\.|kecamatan|kel\.|kelurahan|kab\.|kabupaten|kota\b|"
    r"ruko\b|komplek|kompleks|gedung|blok\b|mall\b|plaza\b|rt\.?\s*\d|rw\.?\s*\d|no\.?\s*\d+\s*[,a-z])"
    r"|\b\d{5}\b",
    re.IGNORECASE,
)
_ADDRESS_EXCLUDE = re.compile(r"\b(telp|tlp|phone|hp|wa|npwp|transaksi|trx|struk|kasir|nota|invoice)\b", re.I)
_JL_FIX = re.compile(r"\bJ[1iI]\.", re.UNICODE)
_NUMBERED_HEADER = re.compile(r"^\s*no\.?\s", re.IGNORECASE)
_SKIP_RE = re.compile(
    r"\b("
    r"sub\s*total|subtotal|total|grand|harga\s*jual|tunai|cash|kembali(?:an)?|change|ppn|pajak|tax|"
    r"diskon|disc|discount|potongan|hemat|promo\s*hemat|debit|kredit|credit|visa|master(?:card)?|"
    r"qris|npwp|telp|tlp|phone|hp|kasir|cashier|dpp|bayar|pembayaran|jumlah|items?|qty|"
    r"card|kartu|saldo|poin|point|member|struk|nota|invoice|trx|tanggal|tgl|jam|layanan|"
    r"kritik|saran|terima\s*kasih|thank|kontak|sms|wa|whatsapp|www|http|email|admin|ref|waktu|pukul|"
    r"approval|appr|edc|bca|bri|bni|mandiri|ovo|gopay|dana|shopeepay|voucher\s*disc"
    r")\b",
    re.IGNORECASE,
)
_TOTAL_PATTERNS = [
    (0, re.compile(r"\bgrand\s*total\b", re.I)),
    (1, re.compile(r"\btotal\s*(belanja|bayar|harga|pembayaran|tagihan|rp)\b", re.I)),
    (2, re.compile(r"(?<!sub)(?<!sub )\btotal\b(?!\s*(item|qty|disc|diskon|hemat|potongan))", re.I)),
    (3, re.compile(r"\bsub\s*total\b|\bharga\s*jual\b", re.I)),
    (4, re.compile(r"\bjumlah\b(?!\s*(item|barang|qty))", re.I)),
]
_DATE_NUMERIC = [
    re.compile(r"\b(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})\b"),  # 2026-10-21
    re.compile(r"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b"),  # 21/10/2026, 21-10-26
]
_MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "mei": 5, "may": 5, "jun": 6, "jul": 7,
    "agu": 8, "agt": 8, "ags": 8, "aug": 8, "sep": 9, "okt": 10, "oct": 10, "nov": 11,
    "des": 12, "dec": 12,
}
_DATE_TEXT = re.compile(
    r"\b(\d{1,2})\s*[-/ ]?\s*(jan|feb|mar|apr|mei|may|jun|jul|agu|agt|ags|aug|sep|okt|oct|nov|des|dec)[a-z]*\.?\s*[-/ ]?\s*(\d{2,4})\b",
    re.IGNORECASE,
)
_TIME = re.compile(r"\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b")

# Satuan di antara qty dan "x": "1 pcs x 4.500", "2 btl @ 3.000".
_QTY_UNIT = re.compile(
    r"\b(\d{1,3})\s*(?:pcs|pc|psc|buah|bh|btl|pck|pack|pak|bks|unit|ea|lbr|sachet|sct|porsi|cup)\b\.?", re.I
)
# Angka ribuan yang terpecah spasi oleh OCR: "84, 300", "49 .500,00".
_SPLIT_THOUSANDS = [
    re.compile(r"(\d)\s*([.,])\s+(\d{3})(?!\d)"),
    re.compile(r"(\d)\s+([.,])(\d{3})(?!\d)"),
    # Desimal terpisah: "5.000, 00" -> "5.000,00"
    re.compile(r"(\d[.,]\d{3})\s*([.,])\s+(\d{2,3})(?![\d.,])"),
]
# Pasangan digit yang paling sering tertukar oleh OCR pada struk thermal.
_CONFUSABLE = {
    "0": "8963", "8": "0396", "9": "0874", "6": "0858", "3": "885", "5": "638",
    "1": "74", "7": "1", "4": "19", "2": "7",
}
# Token yang hampir seluruhnya angka; huruf mirip angka di dalamnya diperbaiki.
_DIGITISH = re.compile(r"^[\dOo@lI|.,\-]+$")
_DIGIT_FIX = str.maketrans({"O": "0", "o": "0", "@": "0", "l": "1", "I": "1", "|": "1"})
_DISCOUNT_RE = re.compile(r"\b(disc|diskon|discount|potongan|hemat|voucher)\b", re.I)
_CHARGE_RE = re.compile(r"\b(ppn|pajak|tax|service|servis|layanan|pb1|svc|biaya\s+lain)\b", re.I)
_PAYMENT_RE = re.compile(
    r"\b(tunai|cash|debit|kredit|credit|bayar|pembayaran|qris|ovo|gopay|dana|shopeepay|edc)\b", re.I
)
_SUBTOTAL_RE = re.compile(r"\bsub\s*total\b|\bharga\s*jual\b", re.I)
_QTY_FIRST_HEADER = re.compile(r"^\s*(qty|jml|kuantitas)\.?\s+(nama|barang|item|deskripsi|produk)\b", re.I)
_LEADING_QTY = re.compile(r"^(\d{1,2})\s*(?:[xX×]\s+|\s+)(?=[A-Za-z][A-Za-z.\-']{2,})")
# OCR membaca satuan "ml" sebagai "m1"/"mI"/"m|".
_ML_FIX = re.compile(r"(?<=\d)\s?m[1I|]\b")


def normalize_line(line: str) -> str:
    """Rapikan satu baris OCR sebelum dibaca: spasi, angka terpecah, huruf yang mirip angka."""
    line = re.sub(r"\s+", " ", line).strip()
    tokens = []
    for token in line.split(" "):
        if token == "=":
            continue  # "1 x Rp 4.500 = Rp 4.500"
        m = re.match(r"^([(\[:;]*)(.*?)([)\]:;]*)$", token)
        core = m.group(2)
        if _DIGITISH.match(core):
            digits = sum(c.isdigit() for c in core)
            alnum = sum(c.isalnum() or c in "@|" for c in core)
            if digits and digits / max(alnum, 1) >= 0.5:
                token = m.group(1) + core.translate(_DIGIT_FIX) + m.group(3)
        tokens.append(token)
    line = " ".join(tokens)
    for pattern in _SPLIT_THOUSANDS:
        line = pattern.sub(r"\1\2\3", line)
    return _QTY_UNIT.sub(r"\1", line)


def digit_distance(a: float, b: float) -> int:
    """Jarak edit antar-digit dua nominal (mis. 19400 vs 10400 = 1)."""
    s, t = str(int(round(a))), str(int(round(b)))
    prev = list(range(len(t) + 1))
    for i, cs in enumerate(s, 1):
        cur = [i]
        for j, ct in enumerate(t, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (cs != ct)))
        prev = cur
    return prev[-1]


def confusion_variants(value: float, max_changes: int = 2) -> dict[float, int]:
    """Nominal hasil mengganti 1-2 digit dengan digit yang mirip bentuknya (0<->8/9/6, 3<->8, ...).

    Nilai = jumlah digit yang diganti. Hanya hasil yang berakhiran "00" (harga rupiah
    lazim) yang diberi bobot normal; sisanya dihitung lebih mahal.
    """
    s = str(int(round(value)))
    out: dict[float, int] = {}
    frontier = {s: 0}
    for _ in range(max_changes):
        nxt: dict[str, int] = {}
        for text, cost in frontier.items():
            for i, ch in enumerate(text):
                for alt in _CONFUSABLE.get(ch, ""):
                    if i == 0 and alt == "0":
                        continue
                    cand = text[:i] + alt + text[i + 1:]
                    if cand != s and cand not in nxt:
                        nxt[cand] = cost + 1
        for cand, cost in nxt.items():
            v = float(cand)
            out[v] = min(out.get(v, 99), cost)
        frontier = nxt
    return out


def one_digit_variants(value: float) -> set[float]:
    """Semua nominal yang berbeda satu digit (ganti/hapus/sisip) dari `value`."""
    s = str(int(round(value)))
    out: set[str] = set()
    for i in range(len(s)):
        out.add(s[:i] + s[i + 1:])
        for d in "0123456789":
            out.add(s[:i] + d + s[i + 1:])
    for i in range(len(s) + 1):
        for d in "0123456789":
            out.add(s[:i] + d + s[i:])
    return {float(v) for v in out if v and not v.startswith("0") and v != s}


def parse_money(value: str) -> float | None:
    """Ubah teks uang ala Indonesia menjadi angka.

    '22.500' -> 22500, '22,500' -> 22500, '1.250.000' -> 1250000,
    '22.500,00' -> 22500, '22,500.00' -> 22500, 'Rp15.000' -> 15000.
    """
    v = re.sub(r"(?i)rp\.?", "", value).replace(" ", "").strip()
    negative = v.startswith("-") or v.endswith("-")
    v = v.strip("-").strip(".,")
    if not v or not re.fullmatch(r"[\d.,]+", v):
        return None
    if "." in v and "," in v:
        # Pemisah yang muncul terakhir adalah pemisah desimal.
        decimal_sep = "." if v.rfind(".") > v.rfind(",") else ","
        thousand_sep = "," if decimal_sep == "." else "."
        v = v.replace(thousand_sep, "").replace(decimal_sep, ".")
    elif "." in v or "," in v:
        sep = "." if "." in v else ","
        parts = v.split(sep)
        if all(len(p) == 3 for p in parts[1:]):
            v = "".join(parts)  # pemisah ribuan
        elif len(parts) == 2 and len(parts[1]) in (1, 2):
            v = parts[0] + "." + parts[1]  # pemisah desimal
        else:
            v = "".join(parts)
    try:
        amount = float(v)
    except ValueError:
        return None
    return -amount if negative else amount


def _is_number_token(token: str) -> bool:
    return bool(_NUMBER_TOKEN.match(token)) and any(c.isdigit() for c in token)


def _clean_merchant(line: str) -> str:
    """Buang simbol sisa OCR di depan/belakang nama toko ("] Toko Sejahtera", "@ Indomaret")."""
    had_junk = bool(re.match(r"^\s*[^0-9A-Za-z\s]", line))
    cleaned = re.sub(r"^[^0-9A-Za-z]+", "", line)
    cleaned = re.sub(r"[^0-9A-Za-z)]+$", "", cleaned)
    if had_junk:
        # Logo terbaca jadi 1-2 huruf yatim ("�EJ Toko ..."); "UD Sinar Jaya" tanpa simbol tidak disentuh.
        cleaned = re.sub(r"^(?:[A-Z]{1,2}|[a-z]|\d)\s+(?=[A-Z][a-z])", "", cleaned)
    return cleaned.strip()


def _letters(text: str) -> int:
    return sum(c.isalpha() for c in text)


def _valid_price(value: float | None) -> bool:
    return value is not None and MIN_PRICE <= value <= MAX_PRICE


class RegexReceiptParser(ReceiptParser):
    name = "regex"

    # ------------------------------------------------------------- public
    def parse(self, text: str) -> ParsedReceipt:
        raw_lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
        raw_lines = [line for line in raw_lines if line]
        lines = [normalize_line(line) for line in raw_lines]
        total_amount, total_index = self._find_total(lines)
        corrections: list[str] = []
        items = self._find_items(lines, stop_at=total_index, corrections=corrections)
        receipt = ParsedReceipt(
            merchant_name=self._find_merchant(raw_lines),
            merchant_address=self._find_address(raw_lines),
            transaction_date=self._find_date(lines),
            total_amount=total_amount,
            items=items,
            subtotal_amount=self._find_subtotal(lines),
            discount_amount=self._find_discounts(lines, total_index),
            has_charges=any(_CHARGE_RE.search(l) and self._last_amount(l) for l in lines),
            corrections=corrections,
        )
        self._reconcile(receipt, lines)
        return receipt

    # ------------------------------------------------------- konsistensi
    def _find_subtotal(self, lines: list[str]) -> float | None:
        for line in lines:
            if _SUBTOTAL_RE.search(line) and not _ITEM_HEADER.search(line):
                amount = self._last_amount(line)
                if amount is not None:
                    return amount
        return None

    def _find_discounts(self, lines: list[str], stop_at: int | None) -> float:
        total = 0.0
        for line in lines[: stop_at if stop_at is not None else len(lines)]:
            if _DISCOUNT_RE.search(line) and not _SUBTOTAL_RE.search(line):
                amount = self._last_amount(line)
                if amount:
                    total += abs(amount)
        return total

    def _payment_amounts(self, lines: list[str]) -> list[float]:
        out = []
        for line in lines:
            if _PAYMENT_RE.search(line) and not re.search(r"kembali|change", line, re.I):
                amount = self._last_amount(line)
                if amount:
                    out.append(amount)
        return out

    def _reconcile(self, receipt: ParsedReceipt, lines: list[str]) -> None:
        """Cocokkan jumlah harga barang dengan subtotal/total struk.

        OCR sering salah membaca SATU digit ("144.000" untuk 44.000). Bila tepat satu
        harga barang yang, setelah diubah satu digit, membuat jumlahnya sama persis
        dengan subtotal/total, harga itu dikoreksi. Total yang salah baca dikoreksi
        bila jumlah barang cocok dengan nominal pembayaran (debit/bayar) yang tercetak.
        """
        items = [i for i in receipt.items if i.price is not None]
        if not items:
            return
        items_sum = sum(i.price for i in items)
        payments = self._payment_amounts(lines)

        target = receipt.subtotal_amount
        if target is None and receipt.total_amount is not None and not receipt.has_charges:
            target = receipt.total_amount + receipt.discount_amount
        if target is None and not receipt.has_charges:
            # Total tidak terbaca: pakai nominal pembayaran yang sama dengan jumlah barang.
            for amount in payments:
                if abs(amount - (items_sum - receipt.discount_amount)) < 1:
                    receipt.total_amount = amount
                    receipt.corrections.append("total diambil dari baris pembayaran")
                    return
        if target is None or abs(items_sum - target) < 1:
            return

        delta = target - items_sum
        item_fix = self._cheapest_item_fix(items, delta)

        # Alternatif: barangnya benar, totalnya yang salah baca.
        total_fix: tuple[float, float] | None = None  # (biaya, total baru)
        expected_total = items_sum - receipt.discount_amount
        if receipt.subtotal_amount is None and not receipt.has_charges and receipt.total_amount is not None:
            variants = confusion_variants(receipt.total_amount)
            cost = variants.get(expected_total)
            if cost is None and digit_distance(receipt.total_amount, expected_total) <= 1:
                cost = 2
            supported = any(abs(p - expected_total) < 1 for p in payments)
            odd_total = receipt.total_amount % 100 != 0 and expected_total % 100 == 0
            # Total tercetak hanya diganti bila ada bukti kuat: nominal pembayaran sama dengan
            # jumlah barang, atau total tercetak tidak lazim (bukan kelipatan 100).
            if cost is not None and (supported or odd_total):
                total_fix = (cost - (0.5 if supported else 0), expected_total)

        if total_fix and (item_fix is None or total_fix[0] <= item_fix[0]):
            receipt.corrections.append(f"total {receipt.total_amount:,.0f} -> {total_fix[1]:,.0f}")
            receipt.total_amount = total_fix[1]
            return
        if item_fix is None:
            return
        for item, candidate in item_fix[1]:
            receipt.corrections.append(f"harga '{item.name}' {item.price:,.0f} -> {candidate:,.0f}")
            item.price = candidate
            item.price_corrected = True
            if item.quantity > 1 and candidate % item.quantity == 0:
                item.unit_price = candidate / item.quantity
            elif item.quantity == 1:
                item.unit_price = candidate

    @staticmethod
    def _cheapest_item_fix(items: list[ParsedItem], delta: float):
        """Cari koreksi 1-2 harga barang termurah yang membuat jumlahnya bergeser tepat `delta`.

        Biaya: jumlah digit yang diganti (pasangan digit mirip), +1 untuk sisip/hapus digit,
        +0,5 bila hasilnya tidak berakhiran "00". Hasil kembar dengan biaya sama = ragu -> None.
        """
        options: list[tuple[float, ParsedItem, float, float]] = []  # (biaya, item, harga baru, pergeseran)
        for item in items:
            cands = {v: float(c) for v, c in confusion_variants(item.price).items()}
            for v in one_digit_variants(item.price):
                cands.setdefault(v, 2.0)
            for value, cost in cands.items():
                if not _valid_price(value):
                    continue
                if value % 100:
                    cost += 0.5
                options.append((cost, item, value, value - item.price))

        best: list[tuple[float, list]] = []
        by_shift: dict[float, list] = {}
        for opt in options:
            if abs(opt[3] - delta) < 1:
                best.append((opt[0], [(opt[1], opt[2])]))
            by_shift.setdefault(round(opt[3]), []).append(opt)
        for opt in options:
            for other in by_shift.get(round(delta - opt[3]), []):
                if other[1] is not opt[1] and id(opt[1]) < id(other[1]):
                    best.append((opt[0] + other[0], [(opt[1], opt[2]), (other[1], other[2])]))
        if not best:
            return None
        best.sort(key=lambda b: b[0])
        lowest = best[0][0]
        if lowest > 3.5:
            return None
        tied = {tuple((id(i), v) for i, v in b[1]) for b in best if b[0] == lowest}
        if len(tied) > 1:
            return None
        return best[0]

    # ------------------------------------------------------------ helpers
    def _merchant_candidate(self, line: str) -> str | None:
        cleaned = _clean_merchant(line)
        if _letters(cleaned) < 3 or _letters(cleaned) / max(len(cleaned), 1) < 0.5:
            return None
        if self._has_date(cleaned) or _SKIP_RE.search(cleaned):
            return None
        if _ADDRESS.search(cleaned) and not _ADDRESS_EXCLUDE.search(cleaned):
            return None  # baris alamat (logo toko tidak terbaca), bukan nama toko
        return cleaned

    _GENERIC_WORDS = {"belanja", "hemat", "terima", "kasih", "selamat", "kembali", "mudah", "murah",
                      "dekat", "setiap", "hari", "lebih", "hidup", "berbelanja", "malang", "jalan", "raya"}

    def _find_merchant(self, lines: list[str]) -> str | None:
        """Nama toko di bagian atas struk.

        Logo toko sering terbaca acak ("Gndomanal", "Ww Indomart"). Calon nama yang
        katanya tercetak LAGI di bagian lain struk ("Indomaret Gondanglegi" ... "di Indomaret")
        lebih dipercaya; bila tidak ada, dipakai calon paling atas.
        """
        top = lines[:6]
        rest_words: dict[str, int] = {}
        for line in lines:
            for w in re.findall(r"[A-Za-z]{4,}", line):
                rest_words[w.lower()] = rest_words.get(w.lower(), 0) + 1

        best: tuple[int, int, str] | None = None  # (skor, -posisi, nama)
        for index, line in enumerate(top):
            cleaned = self._merchant_candidate(line)
            if not cleaned:
                continue
            # Logo/nama besar sering terpecah dua baris: "J Toko" + "Sejahtera".
            words = cleaned.split()
            nxt = self._merchant_candidate(top[index + 1]) if index + 1 < len(top) else None
            if (
                nxt and len(words) <= 2 and len(nxt.split()) <= 2
                and not re.search(r"\d", nxt) and nxt[:1].isupper()
                and not re.search(r"\b(belanja|hemat|murah|terima)\b", nxt, re.I)
            ):
                if len(words) == 2 and len(words[0]) == 1:
                    words = words[1:]  # huruf yatim dari logo ("J Toko")
                cleaned = f"{' '.join(words)} {nxt}"
                words = cleaned.split()
            recurring = [
                i for i, w in enumerate(words)
                if len(w) >= 4 and w.lower() not in self._GENERIC_WORDS and rest_words.get(w.lower(), 0) >= 2
            ]
            if recurring and recurring[0] > 0 and all(len(w) <= 2 for w in words[: recurring[0]]):
                words = words[recurring[0]:]  # sisa logo di depan nama ("Ww Indomart")
                cleaned = " ".join(words)
            key = (1 if recurring else 0, -index, cleaned)
            if best is None or key[:2] > best[:2]:
                best = key
        return best[2][:200] if best else None

    def _find_address(self, lines: list[str]) -> str | None:
        """Alamat toko di bagian atas struk (maks. 2 baris berurutan)."""
        parts: list[str] = []
        for line in lines[:10]:
            cleaned = line.strip(" -=*#:|")
            if _ADDRESS.search(cleaned) and not _ADDRESS_EXCLUDE.search(cleaned):
                # OCR sering membaca "Jl." sebagai "J1." / "Ji.".
                parts.append(_JL_FIX.sub("Jl.", cleaned))
                if len(parts) == 2:
                    break
            elif parts:
                break
        return ", ".join(parts)[:300] if parts else None

    @staticmethod
    def _has_date(line: str) -> bool:
        return any(p.search(line) for p in _DATE_NUMERIC) or bool(_DATE_TEXT.search(line))

    def _find_date(self, lines: list[str]) -> datetime | None:
        for index, line in enumerate(lines):
            found = self._date_in_line(line)
            if not found:
                continue
            # Jam biasanya di baris yang sama atau baris sesudahnya.
            for candidate in (line, lines[index + 1] if index + 1 < len(lines) else ""):
                t = _TIME.search(candidate)
                if t:
                    return found.replace(
                        hour=int(t.group(1)), minute=int(t.group(2)), second=int(t.group(3) or 0)
                    )
            return found
        return None

    @staticmethod
    def _date_in_line(line: str) -> datetime | None:
        candidates: list[tuple[int, int, int]] = []
        m = _DATE_NUMERIC[0].search(line)
        if m:
            candidates.append((int(m.group(1)), int(m.group(2)), int(m.group(3))))
        m = _DATE_NUMERIC[1].search(line)
        if m:
            candidates.append((int(m.group(3)), int(m.group(2)), int(m.group(1))))
        m = _DATE_TEXT.search(line)
        if m:
            candidates.append((int(m.group(3)), _MONTHS[m.group(2).lower()[:3]], int(m.group(1))))
        for year, month, day in candidates:
            if year < 100:
                year += 2000
            if not 2000 <= year <= datetime.now().year + 1:
                continue
            try:
                return datetime(year, month, day)
            except ValueError:
                continue
        return None

    @staticmethod
    def _last_amount(line: str) -> float | None:
        tokens = [t for t in line.split() if _is_number_token(t)]
        for token in reversed(tokens):
            value = parse_money(token)
            if _valid_price(value):
                return value
        return None

    def _find_total(self, lines: list[str]) -> tuple[float | None, int | None]:
        best: tuple[int, float, int] | None = None
        for index, line in enumerate(lines):
            if _ITEM_HEADER.search(line):
                continue  # "No Nama Barang Qty Harga Total" = judul kolom, bukan total
            for priority, pattern in _TOTAL_PATTERNS:
                if not pattern.search(line):
                    continue
                amount = self._last_amount(line)
                if amount is None and index + 1 < len(lines) and _letters(lines[index + 1]) <= 2:
                    amount = self._last_amount(lines[index + 1])
                if amount is not None and (best is None or priority < best[0]):
                    best = (priority, amount, index)
                break
        if best is None:
            return None, None
        # Barang berhenti di baris total/subtotal pertama yang ditemukan.
        first_total = next(
            (
                i
                for i, line in enumerate(lines)
                if not _ITEM_HEADER.search(line)
                and self._last_amount(line) is not None
                and any(p.search(line) for pr, p in _TOTAL_PATTERNS if pr <= 3)
            ),
            best[2],
        )
        return best[1], first_total

    def _split_line(self, line: str) -> tuple[str, list[str]]:
        """Pisahkan teks nama dan token angka/qty di ujung kanan baris."""
        tokens = [t for t in line.split() if t.lower().rstrip(".:") != "rp"]
        tail: list[str] = []
        while tokens and (_is_number_token(tokens[-1]) or _QTY_PREFIX.match(tokens[-1])):
            tail.insert(0, tokens.pop())
        # Kolom Qty "1" yang salah baca OCR ("l", "il", "al", "|") tepat sebelum
        # kolom harga: anggap qty 1 dan jangan masukkan ke nama barang.
        # Hanya bila kolom qty memang hilang (tinggal 2 angka: harga & jumlah),
        # agar "Minyak Goreng 1 L 2 15.500 31.000" tidak kehilangan huruf L.
        numeric_tail = [t for t in tail if _is_number_token(t)]
        if tokens and len(numeric_tail) == 2 and len(tail) == 2 and tokens[-1].lower() in _MISREAD_ONE:
            tokens.pop()
            tail.insert(0, "1")
        # Buang kode barang (PLU) di awal nama.
        while tokens and tokens[0].isdigit() and len(tokens[0]) >= 4:
            tokens.pop(0)
        return " ".join(tokens).strip(" -:.*#|"), tail

    @staticmethod
    def _interpret_tail(
        tail: list[str], corrections: list[str] | None = None
    ) -> tuple[int, float | None, float | None, list[str]] | None:
        """Kembalikan (qty, harga_satuan, harga_total, sisa_token) dari token angka.

        `sisa_token` = angka yang ternyata bagian nama barang (ukuran "60", "335"),
        dikembalikan ke nama. Bila qty x harga satuan berbeda 1 digit dari harga total,
        salah satunya adalah salah baca OCR dan dibetulkan.
        """
        qty_hint = None
        numbers: list[float] = []
        tokens: list[str] = []
        for token in tail:
            q = _QTY_PREFIX.match(token)
            if q:
                if q.group(1) or q.group(2):
                    qty_hint = int(q.group(1) or q.group(2))
                elif numbers and numbers[-1] < 1000 and float(numbers[-1]).is_integer():
                    qty_hint = int(numbers.pop())
                    tokens.pop()
                continue
            value = parse_money(token)
            if value is not None:
                numbers.append(value)
                tokens.append(token)
        if not numbers:
            return None
        total = numbers[-1]
        if total < 0 or not _valid_price(total):
            return None
        qty, unit, used = 1, None, 1
        if qty_hint:
            qty = qty_hint
            unit = numbers[-2] if len(numbers) >= 2 else round(total / qty_hint, 2)
            used = 2 if len(numbers) >= 2 else 1
        elif len(numbers) >= 3 and 0 < numbers[-3] < 1000 and numbers[-3].is_integer() and _valid_price(numbers[-2]):
            qty, unit, used = int(numbers[-3]), numbers[-2], 3
        elif len(numbers) >= 2:
            first = numbers[-2]
            if 0 < first < 1000 and first.is_integer():
                # "2 18.000" = qty 2; "Minyak Kayu Putih 60 21.500": 60 adalah ukuran, bukan qty.
                if total % first == 0 and total / first >= MIN_PRICE:
                    qty, unit, used = int(first), round(total / first, 2), 2
            elif _valid_price(first) and first <= total and total % first == 0:
                qty, unit, used = int(total // first), first, 2
        if unit and qty > 1 and abs(unit - total) < 1:
            # "4, 62.000 62.000": harga satuan = total -> qty 1 yang salah baca.
            if corrections is not None:
                corrections.append(f"qty {qty} -> 1")
            qty = 1
        if unit and qty >= 1 and abs(qty * unit - total) >= 1:
            expected = qty * unit
            # Yang salah bisa harga total ATAU harga satuan. Putuskan hanya bila salah satunya
            # jelas tidak lazim (harga rupiah hampir selalu berakhiran "00"); selain itu
            # biarkan pencocokan dengan subtotal/total struk yang memutuskan.
            total_round, expected_round = total % 100 == 0, expected % 100 == 0
            if digit_distance(total, expected) <= 1 and expected_round and not total_round:
                if corrections is not None:
                    corrections.append(f"harga {total:,.0f} -> {expected:,.0f} (qty x harga)")
                total = expected
            elif total % qty == 0 and digit_distance(unit, total / qty) <= 1:
                unit = total / qty
        # Hanya angka kecil tanpa pemisah (ukuran "60", "335") yang dikembalikan ke nama;
        # nominal harga ("7.500") yang tidak terpakai dibuang.
        leftover = [t for t in tokens[: max(0, len(tokens) - used)] if t.isdigit() and int(t) < 1000]
        return max(qty, 1), unit, total, leftover

    @staticmethod
    def _is_price_only(line: str) -> bool:
        """Baris tanpa nama barang, hanya qty/harga: "  2 x 5,200   10,400"."""
        if _SKIP_RE.search(line) or _letters(re.sub(r"(?i)\brp\.?|[x@]", "", line)) >= 2:
            return False
        return any(_is_number_token(t) for t in line.split())

    @staticmethod
    def _row_number(name: str) -> int | None:
        """Nomor urut di awal nama ("2 USB...", "3. Kabel", "Al Headphone" = 1)."""
        m = _ROW_NUMBER.match(name)
        if not m:
            return None
        token = m.group(1).lower()
        return 1 if token in _MISREAD_ONE else int(token)

    def _strip_row_numbers(self, items: list[ParsedItem], numbered_header: bool) -> list[ParsedItem]:
        """Buang nomor urut baris dari nama barang.

        Hanya dilakukan bila struk jelas bernomor: ada kolom "No." di header,
        atau nomor di awal nama berurutan 1, 2, 3, ... Dengan begitu format
        "2 INDOMIE GORENG" (qty di depan) tidak ikut terpotong.
        """
        numbers = [self._row_number(i.name) for i in items]
        present = [n for n in numbers if n is not None]
        # OCR kadang memindah baris ("5 Tepung" di atas), jadi nilai diurutkan dulu.
        ordered = sorted(present)
        if len(set(ordered)) != len(ordered):
            ordered = present  # ada nomor kembar: bukan nomor urut
        steps = [b - a for a, b in zip(ordered, ordered[1:])]
        sequential = (
            len(present) >= 2
            and len(present) >= len(items) / 2
            # Mulai dari 1 (atau 2 bila baris pertama tak terbaca dan nomornya cukup banyak).
            and (ordered[0] == 1 or (ordered[0] == 2 and len(ordered) >= 3))
            # Naik satu-satu; boleh satu kali loncat 2 (satu baris tak terbaca).
            and all(1 <= s <= 2 for s in steps)
            and sum(1 for s in steps if s == 2) <= 1
        )
        # Nomor urut sungguhan biasanya sudah berurutan, atau barisnya punya kolom qty/harga
        # sendiri. "2 Air Mineral / 1 Americano" (kafe) = qty, bukan nomor urut.
        in_order = sum(1 for a, b in zip(present, present[1:]) if b < a) == 0
        has_columns = sum(1 for i in items if i.unit_price is not None) >= len(items) / 2
        sequential = sequential and (in_order or has_columns)
        if not (numbered_header or sequential):
            return items
        result: list[ParsedItem] = []
        for item, number in zip(items, numbers):
            if number is not None:
                stripped = _ROW_NUMBER.sub("", item.name, count=1).strip()
                if _letters(stripped) >= 2:
                    item = replace(item, name=stripped[:255])
            result.append(item)
        return result

    def _find_items(
        self, lines: list[str], stop_at: int | None, corrections: list[str] | None = None
    ) -> list[ParsedItem]:
        items: list[ParsedItem] = []
        pending_name: str | None = None
        numbered_header = False
        qty_first_header = False  # "Qty Nama Barang Harga Total": angka di depan = qty
        limit = stop_at if stop_at is not None else len(lines)
        for index, line in enumerate(lines[:limit]):
            next_line = lines[index + 1] if index + 1 < limit else ""
            if _QTY_FIRST_HEADER.search(line):
                qty_first_header = True
                pending_name = None
                continue
            # Baris alamat toko di bagian atas (kode pos 60241 bukan harga barang).
            if index < 10 and _ADDRESS.search(line) and not _ADDRESS_EXCLUDE.search(line):
                pending_name = None
                continue
            if _ITEM_HEADER.search(line):
                # Baris judul kolom ("No. Nama Barang Qty Harga Jumlah"), bukan barang.
                numbered_header = numbered_header or bool(_NUMBERED_HEADER.search(line))
                pending_name = None
                continue
            if _SKIP_RE.search(line) or self._has_date(line) or _TIME.search(line):
                pending_name = None
                continue
            name, tail = self._split_line(line)
            numeric_tail = [t for t in tail if _is_number_token(t)]
            # Nama barang yang diakhiri angka ukuran ("ABC SMBL ASLI 335") diikuti baris
            # harga tanpa nama ("2 x 12,700  25,400"): seluruh baris ini adalah nama.
            if _letters(name) >= 3 and len(numeric_tail) <= 1 and self._is_price_only(next_line):
                pending_name = line.strip(" -:.*#|")
                if tail and tail[0].isdigit() and len(tail[0]) >= 6:
                    pending_name = name  # kode barang di belakang, bukan bagian nama
                # Kode barang (PLU/barcode) di depan nama: "8994330348 TEH BTL SOSRO".
                pending_name = re.sub(r"^\d{4,}\s+", "", pending_name)
                continue
            before = len(corrections) if corrections is not None else 0
            parsed = self._interpret_tail(tail, corrections) if tail else None
            row_corrected = corrections is not None and len(corrections) > before

            if parsed is None:
                # Baris tanpa harga: mungkin nama barang yang harganya di baris berikut.
                pending_name = name if _letters(name) >= 3 else None
                continue

            qty, unit, total, leftover = parsed
            if leftover and _letters(name) >= 2:
                name = f"{name} {' '.join(leftover)}"
            if _letters(name) < 2:
                if pending_name:
                    name = pending_name
                else:
                    continue
            pending_name = None
            items.append(ParsedItem(name=name[:255], price=total, quantity=qty, unit_price=unit,
                                    price_corrected=row_corrected))
        if not qty_first_header:
            items = self._strip_row_numbers(items, numbered_header)
        return [self._leading_quantity(item) for item in items]

    @staticmethod
    def _leading_quantity(item: ParsedItem) -> ParsedItem:
        """Format kafe/restoran: qty di depan nama ("2 Croissant Butter 44.000")."""
        item = replace(item, name=_ML_FIX.sub("ml", item.name))
        m = _LEADING_QTY.match(item.name)
        if not m or item.quantity != 1 or item.price is None:
            return item
        qty = int(m.group(1))
        if qty < 1 or item.price % qty != 0 or item.price / qty < MIN_PRICE:
            return item
        if item.unit_price is not None and abs(qty * item.unit_price - item.price) >= 1:
            # Baris punya kolom harga satuan sendiri yang tidak cocok dengan angka di depan:
            # angka itu bukan qty (mis. nomor urut).
            return item
        name = item.name[m.end():].strip()
        unit = item.price / qty
        return replace(item, name=name[:255], quantity=qty, unit_price=unit)
