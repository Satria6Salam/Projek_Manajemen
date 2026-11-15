from datetime import date

from pydantic import BaseModel, Field

from app.schemas.category import CategoryBrief
from app.schemas.common import LocalDateTime
from app.schemas.receipt import ReceiptSummaryOut


class CategorySpendingOut(BaseModel):
    category: CategoryBrief | None = Field(description="null = barang tanpa kategori")
    description: str | None = None
    amount: float
    percentage: float = Field(description="Persentase terhadap total barang bulan itu (0-100)")
    item_count: int


class CategoryBreakdownOut(BaseModel):
    month: str = Field(examples=["2026-10"])
    month_label: str = Field(examples=["Oktober 2026"])
    total_amount: float = Field(description="Jumlah harga semua barang bulan itu")
    categories: list[CategorySpendingOut]


class MonthlyPointOut(BaseModel):
    month: str
    month_label: str
    total_spent: float
    receipt_count: int


class DashboardOut(BaseModel):
    month: str
    month_label: str
    total_spent: float = Field(description="Total pengeluaran (jumlah total_amount struk)")
    receipt_count: int
    item_count: int
    previous_month_total: float
    change_percent: float | None = Field(description="Perubahan vs bulan lalu, null jika bulan lalu 0")
    categories: list[CategorySpendingOut]
    recent_receipts: list[ReceiptSummaryOut]


class YearlyPointOut(BaseModel):
    year: int
    total_spent: float
    receipt_count: int


class PeriodReceiptOut(BaseModel):
    id: int
    merchant_name: str | None
    transaction_date: LocalDateTime | None
    total_amount: float


class PeriodOut(BaseModel):
    date_from: date
    date_to: date
    total_spent: float = Field(description="Jumlah total_amount struk dalam rentang")
    receipt_count: int
    categories: list[CategorySpendingOut] = Field(description="Hanya kategori yang punya pengeluaran")
    receipts: list[PeriodReceiptOut] = Field(description="Struk dalam rentang, terbaru lebih dulu")
