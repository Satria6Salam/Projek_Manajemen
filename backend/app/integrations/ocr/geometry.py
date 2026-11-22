"""Perbaikan geometri foto struk sebelum OCR.

1. find_receipt: struk yang difoto di atas meja dipotong dari latarnya dan
   perspektifnya diluruskan (kamera condong -> struk menjadi persegi panjang).
2. deskew: struk yang miring diputar sampai baris tulisannya mendatar.

Tesseract membaca per kolom bila baris miring atau ada latar di sekitar struk,
sehingga nama barang dan harganya terpisah. Kedua langkah ini mencegah hal itu.
"""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageFilter, ImageOps
from scipy import ndimage

_DETECT_SIDE = 700


def _otsu(arr: np.ndarray) -> float:
    hist, edges = np.histogram(arr, bins=64, range=(0, 255))
    centers = (edges[:-1] + edges[1:]) / 2
    weight = hist.cumsum()
    total = weight[-1]
    mean = (hist * centers).cumsum()
    w0, w1 = weight[:-1], total - weight[:-1]
    valid = (w0 > 0) & (w1 > 0)
    m0 = np.where(valid, mean[:-1] / np.maximum(w0, 1), 0)
    m1 = np.where(valid, (mean[-1] - mean[:-1]) / np.maximum(w1, 1), 0)
    between = np.where(valid, w0 * w1 * (m0 - m1) ** 2, 0)
    return float(centers[int(between.argmax())])


def _perspective_coeffs(dst: list[tuple[float, float]], src: list[tuple[float, float]]) -> list[float]:
    """Koefisien Image.PERSPECTIVE yang memetakan titik keluaran (dst) ke titik masukan (src)."""
    rows = []
    for (x, y), (u, v) in zip(dst, src):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(rows, dtype=np.float64)
    b = np.array([c for p in src for c in p], dtype=np.float64)
    return np.linalg.solve(a, b).tolist()


def find_receipt(image: Image.Image) -> Image.Image | None:
    """Potong & luruskan struk bila tampak sebagai kertas terang di atas latar lebih gelap.

    Mengembalikan None bila struk sudah memenuhi foto atau batasnya tidak jelas.
    """
    gray = ImageOps.grayscale(image)
    small = gray.copy()
    small.thumbnail((_DETECT_SIDE, _DETECT_SIDE), Image.BILINEAR)
    sx, sy = gray.width / small.width, gray.height / small.height
    # Haluskan agar tulisan di kertas tidak memecah area kertas.
    arr = np.asarray(small.filter(ImageFilter.GaussianBlur(3)), dtype=np.float32)
    threshold = _otsu(arr)
    paper = arr > threshold
    if not paper.any() or paper.all() or arr[paper].mean() - arr[~paper].mean() < 35:
        return None  # kertas dan latar tidak cukup berbeda
    paper = ndimage.binary_closing(paper, structure=np.ones((9, 9)))
    paper = ndimage.binary_fill_holes(paper)
    labels, count = ndimage.label(paper)
    if count == 0:
        return None
    sizes = ndimage.sum(paper, labels, range(1, count + 1))
    biggest = int(np.argmax(sizes)) + 1
    mask = labels == biggest
    area = mask.mean()
    if not 0.15 <= area <= 0.9:
        return None
    # Bayangan di atas kertas juga tampak "gelap". Latar sungguhan (meja) hampir tanpa
    # tulisan, sedangkan bagian kertas yang berbayang tetap penuh huruf.
    raw = np.asarray(small, dtype=np.float32)
    edges = np.abs(raw - ndimage.uniform_filter(raw, 5)) > 12
    inner_bg = ndimage.binary_erosion(~mask, iterations=6)
    inner_paper = ndimage.binary_erosion(mask, iterations=6)
    if inner_bg.any() and inner_paper.any():
        if edges[inner_bg].mean() > 0.45 * max(edges[inner_paper].mean(), 1e-3):
            return None
    ys, xs = np.nonzero(mask)
    # Struk yang menyentuh tiga sisi foto atau lebih = sudah dipotong pengguna.
    h, w = mask.shape
    touching = sum([xs.min() <= 1, ys.min() <= 1, xs.max() >= w - 2, ys.max() >= h - 2])
    if touching >= 3:
        return None
    s, d = xs + ys, xs - ys
    corners = [
        (xs[s.argmin()], ys[s.argmin()]),  # kiri atas
        (xs[d.argmax()], ys[d.argmax()]),  # kanan atas
        (xs[s.argmax()], ys[s.argmax()]),  # kanan bawah
        (xs[d.argmin()], ys[d.argmin()]),  # kiri bawah
    ]
    src = [(x * sx, y * sy) for x, y in corners]
    tl, tr, br, bl = (np.array(p) for p in src)
    out_w = int(max(np.linalg.norm(tr - tl), np.linalg.norm(br - bl)))
    out_h = int(max(np.linalg.norm(bl - tl), np.linalg.norm(br - tr)))
    if out_w < 200 or out_h < 200:
        return None
    # Potong sedikit ke dalam agar tepi latar tidak ikut terbaca.
    pad = 0.006
    inner = [
        tuple(tl + (tr - tl) * pad + (bl - tl) * pad), tuple(tr + (tl - tr) * pad + (br - tr) * pad),
        tuple(br + (bl - br) * pad + (tr - br) * pad), tuple(bl + (br - bl) * pad + (tl - bl) * pad),
    ]
    dst = [(0, 0), (out_w, 0), (out_w, out_h), (0, out_h)]
    coeffs = _perspective_coeffs(dst, inner)
    return image.transform((out_w, out_h), Image.PERSPECTIVE, coeffs, Image.BICUBIC)


