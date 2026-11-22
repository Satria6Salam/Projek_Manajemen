"""Memperbaiki salah baca OCR pada nama barang sebelum diklasifikasikan.

Foto struk yang buram sering menghasilkan teks seperti:
    "FRESHMI LK 1L"      (kata terpecah)        -> "freshmilk"
    "MIE SEDAAP5OTO"     (S terbaca 5, tergabung) -> "mie sedaap soto"
    "TE1UR AYAM"         (L terbaca 1)          -> "telur ayam"
    "PEPSODNT"           (huruf hilang)         -> "pepsodent"

Perbaikan memakai kosakata yang dikenal (kata kunci + data latih):
1. Angka yang terselip di dalam kata diganti huruf yang mirip (0->o, 1->l/i, 5->s, ...).
   Token ukuran seperti "600ml", "5kg", "2x" dibuang karena tidak membantu kategori.
2. Dua token yang bila digabung menjadi kata dikenal, digabung.
3. Token panjang yang tidak dikenal dipecah bila menjadi dua kata dikenal.
4. Token yang masih tidak dikenal dicocokkan ke kata dikenal terdekat
   (jarak edit 1, atau 2 untuk kata panjang).
"""
from __future__ import annotations

import re
from collections import Counter
from functools import lru_cache

_SIZE = re.compile(
    r"^(\d+([.,]\d+)?(ml|l|lt|ltr|liter|g|gr|grm|gram|kg|mg|mcg|s|pcs|pc|pck|pak|x|cm|mm|m|w|watt|v|mah|rb|k)?"
    r"|x\d+|\d+x\d*|\d+[a-z]{1,2}\d{0,2})$"
)
_CONFUSABLE = {"0": "o", "1": "l", "2": "z", "4": "a", "5": "s", "6": "g", "8": "b", "9": "g", "3": "e", "7": "t"}
_ALT_ONE = "i"  # "1" kadang berasal dari "I"
_LETTER = re.compile(r"[a-z]")


def _edits1(word: str) -> set[str]:
    return {word[:i] + word[i + 1:] for i in range(len(word))}


def _levenshtein(a: str, b: str, limit: int) -> int:
    if abs(len(a) - len(b)) > limit:
        return limit + 1
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        best = i
        for j, cb in enumerate(b, 1):
            cost = 0 if ca == cb else 1
            value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            current.append(value)
            best = min(best, value)
        if best > limit:
            return limit + 1
        previous = current
    return previous[-1]


