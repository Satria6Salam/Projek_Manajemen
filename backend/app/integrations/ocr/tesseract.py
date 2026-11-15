import re
import shutil
from dataclasses import dataclass
from pathlib import Path

import pytesseract
from PIL import Image, ImageEnhance, ImageOps

from app.integrations.ocr.base import OCREngine, OcrResult
from app.integrations.ocr.enhance import ImageQuality, enhance, measure

_PRICE = re.compile(r"\d{1,3}([.,]\d{3})+|\d{4,}")


@dataclass
class _Reading:
    text: str
    score: float
    mean_conf: float
    enhanced: bool


class TesseractOCR(OCREngine):
    """OCR Tesseract dengan pembacaan bertingkat untuk foto buram.

    1. Baca foto dengan praproses ringan.
    2. Bila foto bermasalah (buram/gelap/pudar/berbayang) atau hasilnya lemah,
       foto diperjelas (lihat enhance.py) lalu dibaca ulang.
    3. Bila masih lemah dan foto buram, dicoba penajaman kuat + mode blok (psm 6).
    Hasil dengan skor tertinggi (keyakinan kata x jumlah kata + harga terbaca) dipakai.
    """

    name = "tesseract"
    # Hasil dianggap cukup baik bila rata-rata keyakinan kata >= nilai ini.
    GOOD_MEAN_CONF = 75
    MIN_WORDS = 8

    def __init__(self, tesseract_cmd: str = "", lang: str = "ind+eng", psm: int = 4):
        self.lang = lang
        self.psm = psm
        if tesseract_cmd and Path(tesseract_cmd).exists():
            pytesseract.pytesseract.tesseract_cmd = tesseract_cmd

    @staticmethod
    def preprocess(image: Image.Image) -> Image.Image:
        image = ImageOps.exif_transpose(image)  # foto HP sering tersimpan miring
        image = ImageOps.grayscale(image)
        # Teks struk kecil; perbesar gambar beresolusi rendah agar terbaca.
        if image.width < 1000:
            scale = 1000 / image.width
            image = image.resize((1000, int(image.height * scale)), Image.LANCZOS)
        image = ImageOps.autocontrast(image, cutoff=1)
        return ImageEnhance.Sharpness(image).enhance(1.5)

    def _read(self, prepared: Image.Image, psm: int, enhanced: bool) -> _Reading:
        data = pytesseract.image_to_data(
            prepared, lang=self.lang, config=f"--oem 3 --psm {psm}", output_type=pytesseract.Output.DICT
        )
        lines: dict[tuple[int, int, int], list[str]] = {}
        confs: list[float] = []
        for i, word in enumerate(data["text"]):
            word = (word or "").strip()
            if not word:
                continue
            key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
            lines.setdefault(key, []).append(word)
            conf = float(data["conf"][i])
            if conf >= 0 and sum(ch.isalnum() for ch in word) >= 2:
                confs.append(conf)
        text = "\n".join(" ".join(words) for _, words in sorted(lines.items()))
        mean_conf = sum(confs) / len(confs) if confs else 0.0
        prices = len(_PRICE.findall(text))
        score = sum(c / 100 for c in confs) + 1.5 * prices
        return _Reading(text.strip(), score, mean_conf, enhanced)

    def _weak(self, reading: _Reading) -> bool:
        words = len(reading.text.split())
        return reading.mean_conf < self.GOOD_MEAN_CONF or words < self.MIN_WORDS

    def extract(self, image: Image.Image) -> OcrResult:
        quality: ImageQuality = measure(image)
        readings = [self._read(self.preprocess(image), self.psm, enhanced=False)]

        if quality.has_issue or self._weak(readings[0]):
            readings.append(self._read(enhance(image, quality).image, self.psm, enhanced=True))
            best = max(readings, key=lambda r: r.score)
            if quality.is_blurry and self._weak(best):
                readings.append(self._read(enhance(image, quality, strong=True).image, 6, enhanced=True))

        best = max(readings, key=lambda r: r.score)
        return OcrResult(best.text, quality.notes, best.enhanced)

    def extract_text(self, image: Image.Image) -> str:
        return self.extract(image).text

    def status(self) -> dict:
        cmd = pytesseract.pytesseract.tesseract_cmd
        if not (Path(cmd).exists() or shutil.which(cmd)):
            return {
                "engine": self.name,
                "ready": False,
                "message": "Tesseract tidak ditemukan. Instal Tesseract atau isi TESSERACT_CMD di .env.",
            }
        try:
            version = str(pytesseract.get_tesseract_version())
            langs = set(pytesseract.get_languages(config=""))
        except Exception as exc:  # pragma: no cover - tergantung instalasi
            return {"engine": self.name, "ready": False, "message": f"Tesseract error: {exc}"}
        missing = [code for code in self.lang.split("+") if code not in langs]
        if missing:
            return {
                "engine": self.name,
                "ready": False,
                "version": version,
                "message": f"Data bahasa OCR belum terpasang: {', '.join(missing)}",
            }
        return {"engine": self.name, "ready": True, "version": version, "languages": self.lang, "message": "OK"}
