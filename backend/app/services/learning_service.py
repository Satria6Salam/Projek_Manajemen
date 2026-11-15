"""Model belajar dari koreksi pengguna.

Setiap kali pengguna mengoreksi kategori barang, nama barang + kategori yang
benar menjadi data latih tambahan `id_model`. Pelatihan ulang dijalankan di
latar belakang (tidak memperlambat request) dan digabung bila ada banyak
koreksi beruntun.
"""
import logging
import threading

from sqlalchemy import select

from app.db.session import SessionLocal
from app.models import Category, ReceiptItem

logger = logging.getLogger("strukku")

MAX_CORRECTIONS = 20000

_lock = threading.Lock()
_running = False
_pending = False


def load_corrections() -> list[tuple[str, str]]:
    """Semua koreksi pengguna: (nama barang, key kategori). Terbaru menang per nama."""
    with SessionLocal() as db:
        rows = db.execute(
            select(ReceiptItem.item_name, Category.name)
            .join(Category, Category.id == ReceiptItem.category_id)
            .where(ReceiptItem.is_user_corrected.is_(True))
            .order_by(ReceiptItem.id.desc())
            .limit(MAX_CORRECTIONS)
        ).all()
    latest: dict[str, tuple[str, str]] = {}
    for name, category in rows:
        key = " ".join((name or "").lower().split())
        if key and key not in latest:
            latest[key] = (name, category)
    return list(latest.values())


def _worker() -> None:
    global _running, _pending
    from app.integrations.providers import get_id_model

    while True:
        try:
            get_id_model().retrain()
            logger.info("id_model dilatih ulang dengan %s koreksi pengguna.", get_id_model().learned_count)
        except Exception:
            logger.exception("Pelatihan ulang id_model gagal")
        with _lock:
            if not _pending:
                _running = False
                return
            _pending = False


def schedule_retrain() -> None:
    """Minta pelatihan ulang di latar belakang (digabung bila sedang berjalan)."""
    global _running, _pending
    with _lock:
        if _running:
            _pending = True
            return
        _running = True
    threading.Thread(target=_worker, name="id-model-retrain", daemon=True).start()


def retrain_now() -> None:
    """Latih ulang secara langsung (dipakai tes & endpoint admin)."""
    from app.integrations.providers import get_id_model

    get_id_model().retrain()
