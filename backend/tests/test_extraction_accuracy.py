"""Penjaga regresi akurasi ekstraksi struk.

Menjalankan sebagian benchmark (scripts/receipt_benchmark.py) lewat OCR Tesseract
sungguhan dan GAGAL bila akurasi turun di bawah batas minimum. Butuh waktu beberapa
menit, jadi hanya dijalankan bila RUN_SLOW=1 (otomatis di CI GitHub Actions):

    RUN_SLOW=1 pytest -q tests/test_extraction_accuracy.py -s
"""
import os

import pytest

from app.core.config import settings
from app.integrations.providers import get_ocr_engine
from scripts.receipt_benchmark import build_cases, run_case, summarize

# Batas minimum (diukur 22-11-2026, lalu diberi sedikit ruang).
MIN_TOTAL = 0.93
MIN_ITEM_F1 = 0.93
MAX_SILENT_ERRORS = 0.05

CONDITIONS = ["clean", "photo", "blur_strong", "dark", "rotate", "motion_mild"]

pytestmark = [
    pytest.mark.skipif(os.environ.get("RUN_SLOW") != "1", reason="uji lambat; set RUN_SLOW=1"),
    pytest.mark.skipif(
        not get_ocr_engine().status().get("ready"),
        reason="Tesseract tidak terpasang",
    ),
]


def test_extraction_accuracy_does_not_regress():
    cases = [c for c in build_cases(CONDITIONS, per_format=1)
             if c["group"] == "real" or c["condition"] in ("clean", "photo", "blur_strong")]
    rows = [run_case(c) for c in cases]
    name, n, merchant, date, total, recall, precision, f1, silent, seconds = summarize(
        [{**r, "all": "semua"} for r in rows], "all")[0]
    print(f"\n{n} gambar: total {total:.1%}, barang F1 {f1:.1%}, salah-diam {silent:.1%}, "
          f"toko {merchant:.1%}, tanggal {date:.1%}, {seconds:.1f} detik/struk")
    failures = [r["id"] for r in rows if r["silent"]]
    assert total >= MIN_TOTAL, f"akurasi total turun ke {total:.1%}"
    assert f1 >= MIN_ITEM_F1, f"akurasi barang turun ke {f1:.1%}"
    assert silent <= MAX_SILENT_ERRORS, f"kesalahan tanpa tanda {silent:.1%}: {failures[:10]}"
