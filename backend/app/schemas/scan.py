from pydantic import BaseModel, Field

from app.schemas.category import CategoryBrief
from app.schemas.common import LocalDateTime


class PredictionOut(BaseModel):
    category_id: int | None = None
    category: CategoryBrief | None = None
    confidence_score: float | None = Field(default=None, description="0..1")
    confidence_percent: int | None = Field(default=None, description="0..100, siap ditampilkan")
    prediction_source: str | None = Field(
        default=None, description="user_history | keyword_rules | ml_model"
    )
    needs_review: bool = Field(description="true = tandai kuning 'Periksa' di layar koreksi")


class ScanItemOut(PredictionOut):
    index: int
    item_name: str
    quantity: int = 1
    unit_price: float | None = None
    item_price: float | None = None
    predicted_category_id: int | None = Field(
        default=None, description="Kirim balik saat menyimpan agar koreksi pengguna tercatat"
    )
    price_corrected: bool = Field(
        default=False, description="Harga diubah otomatis karena diduga salah baca OCR -> tandai untuk dicek"
    )
    name_corrected: bool = Field(
        default=False, description="Nama diperbaiki otomatis (huruf hilang / koreksi pengguna sebelumnya)"
    )
    suspicious: bool = Field(
        default=False, description="Tampak janggal (harga tidak lazim / sisa angka di nama) -> minta dicek"
    )
    uncertain_words: list[str] = Field(
        default_factory=list, description="Kata pada nama yang diragukan OCR -> disorot untuk dicek pengguna"
    )


class ScanOut(BaseModel):
    scan_id: str = Field(description="Kirim di POST /receipts agar foto ikut tersimpan")
    image_url: str
    merchant_name: str | None = None
    merchant_address: str | None = None
    transaction_date: LocalDateTime | None = None
    total_amount: float | None = None
    items_total: float
    total_matches: bool | None = Field(
        description="Apakah total struk sama dengan jumlah harga barang (null jika total tak terbaca)"
    )
    review_count: int = Field(description="Jumlah barang yang perlu diperiksa pengguna")
    items: list[ScanItemOut]
    warnings: list[str]
    raw_text: str
    consistent: bool = Field(
        default=False, description="Jumlah harga barang = subtotal/total struk (angka hampir pasti benar)"
    )
    field_confidence: dict[str, str] = Field(
        default_factory=dict, description="Keyakinan per kolom: merchant/date/total/items -> tinggi|sedang|rendah"
    )
    review_fields: list[str] = Field(default_factory=list, description="Kolom yang perlu dicek pengguna")
    ocr_source: str = Field(default="tesseract", description="Sumber bacaan terpilih (tesseract / ML Kit (HP) / ...)")


class ClassifyRequest(BaseModel):
    texts: list[str] = Field(min_length=1, max_length=100, examples=[["SUSU UHT 1L", "RINSO 800G"]])


class ClassifyItemOut(PredictionOut):
    text: str
