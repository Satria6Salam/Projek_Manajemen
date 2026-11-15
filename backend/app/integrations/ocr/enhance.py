"""Perbaikan foto struk sebelum OCR: buram, gelap, pudar, atau berbayang.

Langkah (diadaptasi dari ImageEnhancer smart_receipt_v2, ditambah penajaman):
1. Grayscale + perbesar: huruf struk yang kecil/buram lebih mudah dibaca
   bila tinggi hurufnya cukup (sisi terpanjang minimal ~2000 px).
2. Ratakan cahaya: piksel dibagi kecerahan latar di sekitarnya sehingga
   bayangan tangan dan sudut gelap hilang.
3. Pertajam (unsharp mask): kekuatan disesuaikan dengan tingkat buram.
4. Tarik kontras: kertas menjadi putih, tinta (termasuk yang pudar) menjadi gelap.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageFilter, ImageOps

TARGET_LONG_SIDE = 2000
MAX_LONG_SIDE = 3000


@dataclass
class ImageQuality:
    brightness: float  # 0-255
    contrast: float  # simpangan baku kecerahan
    sharpness: float  # varians Laplacian pada ukuran baku
    unevenness: float  # rasio latar terang/gelap

    DARK_BELOW = 100
    FADED_BELOW = 30
    BLURRY_BELOW = 120
    UNEVEN_ABOVE = 1.6

    @property
    def is_dark(self) -> bool:
        return self.brightness < self.DARK_BELOW

    @property
    def is_faded(self) -> bool:
        return self.contrast < self.FADED_BELOW

    @property
    def is_blurry(self) -> bool:
        return self.sharpness < self.BLURRY_BELOW

    @property
    def has_shadow(self) -> bool:
        return self.unevenness > self.UNEVEN_ABOVE

    @property
    def has_issue(self) -> bool:
        return self.is_dark or self.is_faded or self.is_blurry or self.has_shadow

    @property
    def notes(self) -> list[str]:
        out: list[str] = []
        if self.is_blurry:
            out.append("foto buram")
        if self.is_faded:
            out.append("tulisan pudar")
        if self.is_dark:
            out.append("foto gelap")
        if self.has_shadow and not self.is_dark:
            out.append("ada bayangan")
        return out


@dataclass
class EnhancedImage:
    image: Image.Image
    quality: ImageQuality
    steps: list[str] = field(default_factory=list)


def _laplacian_variance(gray: np.ndarray) -> float:
    g = gray.astype(np.float32)
    lap = -4 * g[1:-1, 1:-1] + g[:-2, 1:-1] + g[2:, 1:-1] + g[1:-1, :-2] + g[1:-1, 2:]
    return float(lap.var())


def measure(image: Image.Image) -> ImageQuality:
    gray = ImageOps.grayscale(ImageOps.exif_transpose(image))
    # Ukuran baku agar nilai ketajaman sebanding antar resolusi foto.
    small = gray.copy()
    small.thumbnail((1000, 1000), Image.LANCZOS)
    arr = np.asarray(small, dtype=np.float32)
    background = np.asarray(small.filter(ImageFilter.GaussianBlur(radius=max(small.size) / 25)), dtype=np.float32)
    low, high = np.percentile(background, [5, 95])
    return ImageQuality(
        brightness=float(arr.mean()),
        contrast=float(arr.std()),
        sharpness=_laplacian_variance(arr),
        unevenness=float(high / max(low, 1.0)),
    )


def _resize_for_ocr(gray: Image.Image) -> Image.Image:
    longest = max(gray.size)
    if longest < TARGET_LONG_SIDE:
        scale = TARGET_LONG_SIDE / longest
    elif longest > MAX_LONG_SIDE:
        scale = MAX_LONG_SIDE / longest
    else:
        return gray
    return gray.resize((round(gray.width * scale), round(gray.height * scale)), Image.LANCZOS)


def _flatten_light(gray: Image.Image) -> Image.Image:
    """Bagi setiap piksel dengan latar (blur besar) -> cahaya merata."""
    # Latar dihitung di resolusi kecil agar cepat, lalu diperbesar lagi.
    small = gray.copy()
    small.thumbnail((600, 600), Image.BILINEAR)
    radius = max(small.size) / 20
    # Closing (max lalu min) menghapus huruf sehingga yang tersisa hanya kertas.
    bg_small = small.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(radius=radius))
    background = np.asarray(bg_small.resize(gray.size, Image.BILINEAR), dtype=np.float32)
    arr = np.asarray(gray, dtype=np.float32)
    flat = arr / np.maximum(background, 1.0) * 235.0
    return Image.fromarray(np.clip(flat, 0, 255).astype(np.uint8))


def _stretch(gray: Image.Image) -> Image.Image:
    arr = np.asarray(gray, dtype=np.float32)
    ink, paper = np.percentile(arr, [1.0, 60.0])
    if paper - ink < 10:
        return gray
    out = (arr - ink) / (paper - ink) * 255.0
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def enhance(image: Image.Image, quality: ImageQuality | None = None, strong: bool = False) -> EnhancedImage:
    image = ImageOps.exif_transpose(image)
    quality = quality or measure(image)
    gray = _resize_for_ocr(ImageOps.grayscale(image))
    steps = ["grayscale", f"resize {gray.width}x{gray.height}"]

    gray = gray.filter(ImageFilter.MedianFilter(3))  # redam bintik/noise JPEG
    gray = _flatten_light(gray)
    steps.append("ratakan cahaya")

    if quality.is_blurry or strong:
        # Makin buram, makin kuat penajamannya.
        blur_level = max(0.0, min(1.0, 1 - quality.sharpness / ImageQuality.BLURRY_BELOW))
        percent = int(160 + 180 * blur_level + (80 if strong else 0))
        gray = gray.filter(ImageFilter.UnsharpMask(radius=3, percent=percent, threshold=2))
        gray = gray.filter(ImageFilter.UnsharpMask(radius=1, percent=100, threshold=1))
        steps.append(f"pertajam {percent}%")
    else:
        gray = gray.filter(ImageFilter.UnsharpMask(radius=2, percent=120, threshold=3))
        steps.append("pertajam ringan")

    gray = _stretch(gray)
    steps.append("tarik kontras")
    return EnhancedImage(gray, quality, steps)
