"""Membuat varian nama barang dengan gangguan khas OCR untuk data uji.

Gangguan yang ditiru (deterministik, seed tetap):
- huruf mirip tertukar: O<->0, I/l<->1, S<->5, B<->8
- satu huruf hilang
- satu kata terpecah dengan spasi ("FRESHMILK" -> "FRESHMI LK")
- dua kata tergabung tanpa spasi

Pemakaian:
    python -m scripts.make_ocr_noise tests/data/classification_eval.csv tests/data/classification_eval_ocr.csv
"""
import csv
import random
import sys
from pathlib import Path

SWAPS = {"O": "0", "0": "O", "I": "1", "L": "1", "S": "5", "B": "8", "E": "F", "G": "6"}


def _swap(text: str, rng: random.Random) -> str:
    spots = [i for i, ch in enumerate(text) if ch in SWAPS]
    if not spots:
        return text
    i = rng.choice(spots)
    return text[:i] + SWAPS[text[i]] + text[i + 1:]


def _drop(text: str, rng: random.Random) -> str:
    spots = [i for i, ch in enumerate(text) if ch.isalpha()]
    if len(spots) < 5:
        return text
    i = rng.choice(spots[1:-1])
    return text[:i] + text[i + 1:]


def _split(text: str, rng: random.Random) -> str:
    words = text.split()
    long_words = [i for i, w in enumerate(words) if len(w) >= 6 and w.isalpha()]
    if not long_words:
        return text
    i = rng.choice(long_words)
    w = words[i]
    cut = rng.randint(2, len(w) - 2)
    words[i] = f"{w[:cut]} {w[cut:]}"
    return " ".join(words)


def _merge(text: str, rng: random.Random) -> str:
    words = text.split()
    if len(words) < 2:
        return text
    i = rng.randrange(len(words) - 1)
    return " ".join(words[:i] + [words[i] + words[i + 1]] + words[i + 2:])


NOISES = [_swap, _drop, _split, _merge]


def noisy(text: str, rng: random.Random) -> str:
    out = text
    for fn in rng.sample(NOISES, k=2):
        out = fn(out, rng)
    return out


def main(src: str, dst: str) -> None:
    rng = random.Random(2026)
    with Path(src).open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    with Path(dst).open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["text", "label"])
        for row in rows:
            writer.writerow([noisy(row["text"], rng), row["label"]])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
