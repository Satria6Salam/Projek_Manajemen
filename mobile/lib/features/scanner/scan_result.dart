import '../../core/utils/receipt_parser.dart';
import '../../data/repositories/receipt_repository.dart';

/// Data yang dikirim dari halaman Pindai ke halaman Koreksi & Validasi.
class ScanResult {
  const ScanResult({
    required this.imagePath,
    required this.rawText,
    required this.parsed,
    required this.classification,
    this.isDemoSample = false,
    this.isManual = false,
    this.qualityNotes = const <String>[],
    this.enhanced = false,
    this.scanId,
    this.warnings = const <String>[],
  });

  /// scan_id dari server (null bila dibaca di HP / mode demo).
  final String? scanId;

  /// Peringatan dari server, mis. mutu foto atau total tidak cocok.
  final List<String> warnings;

  /// true jika struk dipindai oleh server (OCR Tesseract + parser lengkap).
  bool get scannedByServer => scanId != null;

  /// Catatan mutu foto, mis. ["foto buram", "tulisan pudar"].
  final List<String> qualityNotes;

  /// true jika teks dibaca dari foto yang sudah diperjelas otomatis.
  final bool enhanced;

  /// Lokasi foto struk (null jika diisi manual tanpa gambar).
  final String? imagePath;

  /// Teks mentah hasil OCR.
  final String rawText;

  /// Hasil parsing regex (merchant, tanggal, total, item).
  final ParsedReceipt parsed;

  /// Hasil klasifikasi kategori; null jika klasifikasi gagal/dilewati.
  final ClassificationResult? classification;

  /// true jika dicatat manual tanpa foto struk (parkir, ojek, warung).
  final bool isManual;

  /// true jika memakai contoh struk demo (bukan hasil OCR gambar).
  final bool isDemoSample;
}
