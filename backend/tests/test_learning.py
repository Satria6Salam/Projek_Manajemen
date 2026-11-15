"""Model id_model belajar dari koreksi pengguna."""
from app.integrations.classifier.base import ClassificationContext
from app.integrations.providers import get_id_model
from app.services import learning_service


def test_corrections_teach_similar_item_names(client, auth):
    cats = {c["key"]: c for c in client.get("/api/v1/categories").json()}
    model = get_id_model()
    probe = "ZORBAQU ORIGINAL 250ML"  # merek yang sama, varian berbeda
    learning_service.retrain_now()
    before = model.predict_many([probe], ClassificationContext())[0]
    assert before is None or before.category_key != "Perawatan_Diri"

    # Pengguna mengoreksi barang asing menjadi Perawatan_Diri.
    r = client.post(
        "/api/v1/receipts",
        json={
            "merchant_name": "TOKO UJI",
            "items": [
                {
                    "item_name": "ZORBAQU KRIPIK ORIGINAL",
                    "item_price": 10000,
                    "category_id": cats["Perawatan_Diri"]["id"],
                    "predicted_category_id": cats["Makanan"]["id"],
                }
            ],
        },
        headers=auth,
    )
    assert r.status_code == 201, r.text
    assert r.json()["items"][0]["is_user_corrected"] is True

    learning_service.retrain_now()
    assert model.learned_count >= 1
    assert ("ZORBAQU KRIPIK ORIGINAL", "Perawatan_Diri") in learning_service.load_corrections()
    after = model.predict_many([probe], ClassificationContext())[0]
    assert after is not None and after.category_key == "Perawatan_Diri"

    status = client.get("/api/v1/health").json()
    id_status = next(c for c in status["classifiers"] if c["name"] == "id_model")
    assert id_status["learned_corrections"] >= 1
