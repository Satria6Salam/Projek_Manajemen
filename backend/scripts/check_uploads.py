"""Jalankan OCR -> parser -> klasifikasi pada foto struk tersimpan untuk diperiksa.

Pemakaian (dari folder backend):
    python -m scripts.check_uploads storage/uploads/2/*.jpg
"""
import sys

from PIL import Image

from app.integrations.classifier.base import ClassificationContext
from app.integrations.providers import get_classifier, get_ocr_engine, get_parser


def main(paths: list[str]) -> None:
    for path in paths:
        result = get_ocr_engine().extract(Image.open(path).convert("RGB"))
        parsed = get_parser().parse(result.text)
        preds = get_classifier().predict_many([i.name for i in parsed.items], ClassificationContext())
        items_sum = sum(i.price or 0 for i in parsed.items)
        ok = parsed.total_amount is not None and abs(items_sum - parsed.total_amount) < 1
        print(f"\n=== {path}")
        print(f"toko={parsed.merchant_name!r} alamat={parsed.merchant_address!r} "
              f"total={parsed.total_amount} jumlah_barang={items_sum} {'COCOK' if ok else 'TIDAK COCOK'}")
        for item, pred in zip(parsed.items, preds):
            cat = f"{pred.category_key} ({pred.source} {pred.confidence:.2f})" if pred else "-"
            print(f"   {item.quantity}x {item.name!r:<34} {item.price:>10,.0f}  -> {cat}")


if __name__ == "__main__":
    main(sys.argv[1:])
