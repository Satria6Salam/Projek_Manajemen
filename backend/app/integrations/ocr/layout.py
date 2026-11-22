"""Menyusun baris struk dari kotak-kotak teks hasil OCR, memakai POSISI, bukan urutan bacaan.

Masalah yang ditangani:
1. Foto miring: harga di kolom kanan bergeser naik/turun sehingga terpisah dari nama barangnya.
   Kemiringan diperkirakan dari baris yang berisi beberapa kotak, lalu posisi vertikal tiap kotak
   dikoreksi sebelum dikelompokkan per baris.
2. Harga "yatim": baris yang hanya berisi angka di kolom kanan, tepat di bawah baris nama tanpa
   harga (umum pada struk yang tercetak sedikit bergeser), digabung ke baris nama tersebut.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

_PRICE = re.compile(r"^(rp\.?)?[-(]?\d{1,3}([.,]\d{3})+([.,]\d{2})?\)?-?$|^(rp\.?)?\d{4,7}$", re.I)


@dataclass(frozen=True)
class Box:
    cy: float  # pusat vertikal
    x0: float  # tepi kiri
    x1: float  # tepi kanan
    h: float   # tinggi
    text: str


def _group(boxes: list[Box], ys: list[float], tolerance: float) -> list[list[Box]]:
    order = sorted(range(len(boxes)), key=lambda i: ys[i])
    lines: list[list[int]] = []
    centers: list[float] = []
    for i in order:
        if lines and abs(ys[i] - centers[-1]) <= tolerance:
            lines[-1].append(i)
            centers[-1] = sum(ys[j] for j in lines[-1]) / len(lines[-1])
        else:
            lines.append([i])
            centers.append(ys[i])
    return [sorted((boxes[i] for i in line), key=lambda b: b.x0) for line in lines]


def _slope(lines: list[list[Box]]) -> float:
    slopes = []
    for line in lines:
        if len(line) < 2:
            continue
        a, b = line[0], line[-1]
        dx = (b.x0 + b.x1) / 2 - (a.x0 + a.x1) / 2
        if dx > 3 * a.h:
            slopes.append((b.cy - a.cy) / dx)
    if len(slopes) < 3:
        return 0.0
    slopes.sort()
    return slopes[len(slopes) // 2]


def _is_price(text: str) -> bool:
    return bool(_PRICE.match(text.replace(" ", "")))


def layout_lines(boxes: list[Box], tolerance_ratio: float = 0.5) -> str:
    if not boxes:
        return ""
    heights = sorted(b.h for b in boxes)
    median_h = max(heights[len(heights) // 2], 1.0)
    tolerance = tolerance_ratio * median_h

    ys = [b.cy for b in boxes]
    lines = _group(boxes, ys, tolerance)
    slope = _slope(lines)
    if abs(slope) > 0.004:
        ys = [b.cy - slope * (b.x0 + b.x1) / 2 for b in boxes]
        lines = _group(boxes, ys, tolerance)

    left = min(b.x0 for b in boxes)
    right = max(b.x1 for b in boxes)
    middle = left + 0.5 * (right - left)
    merged: list[list[Box]] = []
    for line in lines:
        if merged and all(_is_price(b.text) for b in line) and line[0].x0 > middle:
            prev = merged[-1]
            gap = min(b.cy for b in line) - max(b.cy for b in prev)
            if not _is_price(prev[-1].text) and prev[-1].x1 < line[0].x0 and gap < 1.6 * median_h:
                merged[-1] = prev + line
                continue
        merged.append(line)
    return "\n".join(" ".join(b.text for b in line) for line in merged)
