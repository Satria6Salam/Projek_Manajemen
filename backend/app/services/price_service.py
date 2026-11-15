"""Riwayat harga satu barang di berbagai toko (dari barang struk pengguna)."""
from collections import defaultdict

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Receipt, ReceiptItem, User
from app.schemas.price import MerchantPriceOut, PriceHistoryOut, PricePointOut

MAX_POINTS = 200


def price_history(db: Session, user: User, query: str) -> PriceHistoryOut:
    words = [w for w in query.lower().split() if w]
    stmt = (
        select(ReceiptItem, Receipt.merchant_name, Receipt.transaction_date)
        .join(Receipt, Receipt.id == ReceiptItem.receipt_id)
        .where(Receipt.user_id == user.id, ReceiptItem.item_price.is_not(None), ReceiptItem.item_price > 0)
    )
    for w in words:  # semua kata harus ada: "indomie goreng" cocok dengan "INDOMIE GORENG SPESIAL"
        stmt = stmt.where(func.lower(ReceiptItem.item_name).contains(w))
    rows = db.execute(stmt.order_by(Receipt.transaction_date.desc(), ReceiptItem.id.desc()).limit(MAX_POINTS)).all()

    points = [
        PricePointOut(
            item_name=item.item_name,
            merchant_name=merchant,
            transaction_date=when,
            quantity=item.quantity or 1,
            unit_price=round(float(item.item_price) / max(item.quantity or 1, 1), 2),
            receipt_id=item.receipt_id,
        )
        for item, merchant, when in rows
    ]
    by_store: dict[str, list[float]] = defaultdict(list)  # terbaru lebih dulu
    names: dict[str, str] = {}
    for p in points:
        key = " ".join((p.merchant_name or "Tanpa nama toko").upper().split())
        names.setdefault(key, p.merchant_name or "Tanpa nama toko")
        by_store[key].append(p.unit_price)
    merchants = sorted(
        (
            MerchantPriceOut(
                merchant_name=names[k],
                purchases=len(v),
                lowest=min(v),
                average=round(sum(v) / len(v), 2),
                latest=v[0],
            )
            for k, v in by_store.items()
        ),
        key=lambda m: m.latest,
    )
    prices = [p.unit_price for p in points]
    return PriceHistoryOut(
        query=query,
        points=points,
        merchants=merchants,
        cheapest_merchant=merchants[0].merchant_name if len(merchants) >= 2 else None,
        lowest=min(prices) if prices else None,
        highest=max(prices) if prices else None,
    )
