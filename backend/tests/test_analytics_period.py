"""Pengujian endpoint analitik periode & tren tahunan."""


def _categories(client):
    return {c["key"]: c for c in client.get("/api/v1/categories").json()}


def _save(client, auth, when: str, items: list[tuple[str, float, int]], merchant="TOKO A"):
    r = client.post(
        "/api/v1/receipts",
        json={
            "merchant_name": merchant,
            "transaction_date": when,
            "items": [
                {"item_name": name, "item_price": price, "category_id": cat, "quantity": 2}
                for name, price, cat in items
            ],
        },
        headers=auth,
    )
    assert r.status_code == 201, r.text
    return r.json()


def test_period_summary_day_month_and_yearly(client, auth):
    cats = _categories(client)
    makanan, minuman = cats["Makanan"]["id"], cats["Minuman"]["id"]
    _save(client, auth, "2025-12-31T10:00:00", [("ROTI", 10000, makanan)])
    _save(client, auth, "2026-01-05T09:00:00", [("ROTI", 20000, makanan), ("TEH", 5000, minuman)])
    _save(client, auth, "2026-01-05T19:00:00", [("KOPI", 15000, minuman)], merchant="KAFE B")
    _save(client, auth, "2026-01-20T12:00:00", [("SUSU", 8000, minuman)])

    # Satu hari: dua struk tanggal 5 Januari.
    day = client.get(
        "/api/v1/analytics/period", params={"date_from": "2026-01-05", "date_to": "2026-01-05"}, headers=auth
    ).json()
    assert day["receipt_count"] == 2
    assert day["total_spent"] == 40000
    assert {c["category"]["key"]: c["amount"] for c in day["categories"]} == {"Makanan": 20000, "Minuman": 20000}
    assert [r["merchant_name"] for r in day["receipts"]] == ["KAFE B", "TOKO A"]  # terbaru dulu

    # Satu bulan.
    month = client.get(
        "/api/v1/analytics/period", params={"date_from": "2026-01-01", "date_to": "2026-01-31"}, headers=auth
    ).json()
    assert month["receipt_count"] == 3 and month["total_spent"] == 48000

    # Tren tahunan.
    years = {p["year"]: p for p in client.get("/api/v1/analytics/yearly", headers=auth).json()}
    assert years[2025]["total_spent"] == 10000 and years[2026]["receipt_count"] == 3


def test_period_rejects_invalid_ranges(client, auth):
    bad = client.get(
        "/api/v1/analytics/period", params={"date_from": "2026-02-01", "date_to": "2026-01-01"}, headers=auth
    )
    assert bad.status_code == 400
    too_long = client.get(
        "/api/v1/analytics/period", params={"date_from": "2024-01-01", "date_to": "2026-01-01"}, headers=auth
    )
    assert too_long.status_code == 400


def test_period_requires_login(client):
    r = client.get("/api/v1/analytics/period", params={"date_from": "2026-01-01", "date_to": "2026-01-02"})
    assert r.status_code == 401


def test_model_report_counts_corrections(client, auth):
    cats = _categories(client)
    mk, mn = cats["Makanan"]["id"], cats["Minuman"]["id"]
    r = client.post(
        "/api/v1/receipts",
        json={
            "merchant_name": "TOKO C",
            "items": [
                {"item_name": "ROTI", "item_price": 1000, "category_id": mk, "predicted_category_id": mk,
                 "prediction_source": "keyword_rules"},
                {"item_name": "TEH X", "item_price": 1000, "category_id": mn, "predicted_category_id": mk,
                 "prediction_source": "id_model"},
                {"item_name": "MANUAL", "item_price": 1000, "category_id": mk},  # tanpa prediksi
            ],
        },
        headers=auth,
    )
    assert r.status_code == 201, r.text
    rep = client.get("/api/v1/analytics/model", headers=auth).json()
    assert rep["total_items"] == 2 and rep["corrected_items"] == 1 and rep["accuracy"] == 50.0
    assert rep["top_corrections"][0] == {
        "item_name": "TEH X", "predicted": "Makanan", "corrected_to": "Minuman", "count": 1
    }
    sources = {s["source"]: s["accuracy"] for s in rep["sources"]}
    assert sources == {"keyword_rules": 100.0, "id_model": 0.0}
    assert len(rep["monthly"]) == 6


