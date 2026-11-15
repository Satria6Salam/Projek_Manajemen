import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_categories.dart';
import '../../core/errors/app_exception.dart';
import '../../models/dashboard_model.dart';
import '../../models/model_report.dart';
import '../../models/price_history.dart';
import '../../models/receipt_item_model.dart';
import '../../models/receipt_model.dart';
import '../local/app_database.dart';
import 'receipt_repository.dart';

/// Repository MODE LOKAL/DEMO.
///
/// - Penyimpanan: SQLite lokal (data benar-benar tersimpan di perangkat).
/// - Klasifikasi: SIMULASI berbasis kata kunci (bukan model TF-IDF/Naive Bayes).
///   Model ML asli ada di backend Python. Hasil simulasi selalu ditandai
///   "simulasi" di UI.
class MockReceiptRepository implements ReceiptRepository {
  // --------------------------------------------------------------------------
  // Klasifikasi simulasi
  // --------------------------------------------------------------------------

  /// Aturan demo: kata kunci -> kategori + confidence tetap.
  /// "vitamin" sengaja diberi 0.62 agar peringatan kuning (seperti di Figma)
  /// dapat dicoba. Barang yang tidak cocok -> "Lainnya" dengan confidence rendah.
  static const List<_Rule> _rules = [
    _Rule(['vitamin'], AppCategories.kesehatan, 0.62),
    _Rule([
      'paracetamol',
      'obat',
      'masker',
      'betadine',
      'plester',
      'sanitizer',
      'antiseptik'
    ], AppCategories.kesehatan, 0.90),
    _Rule([
      'pertalite',
      'pertamax',
      'solar',
      'bensin',
      'bbm',
      'parkir',
      'tol',
      'grab',
      'gojek',
      'ojek',
      'taksi',
      'tiket kereta'
    ], AppCategories.transportasi, 0.93),
    _Rule([
      'kaos',
      'baju',
      'celana',
      'sepatu',
      'sabun',
      'shampoo',
      'deterjen',
      'tisu',
      'lampu'
    ], AppCategories.belanja, 0.88),
    _Rule(['pulsa', 'donasi', 'admin', 'pajak', 'iuran'], AppCategories.lainnya,
        0.80),
    _Rule([
      'roti',
      'susu',
      'kopi',
      'teh',
      'nasi',
      'ayam',
      'mie',
      'mineral',
      'telur',
      'beras',
      'gula',
      'minyak',
      'snack',
      'coklat',
      'keju',
      'yogurt',
      'bakso',
      'es',
      'burger',
      'pizza',
      'daging',
      'bawang',
      'air'
    ], AppCategories.fnb, 0.92),
  ];

  static const double _unknownConfidence = 0.40;

