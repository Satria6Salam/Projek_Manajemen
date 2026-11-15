"""Daftar toko tempat pengguna berbelanja, beserta alamat dari struk."""
from collections import defaultdict
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Receipt, User
from app.schemas.store import StoreOut


def _key(name: str | None) -> str:
    return "".join(ch for ch in (name or "").lower() if ch.isalnum())


def list_stores(db: Session, user: User) -> list[StoreOut]:
    rows = db.execute(
        select(Receipt.merchant_name, Receipt.merchant_address, Receipt.total_amount, Receipt.transaction_date)
        .where(Receipt.user_id == user.id)
        .order_by(Receipt.transaction_date.desc())
    ).all()
    groups: dict[str, dict] = defaultdict(lambda: {"visits": 0, "total": 0.0, "addresses": {}})
    for name, address, total, when in rows:
        if not name:
            continue
        # Toko + alamat berbeda = cabang berbeda; tanpa alamat digabung per nama.
        key = f"{_key(name)}|{_key(address)}"
        g = groups[key]
        g.setdefault("name", name)
        g.setdefault("address", address)
        g.setdefault("last", when)
        g["visits"] += 1
        g["total"] += float(total or 0)
    stores = [
        StoreOut(
            merchant_name=g["name"],
            merchant_address=g["address"],
            visits=g["visits"],
            total_spent=round(g["total"], 2),
            last_visit=g["last"],
        )
        for g in groups.values()
    ]
    stores.sort(key=lambda s: (-s.visits, -(s.last_visit or datetime.min).timestamp()))
    return stores
