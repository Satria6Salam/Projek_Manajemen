"""Parser struk berbasis aturan (regex) untuk format minimarket Indonesia.

Format baris barang yang dikenali, contoh:
    ROTI TAWAR 500G            22.500
    SUSU UHT 1L   2 x 9.000    18.000
    SUSU UHT 1L   2  9.000     18.000
    VITAMIN C 10 TABLET                      (nama di satu baris)
      1 x 15.000               15.000        (harga di baris berikutnya)
"""
import re
from datetime import datetime

from app.integrations.parser.base import ParsedItem, ParsedReceipt, ReceiptParser

MIN_PRICE = 100
MAX_PRICE = 100_000_000

_NUMBER_TOKEN = re.compile(r"^-?(?:rp\.?)?-?\d[\d.,]*$", re.IGNORECASE)
_QTY_PREFIX = re.compile(r"^(\d{1,3})\s*[xX@*]$|^[xX@*]$|^[xX@*](\d{1,3})$")
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
    r"kritik|saran|terima\s*kasih|thank|kontak|sms|wa|whatsapp|www|http|email|admin|ref|"
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
        cleaned = re.sub(r"^(?:[A-Z]{1,2}|[a-z])\s+(?=[A-Z][a-z])", "", cleaned)
    return cleaned.strip()


def _letters(text: str) -> int:
    return sum(c.isalpha() for c in text)


def _valid_price(value: float | None) -> bool:
    return value is not None and MIN_PRICE <= value <= MAX_PRICE


class RegexReceiptParser(ReceiptParser):
    name = "regex"

    # ------------------------------------------------------------- public
    def parse(self, text: str) -> ParsedReceipt:
        lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
        lines = [line for line in lines if line]
        total_amount, total_index = self._find_total(lines)
        return ParsedReceipt(
            merchant_name=self._find_merchant(lines),
            merchant_address=self._find_address(lines),
            transaction_date=self._find_date(lines),
            total_amount=total_amount,
            items=self._find_items(lines, stop_at=total_index),
        )

    # ------------------------------------------------------------ helpers
    def _find_merchant(self, lines: list[str]) -> str | None:
        for line in lines[:6]:
            cleaned = _clean_merchant(line)
            if _letters(cleaned) < 3 or _letters(cleaned) / max(len(cleaned), 1) < 0.5:
                continue
            if self._has_date(cleaned) or _SKIP_RE.search(cleaned):
                continue
            return cleaned[:200]
        return None

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
            if not 2000 <= year <= 2100:
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
    def _interpret_tail(tail: list[str]) -> tuple[int, float | None, float | None] | None:
        """Kembalikan (qty, harga_satuan, harga_total) dari token angka."""
        qty_hint = None
        numbers: list[float] = []
        for token in tail:
            q = _QTY_PREFIX.match(token)
            if q:
                if q.group(1) or q.group(2):
                    qty_hint = int(q.group(1) or q.group(2))
                elif numbers and numbers[-1] < 1000 and float(numbers[-1]).is_integer():
                    qty_hint = int(numbers.pop())
                continue
            value = parse_money(token)
            if value is not None:
                numbers.append(value)
        if not numbers:
            return None
        total = numbers[-1]
        if total < 0 or not _valid_price(total):
            return None
        qty, unit = 1, None
        if qty_hint:
            qty = qty_hint
            unit = numbers[-2] if len(numbers) >= 2 else round(total / qty_hint, 2)
        elif len(numbers) >= 3 and 0 < numbers[-3] < 1000 and abs(numbers[-3] * numbers[-2] - total) < 1:
            qty, unit = int(numbers[-3]), numbers[-2]
        elif len(numbers) >= 2:
            first = numbers[-2]
            if 0 < first < 1000 and first.is_integer():
                qty = int(first)
                unit = round(total / qty, 2)
            elif _valid_price(first) and first <= total and total % first == 0:
                qty, unit = int(total // first), first
        return max(qty, 1), unit, total

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
        if not (numbered_header or sequential):
            return items
        result: list[ParsedItem] = []
        for item, number in zip(items, numbers):
            if number is not None:
                stripped = _ROW_NUMBER.sub("", item.name, count=1).strip()
                if _letters(stripped) >= 2:
                    item = ParsedItem(stripped[:255], item.price, item.quantity, item.unit_price)
            result.append(item)
        return result

    def _find_items(self, lines: list[str], stop_at: int | None) -> list[ParsedItem]:
        items: list[ParsedItem] = []
        pending_name: str | None = None
        numbered_header = False
        limit = stop_at if stop_at is not None else len(lines)
        for index, line in enumerate(lines[:limit]):
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
            parsed = self._interpret_tail(tail) if tail else None

            if parsed is None:
                # Baris tanpa harga: mungkin nama barang yang harganya di baris berikut.
                pending_name = name if _letters(name) >= 3 else None
                continue

            qty, unit, total = parsed
            if _letters(name) < 2:
                if pending_name:
                    name = pending_name
                else:
                    continue
            pending_name = None
            items.append(ParsedItem(name=name[:255], price=total, quantity=qty, unit_price=unit))
        return self._strip_row_numbers(items, numbered_header)
