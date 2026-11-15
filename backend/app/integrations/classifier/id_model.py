"""Model TF-IDF + Multinomial Naive Bayes untuk nama barang berbahasa Indonesia.

Berbeda dengan model utama (`ml_model`, dilatih dari katalog BigBasket berbahasa
Inggris), model ini dilatih saat server start dari:
- app/data/training_items_id.json  (±8.000 nama barang Indonesia, sumber smart_receipt_v2)
- app/data/keyword_rules.json      (kata kunci & merek yang sudah dikurasi)

Fiturnya gabungan kata utuh dan n-gram karakter (2-5 huruf), sehingga tetap
mengenali nama barang yang tersingkat atau sedikit salah baca OCR
("INDOMI GRG", "PEPSODNT"). Bila keyakinan di bawah `min_confidence`, model
tidak menjawab dan classifier berikutnya di rangkaian yang mencoba.
"""
from __future__ import annotations

import json
import logging
import threading
from collections.abc import Callable
from datetime import datetime
from pathlib import Path

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.naive_bayes import MultinomialNB
from sklearn.pipeline import FeatureUnion, Pipeline

from app.integrations.classifier.base import ClassificationContext, ItemClassifier, Prediction
from app.integrations.classifier.text_normalizer import TextNormalizer

logger = logging.getLogger("strukku")

# Kata kunci terkurasi diulang agar bobotnya lebih besar daripada data umum.
KEYWORD_WEIGHT = 3
CORRECTION_WEIGHT = 5


def load_training_samples(training_path: Path, rules_path: Path) -> list[tuple[str, str]]:
    samples: list[tuple[str, str]] = []
    if training_path.exists():
        data = json.loads(training_path.read_text(encoding="utf-8"))
        for label, items in data.get("categories", {}).items():
            samples.extend((text, label) for text in items)
    if rules_path.exists():
        rules = json.loads(rules_path.read_text(encoding="utf-8"))
        for label, keywords in rules.get("categories", {}).items():
            for keyword in keywords:
                samples.extend([(keyword, label)] * KEYWORD_WEIGHT)
    return samples


class IndonesianItemModel(ItemClassifier):
    name = "id_model"

    def __init__(
        self,
        training_path: Path,
        rules_path: Path,
        normalizer: TextNormalizer | None = None,
        min_confidence: float = 0.5,
        corrections_loader: Callable[[], list[tuple[str, str]]] | None = None,
    ):
        self.training_path = training_path
        self.rules_path = rules_path
        self.normalizer = normalizer or TextNormalizer()
        self.min_confidence = min_confidence
        self.pipeline: Pipeline | None = None
        self.sample_count = 0
        self.learned_count = 0
        self.trained_at: datetime | None = None
        self.corrections_loader = corrections_loader
        self.error: str | None = None
        self._lock = threading.Lock()
        self._train()

    def _corrections(self) -> list[tuple[str, str]]:
        if self.corrections_loader is None:
            return []
        try:
            return self.corrections_loader()
        except Exception:  # database belum siap (mis. saat migrasi pertama)
            logger.warning("Koreksi pengguna belum bisa dibaca untuk melatih model.", exc_info=True)
            return []

    def retrain(self) -> None:
        """Latih ulang dengan data terbaru (termasuk koreksi pengguna)."""
        self._train()

    def _train(self) -> None:
        try:
            samples = load_training_samples(self.training_path, self.rules_path)
            corrections = self._corrections()
            # Koreksi pengguna adalah data paling relevan (teks struk asli) -> bobot lebih besar.
            samples += [(text, label) for text, label in corrections for _ in range(CORRECTION_WEIGHT)]
            if not samples:
                self.error = "Data latih model Indonesia tidak ditemukan."
                logger.warning(self.error)
                return
            texts = [self.normalizer.basic(self.normalizer.expand(self.normalizer.basic(t))) for t, _ in samples]
            labels = [label for _, label in samples]
            features = FeatureUnion([
                ("word", TfidfVectorizer(analyzer="word", ngram_range=(1, 2), sublinear_tf=True, token_pattern=r"[a-z]{2,}")),
                ("char", TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 5), sublinear_tf=True, min_df=2)),
            ])
            # fit_prior=False: kategori "Lainnya" yang datanya paling banyak tidak mendominasi.
            pipeline = Pipeline([("features", features), ("nb", MultinomialNB(alpha=0.2, fit_prior=False))])
            pipeline.fit(texts, labels)
            with self._lock:  # tukar model secara atomik; prediksi lama tetap jalan
                self.pipeline = pipeline
                self.sample_count = len(samples)
                self.learned_count = len(corrections)
                self.trained_at = datetime.now()
                self.error = None
        except Exception as exc:  # data rusak / versi sklearn
            self.error = f"Gagal melatih model Indonesia: {exc}"
            logger.exception(self.error)

    @property
    def is_ready(self) -> bool:
        return self.pipeline is not None

    @property
    def classes(self) -> list[str]:
        return [str(c) for c in self.pipeline.classes_] if self.pipeline is not None else []

    def probabilities(self, texts: list[str]) -> list[dict[str, float]]:
        if not self.is_ready or not texts:
            return [{} for _ in texts]
        prepared = [self.normalizer.normalize(t) or self.normalizer.basic(t) for t in texts]
        with self._lock:
            pipeline = self.pipeline
        rows = pipeline.predict_proba(prepared)
        return [dict(zip(map(str, pipeline.classes_), map(float, row))) for row in rows]

    def _coverage(self, text: str) -> float:
        repairer = self.normalizer.repairer
        if repairer is None:
            return 1.0
        return repairer.coverage(self.normalizer.normalize(text))

    def predict_many(self, texts: list[str], ctx: ClassificationContext) -> list[Prediction | None]:
        results: list[Prediction | None] = []
        for text, probs in zip(texts, self.probabilities(texts)):
            if not probs:
                results.append(None)
                continue
            label, probability = max(probs.items(), key=lambda kv: kv[1])
            if probability < self.min_confidence:
                results.append(None)
                continue
            # Naive Bayes cenderung terlalu yakin. Keyakinan yang dilaporkan diturunkan
            # bila sebagian kata tidak dikenal kosakata, sehingga barang asing atau
            # hasil foto buram tetap ditandai "Periksa" walau tebakannya sering benar.
            confidence = probability * (0.5 + 0.5 * self._coverage(text))
            results.append(Prediction(label, confidence, self.name))
        return results

    def status(self) -> dict:
        return {
            "name": self.name,
            "ready": self.is_ready,
            "samples": self.sample_count,
            "learned_corrections": self.learned_count,
            "trained_at": self.trained_at.isoformat(timespec="seconds") if self.trained_at else None,
            "classes": self.classes,
            "message": self.error or "OK",
        }
