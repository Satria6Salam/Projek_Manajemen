from pydantic import BaseModel, Field

from app.schemas.common import LocalDateTime


class PricePointOut(BaseModel):
    item_name: str
    merchant_name: str | None
    transaction_date: LocalDateTime | None
    quantity: int
    unit_price: float = Field(description="Harga per satuan (harga baris / qty)")
    receipt_id: int


class MerchantPriceOut(BaseModel):
    merchant_name: str
    purchases: int
    lowest: float
    average: float
    latest: float


class PriceHistoryOut(BaseModel):
    query: str
    points: list[PricePointOut] = Field(description="Terbaru lebih dulu")
    merchants: list[MerchantPriceOut] = Field(description="Termurah lebih dulu (harga terakhir)")
    cheapest_merchant: str | None
    lowest: float | None
    highest: float | None
