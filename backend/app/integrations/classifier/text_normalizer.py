"""Normalisasi nama barang sebelum diklasifikasikan."""
from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.integrations.classifier.ocr_repair import OcrTextRepairer

_NON_WORD = re.compile(r"[^0-9a-z&' ]+")
_SPACES = re.compile(r"\s+")


class TextNormalizer:
    def __init__(self, abbreviations: dict[str, str] | None = None, repairer: OcrTextRepairer | None = None):
        abbreviations = {k.lower(): v.lower() for k, v in (abbreviations or {}).items()}
        self.phrase_abbr = {k: v for k, v in abbreviations.items() if " " in k}
        self.word_abbr = {k: v for k, v in abbreviations.items() if " " not in k}
        self.repairer = repairer

    def basic(self, text: str) -> str:
        text = _NON_WORD.sub(" ", text.lower())
        return _SPACES.sub(" ", text).strip()

    def expand(self, text: str) -> str:
        text = f" {text} "
        for short, full in self.phrase_abbr.items():
            text = text.replace(f" {short} ", f" {full} ")
        return " ".join(self.word_abbr.get(w, w) for w in text.split())

    def normalize(self, text: str) -> str:
        text = self.expand(self.basic(text))
        if self.repairer is not None:
            # Singkatan diperluas dulu agar "shp" tidak "dikoreksi" menjadi kata lain,
            # lalu diperluas sekali lagi untuk singkatan yang baru muncul setelah perbaikan.
            text = self.expand(self.repairer.repair(text))
        return text