def skew_angle(image: Image.Image, max_angle: float = 15.0) -> float:
    """Perkirakan kemiringan baris tulisan (derajat) dengan profil proyeksi."""
    gray = ImageOps.grayscale(image)
    small = gray.copy()
    small.thumbnail((600, 600), Image.BILINEAR)
    arr = np.asarray(small, dtype=np.float32)
    # Ambang lokal: tinta = jauh lebih gelap dari kertas di sekitarnya (tahan bayangan/cahaya miring).
    local = ndimage.uniform_filter(arr, 25)
    ink = ((arr < local * 0.8) & (local - arr > 15)).astype(np.uint8) * 255
    if ink.mean() < 1:
        return 0.0
    mask = Image.fromarray(ink)

    def sharpness(angle: float) -> float:
        rotated = np.asarray(mask.rotate(angle, resample=Image.NEAREST, expand=False), dtype=np.float32)
        profile = rotated.sum(axis=1)
        return float(np.var(np.diff(profile)))

    coarse = np.arange(-max_angle, max_angle + 0.01, 1.0)
    best = max(coarse, key=sharpness)
    fine = np.arange(best - 1.0, best + 1.01, 0.2)
    return float(max(fine, key=sharpness))


def deskew(image: Image.Image) -> tuple[Image.Image, float]:
    angle = skew_angle(image)
    if abs(angle) < 0.4:
        return image, 0.0
    fill = 255 if image.mode == "L" else (255, 255, 255)
    return image.rotate(angle, resample=Image.BICUBIC, expand=True, fillcolor=fill), angle


def straighten(image: Image.Image) -> tuple[Image.Image, list[str]]:
    """Potong latar + luruskan perspektif + putar baris miring. Mengembalikan langkah yang dilakukan."""
    steps: list[str] = []
    cropped = find_receipt(image)
    if cropped is not None:
        image = cropped
        steps.append("potong & luruskan struk")
    image, angle = deskew(image)
    if angle:
        steps.append(f"putar {angle:+.1f}°")
    return image, steps
