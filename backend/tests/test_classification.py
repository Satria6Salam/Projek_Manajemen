"""Pengujian perbaikan teks OCR dan akurasi rangkaian classifier."""
from pathlib import Path

import pytest

from app.integrations.classifier.ocr_repair import OcrTextRepairer
from app.integrations.providers import get_normalizer
from scripts.evaluate_classifier import evaluate, load_rows

DATA = Path(__file__).parent / "data"
PIPELINE = ["keyword_rules", "id_model", "ml_model"]


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("FRESHMI LK 1L", "fresh milk"),
        ("MIE SEDAAP5OTO", "mie sedaap soto"),
        ("TE1UR AYAM 1KG", "telur ayam"),
        ("PEPSODNT PST GG", "pepsodent pasta gigi"),
        ("CL0SE UP 160G", "close up"),
        ("5ABUN LIFEBUOY", "sabun lifebuoy"),
    ],
)
def test_ocr_repair_fixes_common_misreads(raw, expected):
    assert get_normalizer().normalize(raw) == expected


def test_repairer_keeps_known_words_and_drops_sizes():
    repairer = OcrTextRepairer({"susu": 5, "coklat": 3})
    assert repairer.repair("susu coklat 250ml 2x") == "susu coklat"


def test_repairer_does_not_touch_short_unknown_tokens():
    repairer = OcrTextRepairer({"sabun": 1})
    assert repairer.repair("abc sabun") == "abc sabun"


@pytest.mark.parametrize(
    ("csv_name", "minimum"),
    [
        ("classification_eval.csv", 0.97),       # nama barang bersih
        ("classification_eval_ocr.csv", 0.90),   # nama barang dengan gangguan OCR
        ("classification_eval_unseen.csv", 0.90),  # barang di luar kata kunci awal
    ],
)
def test_classifier_accuracy(csv_name, minimum):
    result = evaluate(PIPELINE, load_rows(DATA / csv_name))
    assert result["accuracy"] >= minimum, result["errors"]


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("ula Pasir 1kg", "gula pasir"), ("inyak Goreng", "minyak goreng"), ("ie Instan", "mie instan"),
     ("abun Mandi", "sabun mandi")],
)
def test_restores_missing_first_letter_from_word_pairs(raw, expected):
    assert get_normalizer().normalize(raw) == expected


def test_truncated_letters_accuracy():
    result = evaluate(PIPELINE, load_rows(DATA / "classification_eval_truncated.csv"))
    assert result["accuracy"] >= 0.95, result["errors"]
