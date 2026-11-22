"""Alur pindai struk: validasi gambar -> simpan -> OCR -> parsing -> klasifikasi.

Hasil scan BELUM disimpan ke database. Pengguna memeriksa/mengoreksi
lebih dulu di layar "Koreksi & Validasi", lalu frontend memanggil
POST /receipts dengan `scan_id` dari respons ini.
"""
import io
import logging
from datetime import timedelta

from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.timeutils import utcnow
from app.core.exceptions import BadRequestError, PayloadTooLargeError, ServiceUnavailableError, UnprocessableError
from app.integrations.classifier.chain import ClassifierChain
from app.integrations.ocr.base import OCREngine
from app.integrations.parser.base import ReceiptParser
from app.integrations.storage.base import StorageBackend
from app.models import ScanAsset, User
from app.schemas.scan import ScanItemOut, ScanOut
from app.services import ocr_learning_service, prediction_service
from app.integrations.providers import get_vision_extractor
from app.services.receipt_reader import read_receipt

logger = logging.getLogger("strukku")
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "MPO", "BMP"}
STORED_MAX_SIDE = 2000


def load_image(content: bytes) -> Image.Image:
    if not content:
        raise BadRequestError("File gambar kosong.", code="EMPTY_FILE")
    if len(content) > settings.max_upload_bytes:
        raise PayloadTooLargeError(f"Ukuran gambar maksimal {settings.MAX_UPLOAD_MB} MB.")
    try:
        image = Image.open(io.BytesIO(content))
        image.load()
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError):
        raise BadRequestError("File bukan gambar yang valid. Gunakan JPG, PNG, atau WEBP.", code="INVALID_IMAGE")
    if image.format not in ALLOWED_FORMATS:
        raise BadRequestError("Format gambar harus JPG, PNG, atau WEBP.", code="INVALID_IMAGE")
    image = ImageOps.exif_transpose(image)
    return image.convert("RGB")


def to_jpeg(image: Image.Image) -> bytes:
    """Kecilkan & simpan ulang sebagai JPEG (sekaligus membuang metadata EXIF/GPS)."""
    copy = image.copy()
    copy.thumbnail((STORED_MAX_SIDE, STORED_MAX_SIDE))
    buffer = io.BytesIO()
    copy.save(buffer, format="JPEG", quality=85, optimize=True)
    return buffer.getvalue()


def scan_receipt(
    db: Session,
    user: User,
    content: bytes,
    ocr: OCREngine,
    parser: ReceiptParser,
    classifier: ClassifierChain,
    storage: StorageBackend,
    device_text: str | None = None,
) -> ScanOut:
    """`device_text` = teks hasil Google ML Kit di HP (opsional), ikut dibandingkan."""
    image = load_image(content)

    try:
        reading = read_receipt(image, ocr, parser, device_text=device_text, vision=get_vision_extractor())
        ocr_result, raw_text, parsed = reading.ocr, reading.raw_text, reading.parsed
    except Exception as exc:
        logger.exception("OCR gagal")
        raise ServiceUnavailableError(
            f"OCR gagal dijalankan. Pastikan Tesseract terpasang. Detail: {exc}", code="OCR_FAILED"
        )
    if not raw_text.strip():
        raise UnprocessableError(
            "Teks pada struk tidak terbaca. Coba foto lebih terang, lurus, dan tidak terpotong.",
            code="OCR_EMPTY",
        )

    try:
        scan_id = storage.save(user.id, to_jpeg(image))
    except Exception as exc:
        logger.exception("Gagal menyimpan gambar struk ke storage '%s'", getattr(storage, "name", "?"))
        raise ServiceUnavailableError(
            "Gagal menyimpan gambar struk. Periksa STORAGE_BACKEND / SUPABASE_URL di file .env. "
            f"Detail: {exc.__class__.__name__}",
            code="STORAGE_FAILED",
        )
    # Koreksi yang pernah dibuat pengguna (nama toko / nama barang per toko) diterapkan.
    learned = 0
    try:
        learned = ocr_learning_service.apply_corrections(db, user.id, parsed)
    except Exception:  # pragma: no cover - kamus koreksi tidak boleh menggagalkan scan
        logger.exception("Gagal menerapkan kamus koreksi OCR")
    db.add(ScanAsset(
        owner_id=user.id,
        storage_key=scan_id,
        expires_at=utcnow() + timedelta(hours=settings.SCAN_ASSET_EXPIRE_HOURS),
        ocr_snapshot=ocr_learning_service.snapshot(parsed, raw_text, reading.label, reading.sources),
    ))
    db.commit()
    predictions = prediction_service.classify(db, user.id, [i.name for i in parsed.items], classifier)

    items = [
        ScanItemOut(
            index=index,
            item_name=item.name,
            quantity=item.quantity,
            unit_price=item.unit_price,
            item_price=item.price,
            predicted_category_id=prediction.category_id,
            price_corrected=item.price_corrected,
            name_corrected=item.name_corrected,
            suspicious=item.suspicious,
            uncertain_words=item.uncertain_words,
            **prediction.model_dump(),
        )
        for index, (item, prediction) in enumerate(zip(parsed.items, predictions))
    ]
    items_total = round(sum(i.item_price or 0 for i in items), 2)
    total_matches = None
    if parsed.total_amount is not None and items:
        targets = [parsed.total_amount, parsed.total_amount + parsed.discount_amount]
        if parsed.subtotal_amount is not None:
            targets.append(parsed.subtotal_amount)
        total_matches = any(abs(t - items_total) < 1 for t in targets)

    warnings: list[str] = []
    if ocr_result.quality_notes:
        notes = ", ".join(ocr_result.quality_notes)
        if ocr_result.enhanced:
            warnings.append(f"Kualitas foto kurang baik ({notes}); foto sudah diperjelas otomatis. Periksa hasilnya.")
        else:
            warnings.append(f"Kualitas foto kurang baik ({notes}). Periksa hasilnya atau foto ulang.")
    if parsed.corrections:
        warnings.append(
            "Beberapa angka dikoreksi otomatis karena kemungkinan salah baca OCR "
            f"({'; '.join(parsed.corrections[:3])}). Periksa kembali."
        )
    if learned:
        warnings.append(f"{learned} nama diisi dari koreksi Anda sebelumnya.")
    if not items:
        warnings.append("Tidak ada barang terdeteksi. Tambahkan barang secara manual atau foto ulang struk.")
    if parsed.total_amount is None:
        warnings.append("Total belanja tidak terbaca; periksa kolom total.")
    elif total_matches is False:
        warnings.append(
            f"Total struk ({parsed.total_amount:,.0f}) berbeda dengan jumlah harga barang ({items_total:,.0f}). "
            "Mungkin ada diskon/pajak atau barang yang tidak terbaca."
        )
    if parsed.transaction_date is None:
        warnings.append("Tanggal transaksi tidak terbaca; tanggal hari ini akan dipakai bila dikosongkan.")
    review_count = sum(1 for i in items if i.needs_review)

    return ScanOut(
        scan_id=scan_id,
        image_url=f"{settings.API_PREFIX}/scans/{scan_id}/image",
        merchant_name=parsed.merchant_name,
        merchant_address=parsed.merchant_address,
        transaction_date=parsed.transaction_date,
        total_amount=parsed.total_amount,
        items_total=items_total,
        total_matches=total_matches,
        review_count=review_count,
        items=items,
        warnings=warnings,
        raw_text=raw_text,
        consistent=reading.consistent,
        field_confidence=reading.confidence,
        review_fields=reading.review_fields,
        ocr_source=reading.label or "tesseract",
    )
