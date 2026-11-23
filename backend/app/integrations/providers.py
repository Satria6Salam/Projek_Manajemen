"""Titik pusat pemilihan implementasi (OCR, parser, classifier, storage).

Untuk menambah implementasi baru:
1. Buat kelas turunan dari base class yang sesuai di folder integrations/.
2. Daftarkan di dictionary *_REGISTRY di bawah.
3. Pilih lewat .env (OCR_ENGINE, STORAGE_BACKEND, CLASSIFIER_PIPELINE).

Semua fungsi `get_*` dipakai sebagai dependency FastAPI, sehingga di
pengujian bisa diganti dengan `app.dependency_overrides`.
"""
import json
import re
from collections import Counter
from functools import lru_cache

from app.core.config import settings
from app.integrations.classifier.base import ItemClassifier
from app.integrations.classifier.chain import ClassifierChain
from app.integrations.classifier.id_model import IndonesianItemModel
from app.integrations.classifier.keyword_rules import KeywordRuleClassifier
from app.integrations.classifier.ocr_repair import OcrTextRepairer
from app.integrations.classifier.sklearn_model import SklearnModelClassifier
from app.integrations.classifier.text_normalizer import TextNormalizer
from app.integrations.classifier.user_history import UserHistoryClassifier
from app.integrations.ocr.base import OCREngine
from app.integrations.ocr.tesseract import TesseractOCR
from app.integrations.parser.base import ReceiptParser
from app.integrations.parser.regex_parser import RegexReceiptParser
from app.integrations.storage.base import StorageBackend
from app.integrations.storage.local import LocalStorage
from app.integrations.storage.supabase import SupabaseStorage

def _tesseract() -> TesseractOCR:
    return TesseractOCR(settings.TESSERACT_CMD, settings.OCR_LANG, settings.OCR_PSM)


def _rapid():
    from app.integrations.ocr.rapid import RapidOCREngine

    mode = settings.OCR_TESSERACT.lower()
    return RapidOCREngine(tesseract=None if mode == "off" else _tesseract(), tesseract_mode=mode)


def _auto():
    """RapidOCR (model PaddleOCR) bila terpasang, Tesseract sebagai cadangan; selain itu Tesseract."""
    from app.integrations.ocr.rapid import rapidocr_available

    return _rapid() if rapidocr_available() else _tesseract()


OCR_REGISTRY = {
    "auto": _auto,
    "rapid": _rapid,
    "tesseract": _tesseract,
}
STORAGE_REGISTRY = {
    "local": lambda: LocalStorage(settings.path(settings.UPLOAD_DIR)),
    "supabase": lambda: SupabaseStorage(
        settings.SUPABASE_URL,
        settings.SUPABASE_SERVICE_ROLE_KEY,
        settings.SUPABASE_STORAGE_BUCKET,
        settings.SUPABASE_SIGNED_URL_EXPIRY_SECONDS,
    ),
}
PARSER_REGISTRY = {
    "regex": RegexReceiptParser,
}


