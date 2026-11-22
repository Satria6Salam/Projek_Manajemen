import re
import shutil
from dataclasses import dataclass
from pathlib import Path

import pytesseract
from PIL import Image, ImageEnhance, ImageOps

from app.integrations.ocr.base import OCREngine, OcrCandidate, OcrResult
from app.integrations.ocr.enhance import ImageQuality, enhance, measure
from app.integrations.ocr.geometry import straighten

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

    @staticmethod
    def _rebuild_lines(data: dict) -> tuple[str, list[float]]:
        """Susun ulang baris dari posisi kata.

        Tesseract kadang membaca struk per kolom (semua nama barang, lalu semua harga).
        Kata-kata dikelompokkan lagi menurut posisi vertikalnya sehingga nama barang
        dan harganya kembali berada di satu baris.
        """
        from app.integrations.ocr.layout import Box

        words = []
        confs: list[float] = []
        for i, raw in enumerate(data["text"]):
            word = (raw or "").strip()
            if not word:
                continue
            top, height = data["top"][i], max(data["height"][i], 1)
            left = data["left"][i]
            words.append(Box(top + height / 2, left, left + data["width"][i], height, word))
            conf = float(data["conf"][i])
            if conf >= 0 and sum(ch.isalnum() for ch in word) >= 2:
                confs.append(conf)
        if not words:
            return "", confs
        from app.integrations.ocr.layout import layout_lines

        return layout_lines(words, 0.55), confs

    def _read(self, prepared: Image.Image, psm: int, enhanced: bool) -> _Reading:
        data = pytesseract.image_to_data(
            prepared, lang=self.lang, config=f"--oem 3 --psm {psm}", output_type=pytesseract.Output.DICT
        )
        text, confs = self._rebuild_lines(data)
        mean_conf = sum(confs) / len(confs) if confs else 0.0
        prices = len(_PRICE.findall(text))
        score = sum(c / 100 for c in confs) + 1.5 * prices
        return _Reading(text.strip(), score, mean_conf, enhanced)

    def _weak(self, reading: _Reading) -> bool:
        words = len(reading.text.split())
        return reading.mean_conf < self.GOOD_MEAN_CONF or words < self.MIN_WORDS

    def extract(self, image: Image.Image) -> OcrResult:
        image = ImageOps.exif_transpose(image)
        # Potong latar, luruskan perspektif, dan putar baris yang miring.
        image, geometry_steps = straighten(image)
        # Foto HP 12 MP terlalu besar untuk Tesseract (lambat tanpa menambah ketajaman huruf).
        if max(image.size) > 2400:
            image = image.copy()
            image.thumbnail((2400, 2400), Image.LANCZOS)
        quality: ImageQuality = measure(image)
        readings: list[tuple[str, _Reading]] = [("asli", self._read(self.preprocess(image), self.psm, enhanced=False))]

        if quality.has_issue or self._weak(readings[0][1]):
            readings.append(("diperjelas", self._read(enhance(image, quality).image, self.psm, enhanced=True)))
            best = max((r for _, r in readings), key=lambda r: r.score)
            if self._weak(best):
                # Mode blok (psm 6) lebih tahan pada tulisan rapat/buram.
                readings.append(("diperjelas psm6", self._read(enhance(image, quality).image, 6, enhanced=True)))
            if quality.is_blurry and self._weak(max((r for _, r in readings), key=lambda r: r.score)):
                readings.append(("pertajam kuat", self._read(enhance(image, quality, strong=True).image, 6, enhanced=True)))

        best = max((r for _, r in readings), key=lambda r: r.score)
        candidates = [OcrCandidate(r.text, r.score, r.enhanced, label) for label, r in readings]
        return OcrResult(best.text, quality.notes, best.enhanced, candidates)

    def extra_candidates(self, image: Image.Image) -> list[OcrCandidate]:
        """Bacaan tambahan bila bacaan biasa belum konsisten (dipanggil layanan scan).

        Mode psm 4 kadang melewatkan kolom angka yang jauh di kanan (spasi lebar).
        Mode blok (psm 6) dan teks jarang (psm 11) membaca setiap kata di mana pun
        letaknya; baris lalu disusun ulang dari posisi kata.
        """
        image, _ = straighten(ImageOps.exif_transpose(image))
        prepared = self.preprocess(image)
        out = []
        for psm, label in ((6, "mode blok psm6"), (11, "teks jarang psm11")):
            r = self._read(prepared, psm, enhanced=False)
            out.append(OcrCandidate(r.text, r.score, False, label))
        return out

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
