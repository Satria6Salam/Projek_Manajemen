"""Pengujian perbaikan foto sebelum OCR (tanpa Tesseract)."""
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

from app.integrations.ocr.enhance import enhance, measure


def _receipt() -> Image.Image:
    image = Image.new("RGB", (600, 900), "white")
    draw = ImageDraw.Draw(image)
    for row in range(30):
        draw.text((30, 20 + row * 28), f"BARANG CONTOH {row:02d}      12.500", fill="black")
    return image


def test_sharp_photo_has_no_blur_note():
    assert "foto buram" not in measure(_receipt()).notes


def test_blurred_photo_is_detected():
    blurred = _receipt().filter(ImageFilter.GaussianBlur(3))
    assert measure(blurred).is_blurry


def test_dark_photo_is_detected():
    dark = ImageEnhance.Brightness(_receipt()).enhance(0.3)
    assert measure(dark).is_dark


def test_enhance_upscales_and_sharpens_blurry_photo():
    blurred = _receipt().filter(ImageFilter.GaussianBlur(3))
    result = enhance(blurred)
    assert result.image.mode == "L"
    assert max(result.image.size) >= 2000
    assert any(step.startswith("pertajam") for step in result.steps)
    # Setelah diperjelas, tepi huruf lebih tajam daripada foto buram aslinya.
    assert measure(result.image).sharpness > measure(blurred).sharpness
