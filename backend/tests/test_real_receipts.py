"""Uji ujung-ke-ujung: foto struk nyata -> OCR Tesseract -> parser.

Kunci jawaban: tests/data/receipts/real/ground_truth.json. Dilewati bila Tesseract
tidak terpasang di mesin uji.
"""
import json
from pathlib import Path

import pytest
from PIL import Image

from app.core.config import settings
from app.integrations.providers import get_ocr_engine
from app.integrations.parser.regex_parser import RegexReceiptParser
from app.services.receipt_reader import read_receipt
from scripts.receipt_benchmark import norm

REAL = Path(__file__).parent / "data" / "receipts" / "real"
TRUTH = json.loads((REAL / "ground_truth.json").read_text(encoding="utf-8"))
OCR = get_ocr_engine()  # OCR_ENGINE=auto: RapidOCR + cadangan Tesseract

pytestmark = pytest.mark.skipif(not OCR.status().get("ready"), reason="Tesseract tidak terpasang")


@pytest.mark.parametrize("filename", sorted(TRUTH))
def test_real_receipt_is_read_correctly(filename):
    gt = TRUTH[filename]
    parsed = read_receipt(Image.open(REAL / filename).convert("RGB"), OCR, RegexReceiptParser()).parsed

    assert norm(gt["merchant"]) in norm(parsed.merchant_name or "")
    assert parsed.transaction_date.strftime("%Y-%m-%d") == gt["date"]
    assert parsed.total_amount == gt["total"]
    if gt.get("check_names", True):
        got = [(norm(i.name), i.quantity, i.price) for i in parsed.items]
        want = [(norm(i["name"]), i["qty"], i["price"]) for i in gt["items"]]
    else:  # foto HP asli: nama barang boleh salah ketik OCR, angka harus tepat
        got = [(i.quantity, i.price) for i in parsed.items]
        want = [(i["qty"], i["price"]) for i in gt["items"]]
    assert got == want
