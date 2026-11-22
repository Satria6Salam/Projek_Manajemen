"""Keyakinan per kolom, teks ML Kit dari HP, dan belajar dari koreksi pengguna."""
from sqlalchemy import func, select

from app.db.session import SessionLocal
from app.models import ScanFeedback
from tests.conftest import SAMPLE_TEXT, FakeOCR


def _scan(client, auth, image_bytes, device_text=None):
    data = {"device_text": device_text} if device_text else None
    r = client.post("/api/v1/scans", files={"file": ("struk.jpg", image_bytes, "image/jpeg")},
                    data=data, headers=auth)
    assert r.status_code == 200, r.text
    return r.json()


def _save(client, auth, scan, merchant=None, rename=None):
    rename = rename or {}
    payload = {
        "scan_id": scan["scan_id"],
        "merchant_name": merchant or scan["merchant_name"],
        "transaction_date": scan["transaction_date"],
        "total_amount": scan["total_amount"],
        "allow_duplicate": True,
        "items": [
            {
                "item_name": rename.get(i["item_name"], i["item_name"]),
                "quantity": i["quantity"],
                "item_price": i["item_price"],
                "category_id": i["category_id"],
                "predicted_category_id": i["predicted_category_id"],
            }
            for i in scan["items"]
        ],
    }
    r = client.post("/api/v1/receipts", json=payload, headers=auth)
    assert r.status_code == 201, r.text


def test_scan_reports_confidence_and_flags(client, auth, image_bytes):
    scan = _scan(client, auth, image_bytes)
    assert scan["consistent"] is True
    assert scan["field_confidence"]["total"] == "tinggi"
    assert scan["field_confidence"]["items"] == "tinggi"
    assert "total" not in scan["review_fields"]
    assert all(i["price_corrected"] is False for i in scan["items"])


def test_device_text_from_phone_is_used_when_better(client, auth, image_bytes, monkeypatch):
    # Tesseract "gagal" membaca kolom harga; teks ML Kit dari HP lengkap.
    monkeypatch.setattr(FakeOCR, "text", "INDOMARET\nROTI TAWAR 500G\nSUSU UHT 1L\nTOTAL\n")
    scan = _scan(client, auth, image_bytes, device_text=SAMPLE_TEXT)
    assert scan["ocr_source"] == "ML Kit (HP)"
    assert scan["total_amount"] == 60500 and len(scan["items"]) == 4
    assert scan["consistent"] is True


def test_inconsistent_scan_is_flagged_for_review(client, auth, image_bytes, monkeypatch):
    monkeypatch.setattr(FakeOCR, "text", "TOKO X\nGULA 1KG 16.000\nTOTAL 90.000\n")
    scan = _scan(client, auth, image_bytes)
    assert scan["consistent"] is False
    assert scan["field_confidence"]["total"] == "rendah"
    assert {"total", "items"} <= set(scan["review_fields"])


def test_user_corrections_are_learned_per_user(client, auth, other_auth, image_bytes):
    with SessionLocal() as db:
        before = db.scalar(select(func.count(ScanFeedback.id)))
    scan = _scan(client, auth, image_bytes)
    _save(client, auth, scan, merchant="Indomaret Gajayana", rename={"BARANG ANEH XYZ": "Sabun Cair Lifebuoy"})
    with SessionLocal() as db:
        assert db.scalar(select(func.count(ScanFeedback.id))) == before + 1

    again = _scan(client, auth, image_bytes)
    assert again["merchant_name"] == "Indomaret Gajayana"
    renamed = [i for i in again["items"] if i["item_name"] == "Sabun Cair Lifebuoy"]
    assert renamed and renamed[0]["name_corrected"] is True
    assert any("koreksi Anda" in w for w in again["warnings"])

    # Pengguna lain tidak terpengaruh.
    other = _scan(client, other_auth, image_bytes)
    assert other["merchant_name"] == "INDOMARET"
    assert "BARANG ANEH XYZ" in [i["item_name"] for i in other["items"]]
