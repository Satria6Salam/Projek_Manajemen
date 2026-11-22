"""Belajar dari koreksi pengguna pada hasil pindai.

Saat pindai: hasil parser disimpan sebagai snapshot di ScanAsset, lalu koreksi yang
pernah dibuat pengguna (nama toko, nama barang per toko) diterapkan otomatis.

Saat struk hasil pindai disimpan: snapshot dibandingkan dengan data akhir yang sudah
dikoreksi pengguna. Perbedaan nama toko / nama barang dicatat ke kamus koreksi, dan
seluruh struk disimpan sebagai data uji nyata (ScanFeedback).
"""
from __future__ import annotations

import json
import logging
import re
from difflib import SequenceMatcher

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.integrations.parser.base import ParsedReceipt
from app.models import OcrCorrection, ScanFeedback

logger = logging.getLogger("strukku")

MIN_ITEM_SIMILARITY = 0.6  # nama hasil OCR & nama koreksi harus cukup mirip agar dicatat


def norm_key(text: str | None) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", (text or "").lower())).strip()[:255]


def snapshot(parsed: ParsedReceipt, raw_text: str = "") -> str:
    return json.dumps({
        "raw_text": raw_text,
        "merchant": parsed.merchant_name,
        "date": parsed.transaction_date.isoformat() if parsed.transaction_date else None,
        "total": parsed.total_amount,
        "items": [{"name": i.name, "qty": i.quantity, "price": i.price} for i in parsed.items],
    }, ensure_ascii=False)


# ------------------------------------------------------------------ terapkan
def apply_corrections(db: Session, user_id: int, parsed: ParsedReceipt) -> int:
    """Terapkan koreksi yang pernah dibuat pengguna. Mengembalikan jumlah perubahan."""
    rows = db.scalars(select(OcrCorrection).where(OcrCorrection.user_id == user_id)).all()
    if not rows:
        return 0
    merchants = {r.ocr_key: r.corrected for r in rows if r.kind == "merchant"}
    items: dict[tuple[str, str], str] = {(r.scope, r.ocr_key): r.corrected for r in rows if r.kind == "item"}
    changed = 0
    key = norm_key(parsed.merchant_name)
    if key and key in merchants:
        parsed.merchant_name = merchants[key]
        changed += 1
    scope = norm_key(parsed.merchant_name)
    for item in parsed.items:
        k = norm_key(item.name)
        fixed = items.get((scope, k)) or items.get(("", k))
        if fixed and fixed != item.name:
            item.name = fixed
            item.name_corrected = True
            changed += 1
    return changed


# ------------------------------------------------------------------ pelajari
def _upsert(db: Session, user_id: int, kind: str, scope: str, ocr_text: str, corrected: str) -> None:
    key = norm_key(ocr_text)
    if not key or norm_key(corrected) == key:
        return
    row = db.scalar(select(OcrCorrection).where(
        OcrCorrection.user_id == user_id, OcrCorrection.kind == kind,
        OcrCorrection.scope == scope, OcrCorrection.ocr_key == key,
    ))
    if row is None:
        db.add(OcrCorrection(user_id=user_id, kind=kind, scope=scope, ocr_key=key, corrected=corrected[:255]))
    else:
        row.corrected = corrected[:255]
        row.hits += 1


def _match_items(scanned: list[dict], final: list[dict]) -> list[tuple[dict, dict]]:
    """Pasangkan barang hasil scan dengan barang akhir: harga sama dulu, lalu nama mirip."""
    pairs: list[tuple[dict, dict]] = []
    used: set[int] = set()
    for s in scanned:
        best, best_score = None, 0.0
        for j, f in enumerate(final):
            if j in used:
                continue
            sim = SequenceMatcher(None, norm_key(s["name"]), norm_key(f["name"])).ratio()
            same_price = s.get("price") is not None and f.get("price") is not None and abs(s["price"] - f["price"]) < 1
            score = sim + (0.5 if same_price else 0)
            if score > best_score:
                best, best_score = j, score
        if best is not None and best_score >= MIN_ITEM_SIMILARITY:
            used.add(best)
            pairs.append((s, final[best]))
    return pairs


def learn_from_save(db: Session, user_id: int, receipt_id: int | None, snapshot_json: str | None,
                    raw_text: str | None, final: dict) -> list[str]:
    """Bandingkan snapshot pindai dengan data akhir. Mengembalikan kolom yang berubah."""
    if not snapshot_json:
        return []
    try:
        scanned = json.loads(snapshot_json)
    except json.JSONDecodeError:
        return []
    changed: list[str] = []

    if scanned.get("merchant") and final.get("merchant") and norm_key(scanned["merchant"]) != norm_key(final["merchant"]):
        _upsert(db, user_id, "merchant", "", scanned["merchant"], final["merchant"])
        changed.append("merchant")
    if scanned.get("total") != final.get("total"):
        changed.append("total")
    if (scanned.get("date") or "")[:10] != (final.get("date") or "")[:10]:
        changed.append("date")

    scope = norm_key(final.get("merchant"))
    names_changed = prices_changed = False
    for s, f in _match_items(scanned.get("items", []), final.get("items", [])):
        if norm_key(s["name"]) != norm_key(f["name"]):
            _upsert(db, user_id, "item", scope, s["name"], f["name"])
            names_changed = True
        if s.get("price") != f.get("price") or s.get("qty") != f.get("qty"):
            prices_changed = True
    if names_changed:
        changed.append("item_names")
    if prices_changed or len(scanned.get("items", [])) != len(final.get("items", [])):
        changed.append("items")

    db.add(ScanFeedback(
        user_id=user_id, receipt_id=receipt_id, raw_text=raw_text or scanned.get("raw_text") or "",
        parsed_json=snapshot_json, final_json=json.dumps(final, ensure_ascii=False),
        changed_fields=",".join(changed),
    ))
    return changed
