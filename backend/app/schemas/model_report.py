from datetime import datetime

from pydantic import BaseModel, Field


class CategoryAccuracyOut(BaseModel):
    category: str = Field(description="Kategori hasil prediksi (nama tampilan)")
    items: int
    corrected: int
    accuracy: float | None = Field(description="0-100; null bila belum ada data")


class SourceAccuracyOut(BaseModel):
    source: str
    label: str
    items: int
    accuracy: float | None


class CorrectionOut(BaseModel):
    item_name: str
    predicted: str
    corrected_to: str
    count: int


class MonthlyAccuracyOut(BaseModel):
    month: str
    month_label: str
    items: int
    accuracy: float | None


class ModelReportOut(BaseModel):
    total_items: int = Field(description="Barang yang punya prediksi sistem")
    corrected_items: int
    accuracy: float | None = Field(description="Persen prediksi yang tidak dikoreksi pengguna")
    categories: list[CategoryAccuracyOut]
    sources: list[SourceAccuracyOut]
    top_corrections: list[CorrectionOut]
    monthly: list[MonthlyAccuracyOut]
    learned_corrections: int = Field(description="Koreksi (semua pengguna) yang sudah dipelajari id_model")
    training_samples: int
    trained_at: datetime | None