def _read_json(path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


@lru_cache
def get_normalizer() -> TextNormalizer:
    """Normalizer bersama: perluas singkatan + perbaiki salah baca OCR.

    Kosakata perbaikan diambil dari kata kunci, singkatan, dan data latih Indonesia.
    """
    rules = _read_json(settings.path(settings.KEYWORD_RULES_PATH))
    abbreviations = rules.get("abbreviations", {})
    if not settings.OCR_TEXT_REPAIR:
        return TextNormalizer(abbreviations)

    base = TextNormalizer(abbreviations)
    vocabulary: Counter[str] = Counter()
    joined: dict[str, str] = {}
    bigrams: set[str] = set()
    phrases: list[str] = []
    domains: dict[str, set[str]] = {}

    def add_domain(text: str, domain: str) -> None:
        for w in base.basic(text).split():
            if w.isalpha() and len(w) >= 3:
                domains.setdefault(w, set()).add(domain)

    for category, keywords in rules.get("categories", {}).items():
        phrases.extend(keywords)
        for keyword in keywords:
            add_domain(keyword, category)
    phrases.extend(abbreviations.values())
    training = _read_json(settings.path(settings.TRAINING_ITEMS_PATH))
    for category, items in training.get("categories", {}).items():
        phrases.extend(items)
        for item in items:
            add_domain(item, category)
    for phrase in phrases:
        words = base.basic(phrase).split()
        vocabulary.update(w for w in words if not w.isdigit())
        alpha = [w for w in words if w.isalpha()]
        bigrams.update(f"{a} {b}" for a, b in zip(alpha, alpha[1:]))
        if 2 <= len(words) <= 3 and all(w.isalpha() for w in words):
            joined.setdefault("".join(words), " ".join(words))
    for short in abbreviations:
        if " " not in short:
            vocabulary[short.lower()] += 1
    # Kosakata umum (elektronik, perkakas, ATK, ukuran, warna, ...): kata sah seperti "ukuran"
    # atau "strip" tidak boleh "diperbaiki" menjadi kata belanja ("cukuran", "sirup").
    general = settings.path("app/data/general_vocabulary.txt")
    hyphenated: set[str] = set()
    if general.exists():
        section = "umum"
        for line in general.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("# ---"):
                section = line.strip("# -").strip().lower()
                continue
            if line.strip().startswith("#"):
                continue
            hyphenated.update(re.findall(r"[a-z]+-[a-z]+", line.lower()))
            for word in base.basic(line).split():
                if word.isalpha() and len(word) >= 2:
                    vocabulary[word] += 1
            add_domain(line, section)
    return TextNormalizer(abbreviations, OcrTextRepairer(vocabulary, joined, bigrams, domains, hyphenated))


CLASSIFIER_REGISTRY = {
    "user_history": UserHistoryClassifier,
    "keyword_rules": lambda: KeywordRuleClassifier(settings.path(settings.KEYWORD_RULES_PATH), get_normalizer()),
    "id_model": lambda: get_id_model(),
    "ml_model": lambda: get_ml_model(),
}


def _pick(registry: dict, key: str, label: str):
    if key not in registry:
        raise ValueError(f"{label} '{key}' tidak dikenal. Pilihan: {', '.join(registry)}")
    return registry[key]()


@lru_cache
def get_ocr_engine() -> OCREngine:
    return _pick(OCR_REGISTRY, settings.OCR_ENGINE, "OCR_ENGINE")


@lru_cache
def get_vision_extractor():
    """Pembaca struk Claude vision, atau None bila dimatikan / tanpa kredensial Anthropic."""
    if settings.VISION_EXTRACTION.strip().lower() != "claude":
        return None
    from app.integrations.vision.claude_extractor import ClaudeReceiptExtractor

    extractor = ClaudeReceiptExtractor(
        model=settings.CLAUDE_VISION_MODEL,
        effort=settings.CLAUDE_VISION_EFFORT,
        timeout=settings.CLAUDE_VISION_TIMEOUT_SECONDS,
        api_key=settings.ANTHROPIC_API_KEY,
    )
    return extractor if extractor.configured() else None


@lru_cache
def get_storage() -> StorageBackend:
    return _pick(STORAGE_REGISTRY, settings.STORAGE_BACKEND, "STORAGE_BACKEND")


@lru_cache
def get_parser() -> ReceiptParser:
    return _pick(PARSER_REGISTRY, "regex", "PARSER")


@lru_cache
def get_ml_model() -> SklearnModelClassifier:
    return SklearnModelClassifier(settings.path(settings.MODEL_PATH), get_normalizer())


@lru_cache
def get_id_model() -> IndonesianItemModel:
    return IndonesianItemModel(
        settings.path(settings.TRAINING_ITEMS_PATH),
        settings.path(settings.KEYWORD_RULES_PATH),
        get_normalizer(),
        settings.ID_MODEL_MIN_CONFIDENCE,
        corrections_loader=_load_corrections if settings.LEARN_FROM_CORRECTIONS else None,
    )


def _load_corrections() -> list[tuple[str, str]]:
    from app.services.learning_service import load_corrections

    return load_corrections()


@lru_cache
def get_classifier() -> ClassifierChain:
    classifiers: list[ItemClassifier] = [
        _pick(CLASSIFIER_REGISTRY, name, "CLASSIFIER_PIPELINE") for name in settings.classifier_pipeline
    ]
    return ClassifierChain(classifiers)
