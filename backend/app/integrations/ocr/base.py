from abc import ABC, abstractmethod
from dataclasses import dataclass, field

from PIL import Image


@dataclass
class OcrResult:
    text: str
    # Catatan mutu foto untuk pengguna, mis. ["foto buram"].
    quality_notes: list[str] = field(default_factory=list)
    # True bila teks berasal dari foto yang sudah diperjelas otomatis.
    enhanced: bool = False
    # Semua bacaan alternatif (praproses/mode berbeda). Layanan scan memilih yang
    # hasil parsing-nya paling masuk akal; `text` adalah pilihan terbaik versi OCR.
    candidates: list["OcrCandidate"] = field(default_factory=list)


@dataclass
class OcrCandidate:
    text: str
    ocr_score: float
    enhanced: bool
    label: str = ""


class OCREngine(ABC):
    """Kontrak mesin OCR.

    Untuk mengganti Tesseract dengan layanan lain (mis. Google Vision),
    buat kelas turunan ini lalu daftarkan di `app/integrations/providers.py`.
    """

    name: str = "base"

    @abstractmethod
    def extract_text(self, image: Image.Image) -> str:
        """Kembalikan teks mentah dari gambar struk."""

    def extract(self, image: Image.Image) -> OcrResult:
        """Seperti extract_text, ditambah catatan mutu foto. Boleh di-override."""
        return OcrResult(self.extract_text(image))

    def status(self) -> dict:
        return {"engine": self.name, "ready": True, "message": "OK"}
