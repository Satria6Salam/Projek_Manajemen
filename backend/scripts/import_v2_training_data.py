"""Mengambil data latih nama barang berbahasa Indonesia dari smart_receipt_v2
(`lib/services/ml_training_data.dart`) dan memetakannya ke 6 kategori STRUKKU.

Hasil: app/data/training_items_id.json  ->  {"Makanan": [...], "Minuman": [...], ...}

Pemakaian (dari folder backend):
    python -m scripts.import_v2_training_data D:/smart_receipt_v2/lib/services/ml_training_data.dart
"""
import json
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "app" / "data" / "training_items_id.json"

# Kategori smart_receipt_v2 (15) -> kategori STRUKKU (6).
# "Konsumsi" dan "Bahan Makanan" dipecah menjadi Makanan / Minuman memakai DRINK.
CATEGORY_MAP = {
    "konsumsi": None,
    "bahanMakanan": None,
    "kesehatan": "Kesehatan",
    "perawatanDiri": "Perawatan_Diri",
    "rumahTangga": "Kebutuhan_Rumah_Tangga",
    "transportasi": "Lainnya",
    "pakaianAksesori": "Lainnya",
    "elektronik": "Lainnya",
    "pendidikan": "Lainnya",
    "hiburan": "Lainnya",
    "tagihanUtilitas": "Lainnya",
    "jasaLayanan": "Lainnya",
    "donasiSosial": "Lainnya",
    "belanja": "Lainnya",
    "lainnya": "Lainnya",
}

DRINK = re.compile(
    r"\b(kopi|coffee|cofee|teh|tea|jus|juice|susu|milk|minum|minuman|air mineral|air putih|aqua|"
    r"soda|sirup|syrup|latte|cappuccino|cappucino|espresso|americano|macchiato|mocha|frappe|"
    r"boba|bubble|smoothie|milkshake|shake|squash|lemonade|wedang|bandrek|sekoteng|bajigur|"
    r"jamu|cendol|dawet|cincau|es jeruk|es kelapa|kelapa muda|es campur|es buah|es doger|"
    r"es teler|yakult|yogurt drink|soft drink|cola|sprite|fanta|pocari|isotonik|energy drink|"
    r"kratingdaeng|extra joss|hemaviton|wine|beer|bir|tuak|matcha|chocolate drink|cokelat panas|"
    r"coklat panas|ice blend|thai tea|teh tarik|ovaltine|milo|nutrisari|marimas|pop ice|"
    r"le minerale|vit|club|ades|cleo)\b"
)
# Makanan yang mengandung kata minuman, tetap Makanan.
FOOD_OVERRIDE = re.compile(r"\b(es krim|ice cream|roti susu|kue|cake|puding|pudding|permen|mie|nasi|ayam|bakso)\b")

ENTRY = re.compile(r"^\s{4}(\w+): <String>\[")
ITEM = re.compile(r"^\s+'((?:[^'\\]|\\.)*)',?\s*$")


def parse_dart(path: Path) -> dict[str, list[str]]:
    data: dict[str, list[str]] = {}
    current = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = ENTRY.match(line)
        if m:
            current = m.group(1)
            data[current] = []
            continue
        if current and line.strip().startswith("],"):
            current = None
            continue
        if current:
            m = ITEM.match(line)
            if m:
                data[current].append(m.group(1).replace("\\'", "'"))
    return data


def map_category(source: str, text: str) -> str:
    target = CATEGORY_MAP.get(source, "Lainnya")
    if target is not None:
        return target
    low = text.lower()
    if DRINK.search(low) and not FOOD_OVERRIDE.search(low):
        return "Minuman"
    return "Makanan"


def main(dart_file: str) -> None:
    raw = parse_dart(Path(dart_file))
    result: dict[str, set[str]] = {}
    for source, items in raw.items():
        for text in items:
            text = " ".join(text.lower().split())
            if text:
                result.setdefault(map_category(source, text), set()).add(text)
    # Satu teks hanya boleh punya satu kategori.
    seen: dict[str, str] = {}
    for label in sorted(result):
        for text in sorted(result[label]):
            seen.setdefault(text, label)
    final: dict[str, list[str]] = {}
    for text, label in seen.items():
        final.setdefault(label, []).append(text)
    payload = {
        "_info": "Data latih nama barang berbahasa Indonesia (sumber: smart_receipt_v2 ml_training_data.dart), "
        "dipetakan ke 6 kategori STRUKKU oleh scripts/import_v2_training_data.py.",
        "categories": {k: sorted(v) for k, v in sorted(final.items())},
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    for label, items in payload["categories"].items():
        print(f"{label:<24} {len(items)}")
    print(f"Tersimpan: {OUT}")


if __name__ == "__main__":
    main(sys.argv[1])
