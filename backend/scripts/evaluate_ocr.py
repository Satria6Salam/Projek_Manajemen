"""Membandingkan OCR lama vs baru pada foto struk yang dibuat buram/gelap.

Pemakaian (dari folder backend):
    python -m scripts.evaluate_ocr path/ke/foto_struk.jpg [foto2.jpg ...]

Untuk setiap foto dibuat varian: asli, buram ringan/sedang/berat, gelap,
resolusi rendah. Teks hasil foto asli (cara baru) dipakai sebagai acuan;
kemiripan dihitung per karakter (difflib), ditambah jumlah barang & total
yang berhasil diparsing.
"""
import difflib
import sys
import time
from pathlib import Path

import pytesseract
from PIL import Image, ImageEnhance, ImageFilter

from app.core.config import settings
from app.integrations.ocr.tesseract import TesseractOCR
from app.integrations.parser.regex_parser import RegexReceiptParser


def variants(image: Image.Image) -> dict[str, Image.Image]:
    small = image.copy()
    small.thumbnail((700, 700))
    return {
        "asli": image,
        "buram ringan (r=1.5)": image.filter(ImageFilter.GaussianBlur(1.5)),
        "buram sedang (r=2.5)": image.filter(ImageFilter.GaussianBlur(2.5)),
        "buram berat (r=3.5)": image.filter(ImageFilter.GaussianBlur(3.5)),
        "gelap + buram": ImageEnhance.Brightness(image.filter(ImageFilter.GaussianBlur(2))).enhance(0.45),
        "resolusi rendah": small,
    }


def old_ocr(engine: TesseractOCR, image: Image.Image) -> str:
    return pytesseract.image_to_string(
        engine.preprocess(image), lang=engine.lang, config=f"--oem 3 --psm {engine.psm}"
    ).strip()


def summary(parser: RegexReceiptParser, text: str) -> str:
    parsed = parser.parse(text)
    total = f"{parsed.total_amount:,.0f}" if parsed.total_amount else "-"
    return f"barang={len(parsed.items):<2} total={total:<9}"


def main(paths: list[str]) -> None:
    engine = TesseractOCR(settings.TESSERACT_CMD, settings.OCR_LANG, settings.OCR_PSM)
    parser = RegexReceiptParser()
    for path in paths:
        image = Image.open(path).convert("RGB")
        reference = engine.extract(image).text
        print(f"\n=== {Path(path).name}  (acuan: {summary(parser, reference)})")
        for name, img in variants(image).items():
            t0 = time.perf_counter()
            old = old_ocr(engine, img)
            t1 = time.perf_counter()
            new = engine.extract(img)
            t2 = time.perf_counter()
            sim_old = difflib.SequenceMatcher(None, reference, old).ratio()
            sim_new = difflib.SequenceMatcher(None, reference, new.text).ratio()
            print(
                f"{name:<22} lama: mirip={sim_old:5.1%} {summary(parser, old)} {t1 - t0:4.1f}s | "
                f"baru: mirip={sim_new:5.1%} {summary(parser, new.text)} {t2 - t1:4.1f}s "
                f"{'[diperjelas]' if new.enhanced else ''} {','.join(new.quality_notes)}"
            )


if __name__ == "__main__":
    main(sys.argv[1:])