  @override
  Future<ClassificationResult> classifyItems(List<String> itemNames) async {
    // Simulasi waktu proses server.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final predictions = itemNames.map((name) {
      final lower = name.toLowerCase();
      final tokens = lower.split(RegExp(r'[^a-z0-9]+'));
      for (final rule in _rules) {
        final hit = rule.keywords.any(
            (k) => k.contains(' ') ? lower.contains(k) : tokens.contains(k));
        if (hit) {
          return ItemPrediction(
              itemName: name,
              categoryName: rule.category,
              confidence: rule.confidence);
        }
      }
      return ItemPrediction(
          itemName: name,
          categoryName: AppCategories.lainnya,
          confidence: _unknownConfidence);
    }).toList();

    return ClassificationResult(predictions: predictions, isSimulated: true);
  }

  // --------------------------------------------------------------------------
  // Penyimpanan & query (SQLite)
  // --------------------------------------------------------------------------

  @override
  Future<ReceiptModel> saveReceipt(ReceiptModel receipt,
      {bool allowDuplicate = false}) async {
    final db = await AppDatabase.instance;
    if (!allowDuplicate) {
      final d = receipt.transactionDate;
      final rows = await db.rawQuery(
          'SELECT merchant_name, total_amount FROM receipts WHERE user_id = ? '
          'AND transaction_date >= ? AND transaction_date < ? '
          'AND ABS(total_amount - ?) <= 1',
          [
            receipt.userId,
            DateTime(d.year, d.month, d.day).toIso8601String(),
            DateTime(d.year, d.month, d.day + 1).toIso8601String(),
            receipt.totalAmount,
          ]);
      String norm(Object? s) =>
          '${s ?? ''}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final key = norm(receipt.merchantName);
      for (final r in rows) {
        final other = norm(r['merchant_name']);
        if (key.isEmpty || other.isEmpty || key == other) {
          throw AppException(
            'Struk serupa sudah tersimpan: ${r['merchant_name']}, '
            '${d.day}/${d.month}/${d.year}, total Rp${(r['total_amount'] as num).round()}.',
            code: 'POSSIBLE_DUPLICATE',
          );
        }
      }
    }
    return db.transaction<ReceiptModel>((txn) async {
      final receiptId = await txn.insert('receipts', {
        'user_id': receipt.userId,
        'merchant_name': receipt.merchantName,
        'merchant_address': receipt.merchantAddress,
        'transaction_date': receipt.transactionDate.toIso8601String(),
        'total_amount': receipt.totalAmount,
        'image_url': receipt.imageUrl,
        'created_at': receipt.createdAt.toIso8601String(),
      });
      for (final item in receipt.items) {
        await txn.insert('receipt_items', item.toDbMap(receiptId));
      }
      return receipt.copyWith(id: receiptId);
    });
  }

  static List<Object?> _monthArgs(int userId, DateTime month) => [
        userId,
        DateTime(month.year, month.month).toIso8601String(),
        DateTime(month.year, month.month + 1).toIso8601String(),
      ];

  static const String _monthWhere =
      'r.user_id = ? AND r.transaction_date >= ? AND r.transaction_date < ?';

  @override
  Future<PeriodData> getPeriodData(
      int userId, DateTime start, DateTime endExclusive) async {
    final db = await AppDatabase.instance;
    final args = <Object?>[
      userId,
      start.toIso8601String(),
      endExclusive.toIso8601String(),
    ];
    final receiptRows = await db.rawQuery(
        'SELECT r.* FROM receipts r WHERE $_monthWhere '
        'ORDER BY r.transaction_date DESC, r.id DESC',
        args);
    final categoryRows = await db.rawQuery(
        'SELECT c.name AS category_name, SUM(i.item_price) AS total '
        'FROM receipt_items i '
        'JOIN receipts r ON r.id = i.receipt_id '
        'JOIN categories c ON c.id = i.category_id '
        'WHERE $_monthWhere GROUP BY c.id, c.name ORDER BY total DESC',
        args);
    return PeriodData(
      receipts: receiptRows.map(ReceiptModel.fromJson).toList(),
      categoryTotals: categoryRows.map(CategoryTotal.fromJson).toList(),
    );
  }

  @override
  Future<List<double>> getMonthlyTotals(int userId, int year) async {
    final db = await AppDatabase.instance;
    final rows = await db.rawQuery(
        'SELECT CAST(substr(transaction_date, 6, 2) AS INTEGER) AS m, '
        'SUM(total_amount) AS total FROM receipts '
        'WHERE user_id = ? AND substr(transaction_date, 1, 4) = ? GROUP BY m',
        [userId, '$year']);
    final totals = List<double>.filled(12, 0);
    for (final r in rows) {
      final m = (r['m'] as num?)?.toInt();
      if (m != null && m >= 1 && m <= 12) {
        totals[m - 1] = (r['total'] as num?)?.toDouble() ?? 0;
      }
    }
    return totals;
  }

  @override
  Future<Map<int, double>> getYearlyTotals(int userId) async {
    final db = await AppDatabase.instance;
    final rows = await db.rawQuery(
        'SELECT CAST(substr(transaction_date, 1, 4) AS INTEGER) AS y, '
        'SUM(total_amount) AS total FROM receipts WHERE user_id = ? GROUP BY y',
        [userId]);
    return {
      for (final r in rows)
        if (r['y'] != null)
          (r['y'] as num).toInt(): (r['total'] as num?)?.toDouble() ?? 0,
    };
  }

  @override
  Future<ServerScan?> scanReceipt(String imagePath) async => null;

  @override
  Future<ModelReport?> getModelReport() async => null;

  @override
  Future<List<StoreSummary>> getStores(int userId) async =>
      StoreSummary.fromReceipts(await getReceipts(userId));

  @override
  Future<PriceHistory> getPriceHistory(int userId, String query) async {
    final db = await AppDatabase.instance;
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final where =
        [for (final _ in words) 'LOWER(i.item_name) LIKE ?'].join(' AND ');
    final rows = await db.rawQuery(
        'SELECT i.item_name, i.item_price, r.merchant_name, r.transaction_date '
        'FROM receipt_items i JOIN receipts r ON r.id = i.receipt_id '
        'WHERE r.user_id = ? AND i.item_price > 0 ${where.isEmpty ? '' : 'AND $where'} '
        'ORDER BY r.transaction_date DESC, i.id DESC LIMIT 200',
        [userId, for (final w in words) '%$w%']);
    return PriceHistory.fromPoints([
      for (final r in rows)
        PricePoint(
          itemName: r['item_name'] as String,
          merchantName: (r['merchant_name'] as String?) ?? 'Tanpa nama toko',
          date: DateTime.tryParse('${r['transaction_date']}'),
          quantity: 1,
          unitPrice: (r['item_price'] as num).toDouble(),
        ),
    ]);
  }

  @override
  Future<List<ReceiptModel>> getReceiptSummaries(int userId,
          {required DateTime month}) =>
      getReceipts(userId, month: month);

  @override
  Future<List<ReceiptModel>> getReceipts(int userId, {DateTime? month}) async {
    final db = await AppDatabase.instance;

    final where = month == null ? 'r.user_id = ?' : _monthWhere;
    final args = month == null ? <Object?>[userId] : _monthArgs(userId, month);

    final receiptRows = await db.rawQuery(
        'SELECT r.* FROM receipts r WHERE $where '
        'ORDER BY r.transaction_date DESC, r.id DESC',
        args);
    if (receiptRows.isEmpty) return [];

    final itemRows = await db.rawQuery(
        'SELECT i.*, c.name AS category_name FROM receipt_items i '
        'JOIN receipts r ON r.id = i.receipt_id '
        'JOIN categories c ON c.id = i.category_id '
        'WHERE $where ORDER BY i.id',
        args);

    final itemsByReceipt = <int, List<ReceiptItemModel>>{};
    for (final row in itemRows) {
      final item = ReceiptItemModel.fromJson(row);
      itemsByReceipt.putIfAbsent(item.receiptId!, () => []).add(item);
    }

    return receiptRows.map((row) {
      final base = ReceiptModel.fromJson(row);
      return base.copyWith(items: itemsByReceipt[base.id] ?? const []);
    }).toList();
  }

  @override
  Future<DashboardModel> getDashboard(int userId, DateTime month) async {
    final db = await AppDatabase.instance;
    final args = _monthArgs(userId, month);

    final totalRows = await db.rawQuery(
        'SELECT COALESCE(SUM(r.total_amount), 0) AS total, COUNT(*) AS cnt '
        'FROM receipts r WHERE $_monthWhere',
        args);

    final categoryRows = await db.rawQuery(
        'SELECT c.name AS category_name, SUM(i.item_price) AS total '
        'FROM receipt_items i '
        'JOIN receipts r ON r.id = i.receipt_id '
        'JOIN categories c ON c.id = i.category_id '
        'WHERE $_monthWhere GROUP BY c.id, c.name ORDER BY total DESC',
        args);

    final receipts = await getReceipts(userId, month: month);

    return DashboardModel(
      month: DateTime(month.year, month.month),
      totalAmount: (totalRows.first['total'] as num).toDouble(),
      receiptCount: (totalRows.first['cnt'] as num).toInt(),
      categoryTotals: categoryRows.map(CategoryTotal.fromJson).toList(),
      recentReceipts: receipts.take(3).toList(),
    );
  }

  @override
  Future<DateTime?> latestMonthWithData(int userId) async {
    final months = await availableMonths(userId);
    return months.isEmpty ? null : months.first;
  }

  @override
  Future<List<DateTime>> availableMonths(int userId) async {
    final db = await AppDatabase.instance;
    final rows = await db.rawQuery(
        'SELECT DISTINCT substr(transaction_date, 1, 7) AS ym FROM receipts '
        'WHERE user_id = ? ORDER BY ym DESC',
        [userId]);
    return rows
        .map((r) => DateTime.tryParse('${r['ym']}-01'))
        .whereType<DateTime>()
        .toList();
  }

  @override
  Future<int> countReceipts(int userId) async {
    final db = await AppDatabase.instance;
    final count = Sqflite.firstIntValue(await db
        .rawQuery('SELECT COUNT(*) FROM receipts WHERE user_id = ?', [userId]));
    return count ?? 0;
  }

  @override
  Future<void> deleteReceipt(int userId, int receiptId) async {
    final db = await AppDatabase.instance;
    // receipt_items ikut terhapus (ON DELETE CASCADE).
    await db.delete('receipts',
        where: 'id = ? AND user_id = ?', whereArgs: [receiptId, userId]);
  }
}

class _Rule {
  const _Rule(this.keywords, this.category, this.confidence);

  final List<String> keywords;
  final String category;
  final double confidence;
}
