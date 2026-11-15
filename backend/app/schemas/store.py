from pydantic import BaseModel

from app.schemas.common import LocalDateTime


class StoreOut(BaseModel):
    merchant_name: str
    merchant_address: str | None
    visits: int
    total_spent: float
    last_visit: LocalDateTime | None
