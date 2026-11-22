from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class ParsedItem:
    name: str
    price: float | None  # harga total baris
    quantity: int = 1
    unit_price: float | None = None
    # Harga diubah otomatis karena diduga salah baca OCR (perlu dicek pengguna).
    price_corrected: bool = False
    # Nama diperbaiki otomatis (huruf hilang dipulihkan / dari koreksi pengguna sebelumnya).
    name_corrected: bool = False
    # Tampak janggal (harga tidak lazim / ada sisa angka di nama) -> minta pengguna cek.
    suspicious: bool = False


@dataclass
class ParsedReceipt:
    merchant_name: str | None = None
    merchant_address: str | None = None
    transaction_date: datetime | None = None
    total_amount: float | None = None
    items: list[ParsedItem] = field(default_factory=list)
    # Subtotal (sebelum pajak/biaya layanan) bila tercetak; dipakai untuk mencocokkan jumlah barang.
    subtotal_amount: float | None = None
    # Jumlah potongan/diskon yang tercetak di antara barang.
    discount_amount: float = 0.0
    # Ada baris pajak/biaya layanan sehingga total boleh lebih besar dari jumlah barang.
    has_charges: bool = False
    # Catatan koreksi otomatis (mis. harga yang diperbaiki karena salah baca 1 digit).
    corrections: list[str] = field(default_factory=list)


class ReceiptParser(ABC):
    """Kontrak pengubah teks OCR menjadi data struk terstruktur."""

    name: str = "base"

    @abstractmethod
    def parse(self, text: str) -> ParsedReceipt:
        ...
