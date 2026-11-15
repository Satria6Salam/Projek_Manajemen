"""Mengukur akurasi rangkaian classifier pada data uji nama barang struk.

Pemakaian (dari folder backend):
    python -m scripts.evaluate_classifier
    python -m scripts.evaluate_classifier --pipeline ml_model
    python -m scripts.evaluate_classifier --csv tests/data/classification_eval.csv --show-errors
"""
import argparse
import csv
from collections import Counter, defaultdict
from pathlib import Path

from app.core.config import settings
from app.integrations.classifier.base import ClassificationContext
from app.integrations.classifier.chain import ClassifierChain
from app.integrations.providers import CLASSIFIER_REGISTRY

DEFAULT_CSV = Path(__file__).resolve().parents[1] / "tests" / "data" / "classification_eval.csv"


def load_rows(path: Path) -> list[tuple[str, str]]:
    with path.open(encoding="utf-8") as handle:
        return [(row["text"], row["label"]) for row in csv.DictReader(handle)]


def evaluate(pipeline: list[str], rows: list[tuple[str, str]]) -> dict:
    # user_history butuh database; dilewati saat evaluasi offline.
    names = [n for n in pipeline if n != "user_history"]
    chain = ClassifierChain([CLASSIFIER_REGISTRY[n]() for n in names])
    texts = [t for t, _ in rows]
    predictions = chain.predict_many(texts, ClassificationContext())

    correct = 0
    per_label: dict[str, Counter] = defaultdict(Counter)
    sources: Counter = Counter()
    errors: list[tuple[str, str, str, str]] = []
    for (text, gold), pred in zip(rows, predictions):
        label = pred.category_key if pred else "-"
        sources[pred.source if pred else "none"] += 1
        per_label[gold]["total"] += 1
        if label == gold:
            correct += 1
            per_label[gold]["correct"] += 1
        else:
            errors.append((text, gold, label, pred.source if pred else "none"))
    return {
        "pipeline": names,
        "accuracy": correct / len(rows) if rows else 0.0,
        "correct": correct,
        "total": len(rows),
        "per_label": per_label,
        "sources": sources,
        "errors": errors,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--pipeline", default=",".join(settings.classifier_pipeline))
    parser.add_argument("--show-errors", action="store_true")
    args = parser.parse_args()

    rows = load_rows(args.csv)
    result = evaluate([p.strip() for p in args.pipeline.split(",") if p.strip()], rows)
    print(f"Pipeline : {' -> '.join(result['pipeline'])}")
    print(f"Akurasi  : {result['accuracy']:.1%} ({result['correct']}/{result['total']})")
    print("Per kategori:")
    for label, counts in sorted(result["per_label"].items()):
        print(f"  {label:<24} {counts['correct']:>3}/{counts['total']:<3} ({counts['correct'] / counts['total']:.0%})")
    print("Sumber jawaban:", dict(result["sources"]))
    if args.show_errors:
        print("\nSalah klasifikasi:")
        for text, gold, label, source in result["errors"]:
            print(f"  {text:<32} benar={gold:<24} tebakan={label:<24} ({source})")


if __name__ == "__main__":
    main()
