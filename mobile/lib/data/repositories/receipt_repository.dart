import '../../core/utils/receipt_parser.dart';
import '../../models/dashboard_model.dart';
import '../../models/model_report.dart';
import '../../models/price_history.dart';
import '../../models/receipt_model.dart';

/// Prediksi kategori untuk satu nama barang.
class ItemPrediction {
  const ItemPrediction({
    required this.itemName,
    required this.categoryName,
    required this.confidence,
    this.categoryId,
    this.source,
  });

  final String itemName;
  final String categoryName;

  /// Probabilitas 0..1 (confidence_score).
  final double confidence;

  /// id kategori hasil prediksi server (null pada mode demo).
  final int? categoryId;

  /// Sumber prediksi server, mis. keyword_rules / id_model.
  final String? source;
}

/// Satu toko (cabang) beserta alamat dari struk.
class StoreSummary {
  const StoreSummary({
    required this.name,
    this.address,
    required this.visits,
    required this.totalSpent,
    this.lastVisit,
  });

  final String name;
  final String? address;
  final int visits;
  final double totalSpent;
  final DateTime? lastVisit;

  /// Gabungkan struk per toko + alamat (dipakai mode demo).
  static List<StoreSummary> fromReceipts(List<ReceiptModel> receipts) {
    String key(String? s) =>
        (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final groups = <String, List<ReceiptModel>>{};
    for (final r in receipts) {
      groups
          .putIfAbsent(
              '${key(r.merchantName)}|${key(r.merchantAddress)}', () => [])
          .add(r);
    }
    final out = [
      for (final g in groups.values)
        StoreSummary(
          name: g.first.merchantName,
          address: g.first.merchantAddress,
          visits: g.length,
          totalSpent: g.fold<double>(0, (s, r) => s + r.totalAmount),
          lastVisit: g
              .map((r) => r.transactionDate)
              .reduce((a, b) => a.isAfter(b) ? a : b),
        ),
    ]..sort((a, b) => b.visits.compareTo(a.visits));
    return out;
  }
}

/// Data satu periode (hari / bulan / tahun) untuk analisis dan anggaran.
class PeriodData {
  const PeriodData({required this.receipts, required this.categoryTotals});

  /// Struk dalam periode (tanpa detail barang), terbaru lebih dulu.
  final List<ReceiptModel> receipts;
  final List<CategoryTotal> categoryTotals;

  double get total => receipts.fold<double>(0, (s, r) => s + r.totalAmount);
}

/// Hasil pindai struk di server (POST /scans): OCR Tesseract bertingkat,
/// parser lengkap (qty & harga satuan), dan kategori per barang.
class ServerScan {
  const ServerScan({
    required this.scanId,
    required this.rawText,
    required this.parsed,
    required this.classification,
    this.warnings = const [],
  });

  /// Kirim kembali saat menyimpan agar foto ikut tersimpan di server.
  final String scanId;
  final String rawText;
  final ParsedReceipt parsed;
  final ClassificationResult classification;

  /// Peringatan dari server (mutu foto, total tidak cocok, dll.).
  final List<String> warnings;
}

/// Hasil klasifikasi seluruh barang pada satu struk.
class ClassificationResult {
  const ClassificationResult(
      {required this.predictions, required this.isSimulated});

  /// Urutan sama dengan daftar nama barang yang dikirim.
  final List<ItemPrediction> predictions;

  /// true jika hasil berasal dari simulasi (mode demo), bukan model ML asli.
  final bool isSimulated;
}

/// Kontrak data struk. Implementasi: MockReceiptRepository (lokal/demo)
/// dan FastApiReceiptRepository (backend Python, nonaktif secara default).
abstract class ReceiptRepository {
  /// Mengklasifikasikan nama-nama barang menjadi kategori + confidence.
  Future<ClassificationResult> classifyItems(List<String> itemNames);

  /// Pindai foto struk di server. Mengembalikan null bila mode ini tidak
  /// mendukung pindai server (mode demo) sehingga OCR di HP yang dipakai.
  Future<ServerScan?> scanReceipt(String imagePath);

  /// Menyimpan struk beserta item (termasuk koreksi kategori pengguna).
  ///
  /// Melempar AppException dengan code `POSSIBLE_DUPLICATE` bila struk serupa
  /// (tanggal & total sama, toko sama) sudah ada, kecuali [allowDuplicate].
  Future<ReceiptModel> saveReceipt(ReceiptModel receipt,
      {bool allowDuplicate = false});

  /// Riwayat struk, terbaru lebih dulu. [month] opsional untuk filter bulan.
  Future<List<ReceiptModel>> getReceipts(int userId, {DateTime? month});

  /// Seperti [getReceipts] tetapi tanpa detail barang (lebih ringan).
  /// Dipakai untuk analisis & rekomendasi yang hanya butuh tanggal, toko, dan total.
  Future<List<ReceiptModel>> getReceiptSummaries(int userId,
      {required DateTime month});

  /// Struk (tanpa detail barang) dan total per kategori untuk rentang
  /// [start, endExclusive). Dipakai halaman Analisis dan Anggaran.
  Future<PeriodData> getPeriodData(
      int userId, DateTime start, DateTime endExclusive);

  /// 12 nilai total pengeluaran per bulan pada [year] (indeks 0 = Januari).
  Future<List<double>> getMonthlyTotals(int userId, int year);

  /// Total pengeluaran per tahun (tahun -> total) untuk semua tahun berdata.
  Future<Map<int, double>> getYearlyTotals(int userId);

  /// Kinerja prediksi kategori. null = tidak tersedia (mode demo).
  Future<ModelReport?> getModelReport();

  /// Riwayat harga barang yang namanya memuat semua kata di [query].
  Future<PriceHistory> getPriceHistory(int userId, String query);

  /// Toko tempat pengguna berbelanja (alamat dari struk), paling sering lebih dulu.
  Future<List<StoreSummary>> getStores(int userId);

  /// Ringkasan pengeluaran satu bulan (Beranda & Kategori).
  Future<DashboardModel> getDashboard(int userId, DateTime month);

  /// Bulan terbaru yang memiliki data (awal bulan), atau null jika belum ada.
  Future<DateTime?> latestMonthWithData(int userId);

  /// Daftar bulan yang memiliki data, terbaru lebih dulu.
  Future<List<DateTime>> availableMonths(int userId);

  Future<int> countReceipts(int userId);

  Future<void> deleteReceipt(int userId, int receiptId);
}