def test_duplicate_receipt_is_detected(client, auth):
    cats = _categories(client)
    body = {
        "merchant_name": "Indomaret Dago",
        "transaction_date": "2026-03-03T10:00:00",
        "items": [{"item_name": "ROTI", "item_price": 12500, "category_id": cats["Makanan"]["id"]}],
    }
    assert client.post("/api/v1/receipts", json=body, headers=auth).status_code == 201
    # Struk sama (beda jam & huruf besar/kecil nama toko) -> ditolak sebagai kemungkinan ganda.
    again = dict(body, merchant_name="INDOMARET DAGO", transaction_date="2026-03-03T18:00:00")
    r = client.post("/api/v1/receipts", json=again, headers=auth)
    assert r.status_code == 409 and r.json()["code"] == "POSSIBLE_DUPLICATE"
    # Pengguna memilih tetap simpan.
    assert client.post("/api/v1/receipts", json=dict(again, allow_duplicate=True), headers=auth).status_code == 201
    # Toko berbeda / total berbeda -> bukan duplikat.
    other = dict(body, merchant_name="Alfamart")
    assert client.post("/api/v1/receipts", json=other, headers=auth).status_code == 201


def test_price_history_compares_stores(client, auth):
    cats = _categories(client)
    mk = cats["Makanan"]["id"]
    for merchant, when, price, qty in [
        ("Indomaret", "2026-01-02T10:00:00", 7000, 2),   # 3.500 / bungkus
        ("Alfamart", "2026-01-09T10:00:00", 3200, 1),
        ("Indomaret", "2026-02-02T10:00:00", 3600, 1),
    ]:
        r = client.post("/api/v1/receipts", json={
            "merchant_name": merchant, "transaction_date": when,
            "items": [{"item_name": "INDOMIE GORENG SPESIAL", "item_price": price, "quantity": qty, "category_id": mk},
                      {"item_name": "TEH BOTOL", "item_price": 5000, "category_id": mk}],
        }, headers=auth)
        assert r.status_code == 201, r.text
    h = client.get("/api/v1/items/price-history", params={"q": "indomie goreng"}, headers=auth).json()
    assert [p["unit_price"] for p in h["points"]] == [3600, 3200, 3500]  # terbaru dulu
    assert h["cheapest_merchant"] == "Alfamart"
    indo = next(m for m in h["merchants"] if m["merchant_name"] == "Indomaret")
    assert indo == {"merchant_name": "Indomaret", "purchases": 2, "lowest": 3500, "average": 3550, "latest": 3600}
    assert h["lowest"] == 3200 and h["highest"] == 3600


def test_store_address_saved_and_listed(client, auth):
    cats = _categories(client)
    mk = cats["Makanan"]["id"]
    for when, address, total in [
        ("2026-04-01T10:00:00", "Jl. Dago No. 1, Bandung", 10000),
        ("2026-04-02T10:00:00", "Jl. Dago No. 1, Bandung", 20000),
        ("2026-04-03T10:00:00", "Jl. Merdeka No. 5, Bandung", 5000),
    ]:
        r = client.post("/api/v1/receipts", json={
            "merchant_name": "Indomaret", "merchant_address": address, "transaction_date": when,
            "items": [{"item_name": "ROTI", "item_price": total, "category_id": mk}],
        }, headers=auth)
        assert r.status_code == 201, r.text
        assert r.json()["merchant_address"] == address
    stores = client.get("/api/v1/stores", headers=auth).json()
    assert [(s["merchant_address"], s["visits"], s["total_spent"]) for s in stores] == [
        ("Jl. Dago No. 1, Bandung", 2, 30000),
        ("Jl. Merdeka No. 5, Bandung", 1, 5000),
    ]