class OcrTextRepairer:
    # Kata 4 huruf tidak dikoreksi: terlalu banyak kata pendek yang mirip ("aneh" vs "aceh").
    MIN_FUZZY_LEN = 5

    def __init__(
        self,
        vocabulary: Counter[str] | dict[str, int],
        joined_phrases: dict[str, str] | None = None,
        bigrams: set[str] | None = None,
    ):
        self.vocab: dict[str, int] = {w: c for w, c in vocabulary.items() if w and _LETTER.search(w)}
        # "freshmilk" -> "fresh milk": frasa kata kunci yang ditulis tanpa spasi.
        self.joined = dict(joined_phrases or {})
        # Pasangan kata yang dikenal, mis. "gula pasir", untuk memulihkan huruf yang hilang.
        self.bigrams = set(bigrams or ())
        self._deletes: dict[str, list[str]] = {}
        for word in self.vocab:
            if len(word) >= self.MIN_FUZZY_LEN:
                for variant in _edits1(word) | {word}:
                    self._deletes.setdefault(variant, []).append(word)

    # ------------------------------------------------------------------ util
    def known(self, token: str) -> bool:
        return token in self.vocab or token in self.joined

    def coverage(self, text: str) -> float:
        """Porsi kata (>= 3 huruf) pada teks yang dikenal kosakata, 0.0 - 1.0."""
        words = [w for w in text.split() if len(w) >= 3 and w.isalpha()]
        if not words:
            return 0.0
        return sum(1 for w in words if self.known(w)) / len(words)

    def _expand(self, token: str) -> str:
        return self.joined.get(token, token)

    def _fix_digits(self, token: str) -> str | None:
        """None = token ukuran/angka yang dibuang."""
        if not any(ch.isdigit() for ch in token):
            return token
        if _SIZE.match(token) or not _LETTER.search(token):
            return None
        primary = "".join(_CONFUSABLE.get(ch, ch) for ch in token)
        if "1" in token and not self.known(primary):
            alternative = "".join(_ALT_ONE if ch == "1" else _CONFUSABLE.get(ch, ch) for ch in token)
            if self.known(alternative):
                return alternative
        return primary

    @lru_cache(maxsize=20000)
    def nearest(self, token: str) -> str | None:
        if len(token) < self.MIN_FUZZY_LEN:
            return None
        limit = 1 if len(token) < 8 else 2
        candidates: set[str] = set()
        for variant in _edits1(token) | {token}:
            candidates.update(self._deletes.get(variant, ()))
        best: tuple[int, int, str] | None = None
        for word in candidates:
            distance = _levenshtein(token, word, limit)
            if distance <= limit:
                key = (distance, -self.vocab.get(word, 0), word)
                if best is None or key < best:
                    best = key
        return best[2] if best else None

    def _restore_with_neighbor(self, token: str, prev: str | None, nxt: str | None) -> str | None:
        """Kata pendek tak dikenal yang kehilangan satu huruf ("ula" + "pasir" -> "gula").

        Calon = sisipkan satu huruf di posisi mana pun; dipakai hanya bila
        membentuk pasangan kata yang dikenal dengan kata sebelum/sesudahnya.
        """
        if not self.bigrams or len(token) < 2 or not token.isalpha():
            return None
        best: tuple[int, str] | None = None
        for i in range(len(token) + 1):
            for ch in "abcdefghijklmnopqrstuvwxyz":
                cand = token[:i] + ch + token[i:]
                if cand not in self.vocab:
                    continue
                if (nxt and f"{cand} {nxt}" in self.bigrams) or (prev and f"{prev} {cand}" in self.bigrams):
                    score = self.vocab.get(cand, 0)
                    if best is None or score > best[0]:
                        best = (score, cand)
        return best[1] if best else None

    def repair_display(self, name: str) -> str:
        """Perbaiki nama barang untuk DITAMPILKAN, tanpa mengubah huruf besar/kecil dan ukuran.

        Sengaja hati-hati: hanya memulihkan satu huruf yang hilang bila hasilnya membentuk
        pasangan kata yang dikenal ("ula Pasir" -> "Gula Pasir"). Ejaan lain tidak disentuh.
        """
        tokens = name.split(" ")
        lowered = [t.lower() for t in tokens]
        out: list[str] = []
        for i, tok in enumerate(tokens):
            low = lowered[i]
            if not low.isalpha() or len(low) < 2 or self.known(low):
                out.append(tok)
                continue
            prev = lowered[i - 1] if i > 0 and lowered[i - 1].isalpha() else None
            nxt = lowered[i + 1] if i + 1 < len(lowered) and lowered[i + 1].isalpha() else None
            fix = self._restore_with_neighbor(low, prev, nxt)
            if not fix:
                out.append(tok)
            elif tok.isupper():
                out.append(fix.upper())
            elif tok[:1].isupper() or (i + 1 < len(tokens) and tokens[i + 1][:1].isupper()):
                out.append(fix.capitalize())
            else:
                out.append(fix)
        return " ".join(out)

    def _split(self, token: str) -> list[str] | None:
        if len(token) < 7:
            return None
        best: list[str] | None = None
        for cut in range(3, len(token) - 2):
            left, right = token[:cut], token[cut:]
            if self.known(left) and self.known(right):
                if best is None or len(left) > len(best[0]):
                    best = [left, right]
        return best

    # ------------------------------------------------------------------ main
    def repair(self, text: str) -> str:
        tokens: list[str] = []
        for raw in text.split():
            fixed = self._fix_digits(raw)
            if fixed:
                tokens.append(fixed)

        # Gabungkan token yang terpecah: "sa rimi" -> "sarimi".
        merged: list[str] = []
        i = 0
        while i < len(tokens):
            if i + 1 < len(tokens):
                a, b = tokens[i], tokens[i + 1]
                joined = a + b
                if not (self.known(a) and self.known(b)):
                    if self.known(joined):
                        merged.append(joined)
                        i += 2
                        continue
                    near = self.nearest(joined) if len(joined) >= 6 else None
                    if near and (len(a) <= 3 or len(b) <= 3 or not self.known(a)):
                        merged.append(near)
                        i += 2
                        continue
            merged.append(tokens[i])
            i += 1

        result: list[str] = []
        for idx, token in enumerate(merged):
            if self.known(token) and len(token) > 3:
                result.append(self._expand(token))
                continue
            prev = merged[idx - 1] if idx > 0 else None
            nxt = merged[idx + 1] if idx + 1 < len(merged) else None
            restored = self._restore_with_neighbor(token, prev, nxt)
            if restored and not (self.known(token) and (
                    (nxt and f"{token} {nxt}" in self.bigrams) or (prev and f"{prev} {token}" in self.bigrams))):
                result.append(self._expand(restored))
                continue
            if self.known(token):
                result.append(self._expand(token))
                continue
            parts = self._split(token)
            if parts:
                result.extend(self._expand(p) for p in parts)
                continue
            near = self.nearest(token)
            result.append(self._expand(near) if near else token)
        return " ".join(result)
