"""OCR lokal berbasis model PaddleOCR (RapidOCR, ONNX Runtime) dengan cadangan Tesseract.

Tesseract dirancang untuk dokumen hasil pindai yang bersih; pada foto HP struk thermal
(tinta pudar, kertas terlipat, cetakan dot-matrix) angka di kolom harga sering rusak.
Model deteksi + pengenalan teks PaddleOCR dilatih pada foto teks di dunia nyata, sehingga
jauh lebih tahan pada kondisi itu. Semuanya berjalan lokal: gratis dan foto tidak dikirim
ke mana pun.

Alur: luruskan foto (geometry.straighten) -> RapidOCR -> susun baris dari posisi kotak teks.
Bila hasil parsing belum konsisten, layanan scan meminta bacaan tambahan (extra_candidates)
dari Tesseract, lalu memilih bacaan terbaik.
"""
from __future__ import annotations

import logging
import threading

import numpy as np
from PIL import Image, ImageOps

from app.integrations.ocr.base import OCREngine, OcrCandidate, OcrResult
from app.integrations.ocr.enhance import measure
from app.integrations.ocr.geometry import straighten
from app.integrations.ocr.tesseract import TesseractOCR

logger = logging.getLogger("strukku")

# Sisi terpanjang foto yang dibaca: cukup untuk huruf struk, menjaga waktu proses ~2-4 detik.
MAX_SIDE = 2000


def rapidocr_available() -> bool:
    try:
        import rapidocr_onnxruntime  # noqa: F401
    except Exception:
        return False
    return True


from app.integrations.ocr.layout import Box, layout_lines  # noqa: E402


def rebuild_lines(boxes: list[tuple[float, float, float, str]]) -> str:
    """boxes = (pusat_y, kiri_x, tinggi, teks). Kelompokkan per baris lalu urutkan kiri->kanan."""
    if not boxes:
        return ""
    boxes = sorted(boxes)
    heights = sorted(b[2] for b in boxes)
    tolerance = 0.5 * heights[len(heights) // 2]
    lines: list[list[tuple]] = []
    centers: list[float] = []
    for box in boxes:
        if lines and abs(box[0] - centers[-1]) <= tolerance:
            lines[-1].append(box)
            centers[-1] = sum(b[0] for b in lines[-1]) / len(lines[-1])
        else:
            lines.append([box])
            centers.append(box[0])
    return "\n".join(" ".join(b[3] for b in sorted(line, key=lambda b: b[1])) for line in lines)


class RapidOCREngine(OCREngine):
    name = "rapid"

    def __init__(self, tesseract: TesseractOCR | None = None, tesseract_mode: str = "on_demand"):
        self._engine = None
        # on_demand: Tesseract tidak ikut di extract(); layanan scan memanggil
        # tesseract_candidates() hanya bila bacaan lain belum yakin.
        self.tesseract_mode = tesseract_mode
        self._lock = threading.Lock()
        self.tesseract = tesseract

    def _get(self):
        with self._lock:
            if self._engine is None:
                from rapidocr_onnxruntime import RapidOCR

                self._engine = RapidOCR()
            return self._engine

    def _read(self, image: Image.Image) -> tuple[str, float]:
        image = image.convert("RGB")
        image.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
        result, _ = self._get()(np.asarray(image))
        boxes, confs = [], []
        for box, text, conf in result or []:
            ys = [p[1] for p in box]
            xs = [p[0] for p in box]
            boxes.append(Box((min(ys) + max(ys)) / 2, min(xs), max(xs), max(ys) - min(ys), text))
            confs.append(float(conf))
        return layout_lines(boxes), sum(confs)

    def extract(self, image: Image.Image) -> OcrResult:
        image = ImageOps.exif_transpose(image)
        straight, _ = straighten(image)
        quality = measure(straight)
        text, score = self._read(straight)
        candidates = [OcrCandidate(text, score, False, "RapidOCR")]
        enhanced = False
        # Hibrida: Tesseract tetap dibaca. RapidOCR unggul pada foto HP (tinta pudar, kertas
        # terlipat); Tesseract unggul pada cetakan bersih (spasi antarkata lebih rapi).
        # Layanan scan memilih bacaan yang hasil parsing-nya paling konsisten.
        if self.tesseract is not None and self.tesseract_mode == "always":
            try:
                tess = self.tesseract.extract(image)
                candidates += tess.candidates
                enhanced = tess.enhanced
            except Exception:
                logger.exception("Tesseract (pembanding) gagal")
        return OcrResult(text, quality.notes, enhanced, candidates)

    def tesseract_candidates(self, image: Image.Image) -> list[OcrCandidate]:
        """Bacaan utama Tesseract, untuk mode on_demand (kosong bila sudah ikut / mati)."""
        if self.tesseract is None or self.tesseract_mode != "on_demand":
            return []
        try:
            return self.tesseract.extract(image).candidates
        except Exception:
            logger.exception("Tesseract (penengah) gagal")
            return []

    def extra_candidates(self, image: Image.Image) -> list[OcrCandidate]:
        """Cadangan: bacaan Tesseract (foto asli/diperjelas, beberapa mode)."""
        if self.tesseract is None:
            return []
        try:
            return self.tesseract.extra_candidates(image)
        except Exception:
            logger.exception("Tesseract cadangan gagal")
            return []

    def extract_text(self, image: Image.Image) -> str:
        return self.extract(image).text

    def status(self) -> dict:
        if not rapidocr_available():
            return {"engine": self.name, "ready": False,
                    "message": "Paket rapidocr-onnxruntime belum terpasang (pip install rapidocr-onnxruntime)."}
        return {"engine": self.name, "ready": True, "message": "OK",
                "fallback": self.tesseract.status() if self.tesseract else None}
