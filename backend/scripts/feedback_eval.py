"""Ukur parser pada struk NYATA yang sudah dikoreksi pengguna (tabel scan_feedback).

Setiap struk yang dipindai lalu disimpan pengguna menjadi kasus uji: teks OCR-nya di-parse
ulang dengan parser terbaru, lalu dibandingkan dengan data akhir yang sudah dikoreksi.
Makin sering aplikasi dipakai, makin banyak data uji nyata.

Pemakaian (dari folder backend):
    python -m scripts.feedback_eval                   # ringkasan akurasi
    python -m scripts.feedback_eval --show-errors     # rincian struk yang salah
    python -m scripts.feedback_eval --export tests/data/receipts/feedback.json
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from sqlalchemy import select

from app.db.session import SessionLocal
from app.integrations.parser.regex_parser import RegexReceiptParser
from app.models import ScanFeedback
from scripts.receipt_benchmark import norm, similar


def evaluate(rows: list[ScanFeedback], show_errors: bool = False) -> dict:
    parser = RegexReceiptParser()
    n = total_ok = item_ok = item_gt = 0
    for row in rows:
        final = json.loads(row.final_json)
        if not row.raw_text.strip() or not final.get("items"):
            continue
        n += 1
        parsed = parser.parse(row.raw_text)
        errors = []
        if parsed.total_amount is not None and final.get("total") is not None and abs(parsed.total_amount - final["total"]) < 1:
            total_ok += 1
        else:
            errors.append(f"total {parsed.total_amount} != {final.get('total')}")
        used: set[int] = set()
        for f in final["items"]:
            item_gt += 1
            match = next(
                (i for i, p in enumerate(parsed.items)
                 if i not in used and p.price is not None and f.get("price") is not None
                 and abs(p.price - f["price"]) < 1 and similar(p.name, f["name"]) >= 0.6),
                None,
            )
            if match is None:
                errors.append(f"barang '{f['name']}' {f.get('price')}")
            else:
                used.add(match)
                item_ok += 1
        if show_errors and errors:
            print(f"--- feedback #{row.id} (diubah pengguna: {row.changed_fields or '-'})")
            for e in errors[:8]:
                print("   ", e)
    return {"struk": n, "total_benar": total_ok / n if n else 0.0, "barang_benar": item_ok / item_gt if item_gt else 0.0}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--show-errors", action="store_true")
    ap.add_argument("--export", type=Path, help="simpan sebagai berkas uji (teks OCR + jawaban)")
    args = ap.parse_args()
    with SessionLocal() as db:
        rows = db.scalars(select(ScanFeedback).order_by(ScanFeedback.id)).all()
        result = evaluate(rows, args.show_errors)
        if args.export:
            data = [{"raw_text": r.raw_text, "final": json.loads(r.final_json)} for r in rows if r.raw_text.strip()]
            args.export.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
            print(f"{len(data)} kasus diekspor ke {args.export}")
    print(f"Struk nyata terkoreksi : {result['struk']}")
    print(f"Total benar            : {result['total_benar']:.1%}")
    print(f"Barang benar           : {result['barang_benar']:.1%}")


if __name__ == "__main__":
    main()
