"""Pembacaan struk dengan Claude vision (klien palsu: tanpa jaringan, tanpa biaya)."""
import json
from types import SimpleNamespace

from PIL import Image

from app.integrations.parser.regex_parser import RegexReceiptParser
from app.integrations.vision.claude_extractor import SCHEMA, ClaudeReceiptExtractor
from app.services.receipt_reader import read_receipt
from tests.conftest import FakeOCR

DIGPART = {
    "merchant_name": "DigPart Malang - Pusat",
    "merchant_address": "Jl. Joyosuko Metro Gg. 2B No 60",
    "transaction_date": "2026-10-19",
    "transaction_time": None,
    "items": [
        {"name": "PIN HEADER FEMALE STRIP SINGLE ROW 1X40 2.54MM BLACK HITAM", "quantity": 1,
         "unit_price": 3000, "line_total": 3000},
        {"name": "Timah Solder Paragon 10 Meter", "quantity": 1, "unit_price": 30000, "line_total": 30000},
        {"name": "Kabel Listrik Elektronika Serabut Kecil Ukuran 1x10 Warna-warni", "quantity": 5,
         "unit_price": 1000, "line_total": 5000},
    ],
    "subtotal": 38000, "discount": None, "tax_and_charges": None, "total": 38000,
    "payment_method": "Tunai", "amount_paid": 50000, "change": 12000,
    "unreadable_fields": ["transaction_time"],
    "transcription": "DigPart Malang - Pusat\nJl. Joyosuko Metro Gg. 2B No 60\n...",
}


class FakeMessages:
    def __init__(self, payload=None, stop_reason="end_turn", error=None):
        self.payload, self.stop_reason, self.error, self.calls = payload, stop_reason, error, []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        text = json.dumps(self.payload)
        return SimpleNamespace(stop_reason=self.stop_reason, content=[SimpleNamespace(type="text", text=text)])


def _extractor(messages):
    ex = ClaudeReceiptExtractor(model="claude-opus-5-5", api_key="test-key")
    ex._client = SimpleNamespace(beta=SimpleNamespace(messages=messages))
    return ex


def _image():
    return Image.new("RGB", (600, 900), "white")


def test_claude_reads_receipt_into_structured_data():
    messages = FakeMessages(DIGPART)
    reading = read_receipt(_image(), FakeOCR(), RegexReceiptParser(), vision=_extractor(messages))
    p = reading.parsed
    assert reading.label == "Claude (vision)"
    assert p.merchant_name == "DigPart Malang - Pusat"
    assert p.transaction_date.strftime("%Y-%m-%d") == "2026-10-19"
    assert p.total_amount == 38000 and p.subtotal_amount == 38000
    assert [(i.quantity, i.unit_price, i.price) for i in p.items] == [(1, 3000, 3000), (1, 30000, 30000), (5, 1000, 5000)]
    assert reading.consistent is True
    # Jam tidak terbaca (dilaporkan Claude) -> tanggal wajib dicek.
    assert "date" in reading.review_fields

    req = messages.calls[0]
    assert req["model"] == "claude-opus-5-5"
    assert req["output_config"]["format"] == {"type": "json_schema", "schema": SCHEMA}
    assert req["messages"][0]["content"][0]["type"] == "image"


def test_refusal_or_error_falls_back_to_local_ocr():
    for messages in (FakeMessages(DIGPART, stop_reason="refusal"), FakeMessages(error=RuntimeError("putus"))):
        reading = read_receipt(_image(), FakeOCR(), RegexReceiptParser(), vision=_extractor(messages))
        assert reading.label != "Claude (vision)"
        assert reading.parsed.merchant_name == "INDOMARET"  # dari teks OCR palsu (Tesseract)


def test_invalid_output_falls_back():
    messages = FakeMessages({"merchant_name": "X"})  # tidak sesuai skema
    reading = read_receipt(_image(), FakeOCR(), RegexReceiptParser(), vision=_extractor(messages))
    assert reading.label != "Claude (vision)"


def test_without_api_key_vision_is_off(monkeypatch):
    from app.integrations import providers

    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("ANTHROPIC_AUTH_TOKEN", raising=False)
    monkeypatch.setattr(providers.settings, "ANTHROPIC_API_KEY", "")
    providers.get_vision_extractor.cache_clear()
    assert providers.get_vision_extractor() is None
    providers.get_vision_extractor.cache_clear()
