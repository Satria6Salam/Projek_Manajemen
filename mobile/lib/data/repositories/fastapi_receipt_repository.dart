import '../../core/errors/app_exception.dart';
import '../../core/utils/receipt_parser.dart';
import '../../models/dashboard_model.dart';
import '../../models/model_report.dart';
import '../../models/price_history.dart';
import '../../models/receipt_item_model.dart';
import '../../models/receipt_model.dart';
import '../remote/api_config.dart';
import '../remote/api_routes.dart';
import '../remote/fastapi_client.dart';
import 'receipt_repository.dart';

/// Repository struk yang memakai backend STRUKKU (FastAPI).
/// Bentuk JSON mengikuti strukku_backend/docs/API_FRONTEND.md.
class FastApiReceiptRepository implements ReceiptRepository {
  FastApiReceiptRepository(this._client);

  final FastApiClient _client;

  // ------------------------------------------------------------ klasifikasi
  /// POST /classify {"texts": [...]}
  /// -> [{"text","category_id","category":{"name",...}|null,"confidence_score",...}]
  @override
  Future<ClassificationResult> classifyItems(List<String> itemNames) async {
    if (itemNames.isEmpty) {
      return const ClassificationResult(predictions: [], isSimulated: false);
    }
    final data = await _client.post(ApiRoutes.classify,
        body: {'texts': itemNames}, timeout: ApiConfig.longTimeout);
    if (data is! List || data.length != itemNames.length) {
      throw AppException(
          'Respons klasifikasi dari server tidak sesuai format.');
    }
    final predictions = <ItemPrediction>[];
    for (var i = 0; i < data.length; i++) {
      final m = data[i] as Map<String, dynamic>;
      final cat = m['category'];
      predictions.add(ItemPrediction(
        itemName: (m['text'] as String?) ?? itemNames[i],
        // Nama tampilan, sama dengan "name" di GET /categories.
        categoryName: cat is Map ? (cat['name'] as String? ?? '') : '',
        confidence: (m['confidence_score'] as num?)?.toDouble() ?? 0,
      ));
    }
    return ClassificationResult(predictions: predictions, isSimulated: false);
  }

  // --------------------------------------------------------------- analitik
  /// GET /analytics/period?date_from&date_to (inklusif) -> PeriodOut.
  @override
  Future<PeriodData> getPeriodData(
      int userId, DateTime start, DateTime endExclusive) async {
    final last = endExclusive.subtract(const Duration(days: 1));
    final data = await _client.get(ApiRoutes.analyticsPeriod, query: {
      'date_from': _ymd(start),
      'date_to': _ymd(last.isBefore(start) ? start : last),
    });
    if (data is! Map<String, dynamic>) {
      throw AppException('Respons analitik dari server tidak sesuai format.');
    }
    final receipts = (data['receipts'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((r) => _receiptFromApi(r, userId))
        .toList();
    final categories = (data['categories'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((c) {
          final cat = c['category'];
          return CategoryTotal(
            categoryName: cat is Map
                ? (cat['name'] as String? ?? 'Lainnya')
                : 'Tanpa kategori',
            total: (c['amount'] as num?)?.toDouble() ?? 0,
          );
        })
        .where((c) => c.total > 0)
        .toList();
    return PeriodData(receipts: receipts, categoryTotals: categories);
  }

  /// GET /analytics/monthly?month=YYYY-12&months=12 -> 12 titik.
  @override
  Future<List<double>> getMonthlyTotals(int userId, int year) async {
    final data = await _client.get(ApiRoutes.analyticsMonthly,
        query: {'month': '$year-12', 'months': '12'});
    final totals = List<double>.filled(12, 0);
    for (final p in (data as List? ?? const []).cast<Map<String, dynamic>>()) {
      final key = '${p['month']}'; // YYYY-MM
      final m = int.tryParse(key.length >= 7 ? key.substring(5, 7) : '');
      if (key.startsWith('$year-') && m != null && m >= 1 && m <= 12) {
        totals[m - 1] = (p['total_spent'] as num?)?.toDouble() ?? 0;
      }
    }
    return totals;
  }

  /// GET /analytics/yearly -> [{year, total_spent, receipt_count}].
  @override
  Future<Map<int, double>> getYearlyTotals(int userId) async {
    final data = await _client.get(ApiRoutes.analyticsYearly);
    return {
      for (final p in (data as List? ?? const []).cast<Map<String, dynamic>>())
        (p['year'] as num).toInt(): (p['total_spent'] as num?)?.toDouble() ?? 0,
    };
  }

  @override
  Future<ModelReport?> getModelReport() async {
    final data = await _client.get(ApiRoutes.analyticsModel);
    if (data is! Map<String, dynamic>) {
      throw AppException('Respons evaluasi model tidak sesuai format.');
    }
    return ModelReport.fromJson(data);
  }

  @override
  Future<PriceHistory> getPriceHistory(int userId, String query) async {
    final data = await _client.get(ApiRoutes.priceHistory, query: {'q': query});
    if (data is! Map<String, dynamic>) {
      throw AppException('Respons riwayat harga tidak sesuai format.');
    }
    return PriceHistory.fromJson(data);
  }

  @override
  Future<List<StoreSummary>> getStores(int userId) async {
    final data = await _client.get(ApiRoutes.stores);
    return [
      for (final s in (data as List? ?? const []).cast<Map<String, dynamic>>())
        StoreSummary(
          name: s['merchant_name'] as String,
          address: s['merchant_address'] as String?,
          visits: (s['visits'] as num).toInt(),
          totalSpent: (s['total_spent'] as num).toDouble(),
          lastVisit: s['last_visit'] == null
              ? null
              : DateTime.tryParse('${s['last_visit']}'),
        ),
    ];
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------------ pindai
  /// POST /scans (multipart, field "file") -> ScanOut.
  @override
  Future<ServerScan?> scanReceipt(String imagePath,
      {String? deviceText}) async {
    final text = deviceText?.trim() ?? '';
    final data = await _client.upload(ApiRoutes.scans, imagePath,
        timeout: const Duration(seconds: 90),
        fields: text.isEmpty
            ? null
            : {
                'device_text':
                    text.length > 20000 ? text.substring(0, 20000) : text
              });
    if (data is! Map<String, dynamic> || data['scan_id'] is! String) {
      throw AppException('Respons pindai dari server tidak sesuai format.');
    }
    final rawItems =
        (data['items'] as List? ?? const []).cast<Map<String, dynamic>>();
    final items = <ParsedItem>[];
    final predictions = <ItemPrediction>[];
    for (final m in rawItems) {
      final name = (m['item_name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final qty = (m['quantity'] as num?)?.toInt() ?? 1;
      final unit = (m['unit_price'] as num?)?.toDouble();
      final price = (m['item_price'] as num?)?.toDouble() ??
          (unit == null ? 0 : unit * qty);
      items.add(ParsedItem(name, price,
          quantity: qty < 1 ? 1 : qty,
          unitPrice: unit,
          priceCorrected: m['price_corrected'] == true,
          nameCorrected: m['name_corrected'] == true,
          suspicious: m['suspicious'] == true));
      final cat = m['category'];
      predictions.add(ItemPrediction(
        itemName: name,
        categoryName: cat is Map ? (cat['name'] as String? ?? '') : '',
        confidence: (m['confidence_score'] as num?)?.toDouble() ?? 0,
        categoryId: (m['predicted_category_id'] as num?)?.toInt() ??
            (m['category_id'] as num?)?.toInt(),
        source: m['prediction_source'] as String?,
      ));
    }
    final date = data['transaction_date'];
    return ServerScan(
      scanId: data['scan_id'] as String,
      rawText: (data['raw_text'] as String?) ?? '',
      parsed: ParsedReceipt(
        merchantName:
            (data['merchant_name'] as String?)?.trim().isNotEmpty == true
                ? data['merchant_name'] as String
                : null,
        merchantAddress: data['merchant_address'] as String?,
        transactionDate: date == null ? null : DateTime.tryParse('$date'),
        totalAmount: (data['total_amount'] as num?)?.toDouble(),
        items: items,
      ),
      classification:
          ClassificationResult(predictions: predictions, isSimulated: false),
      warnings:
          (data['warnings'] as List? ?? const []).map((w) => '$w').toList(),
      consistent: data['consistent'] as bool?,
      fieldConfidence: {
        for (final e
            in ((data['field_confidence'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      reviewFields: (data['review_fields'] as List? ?? const [])
          .map((f) => '$f')
          .toList(),
      ocrSource: data['ocr_source'] as String?,
    );
  }

  // ------------------------------------------------------------------ simpan
  /// POST /receipts -> ReceiptOut
  @override
  Future<ReceiptModel> saveReceipt(ReceiptModel receipt,
      {bool allowDuplicate = false}) async {
    final body = <String, dynamic>{
      if (allowDuplicate) 'allow_duplicate': true,
      'merchant_name': receipt.merchantName,
      if (receipt.merchantAddress != null)
        'merchant_address': receipt.merchantAddress,
      // Waktu lokal tanpa zona (dianggap WIB oleh backend).
      'transaction_date': _localIso(receipt.transactionDate),
      'total_amount': receipt.totalAmount,
      // scan_id dari POST /scans: foto struk di server ikut tersimpan.
      if (receipt.scanId != null) 'scan_id': receipt.scanId,
      'items': [
        for (final i in receipt.items)
          {
            'item_name': i.itemName,
            'quantity': i.quantity < 1 ? 1 : i.quantity,
            'item_price': i.itemPrice,
            'category_id': i.categoryId,
            if (i.predictedCategoryId != null)
              'predicted_category_id': i.predictedCategoryId,
            if (i.predictionSource != null)
              'prediction_source': i.predictionSource,
            'confidence_score': i.confidenceScore,
            'is_user_corrected': i.isUserCorrected,
          },
      ],
    };
    final data = await _client.post(ApiRoutes.receipts, body: body);
    if (data is! Map<String, dynamic>) {
      throw AppException(
          'Respons penyimpanan dari server tidak sesuai format.');
    }
    return _receiptFromApi(data, receipt.userId);
  }

  // ------------------------------------------------------------------ daftar
  /// GET /receipts?month=YYYY-MM -> {"items":[ReceiptSummaryOut],"total",...}
  /// Ringkasan tidak memuat daftar barang, jadi detail tiap struk diambil
  /// (GET /receipts/{id}) agar lembar detail bisa menampilkan barangnya.
  @override
  Future<List<ReceiptModel>> getReceipts(int userId, {DateTime? month}) async {
    final data = await _client.get(ApiRoutes.receipts, query: {
      'page': '1',
      'page_size': '100',
      if (month != null) 'month': _ym(month),
    });
    final list = (data is Map ? data['items'] : data) as List? ?? const [];
    return _withDetails(list.cast<Map<String, dynamic>>(), userId);
  }

  @override
  Future<List<ReceiptModel>> getReceiptSummaries(int userId,
      {required DateTime month}) async {
    final data = await _client.get(ApiRoutes.receipts, query: {
      'page': '1',
      'page_size': '100',
      'month': _ym(month),
    });
    final list = (data is Map ? data['items'] : data) as List? ?? const [];
    return list
        .cast<Map<String, dynamic>>()
        .map((s) => _receiptFromApi(s, userId))
        .toList();
  }

  @override
  Future<DashboardModel> getDashboard(int userId, DateTime month) async {
    final data =
        await _client.get(ApiRoutes.dashboard, query: {'month': _ym(month)});
    if (data is! Map<String, dynamic>) {
      throw AppException('Respons dashboard dari server tidak sesuai format.');
    }
    final categories = (data['categories'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((c) {
          final cat = c['category'];
          return CategoryTotal(
            categoryName: cat is Map
                ? (cat['name'] as String? ?? 'Lainnya')
                : 'Tanpa kategori',
            total: (c['amount'] as num?)?.toDouble() ?? 0,
          );
        })
        .where((c) => c.total > 0)
        .toList();

    final recent = await _withDetails(
        (data['recent_receipts'] as List? ?? const [])
            .cast<Map<String, dynamic>>(),
        userId);

    return DashboardModel(
      month: DateTime.tryParse('${data['month']}-01') ??
          DateTime(month.year, month.month),
      totalAmount: (data['total_spent'] as num?)?.toDouble() ?? 0,
      receiptCount: (data['receipt_count'] as num?)?.toInt() ?? 0,
      categoryTotals: categories,
      recentReceipts: recent,
    );
  }

  /// GET /analytics/monthly?months=24 -> [{"month":"YYYY-MM","receipt_count",...}]
  @override
  Future<List<DateTime>> availableMonths(int userId) async {
    final data =
        await _client.get(ApiRoutes.analyticsMonthly, query: {'months': '24'});
    final list = data is List ? data : const [];
    final months = list
        .whereType<Map<String, dynamic>>()
        .where((m) => ((m['receipt_count'] as num?) ?? 0) > 0)
        .map((m) => DateTime.tryParse('${m['month']}-01'))
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return months;
  }

  @override
  Future<DateTime?> latestMonthWithData(int userId) async {
    final months = await availableMonths(userId);
    return months.isEmpty ? null : months.first;
  }

  @override
  Future<int> countReceipts(int userId) async {
    final data = await _client
        .get(ApiRoutes.receipts, query: {'page': '1', 'page_size': '1'});
    return data is Map ? ((data['total'] as num?)?.toInt() ?? 0) : 0;
  }

  @override
  Future<void> deleteReceipt(int userId, int receiptId) async {
    await _client.delete(ApiRoutes.receiptById(receiptId));
  }

  // ----------------------------------------------------------------- helper
  Future<List<ReceiptModel>> _withDetails(
      List<Map<String, dynamic>> summaries, int userId) {
    return Future.wait(summaries.map((s) async {
      final id = (s['id'] as num?)?.toInt();
      if (id == null) return _receiptFromApi(s, userId);
      try {
        final detail = await _client.get(ApiRoutes.receiptById(id));
        if (detail is Map<String, dynamic>) {
          return _receiptFromApi(detail, userId);
        }
      } on AppException {
        // Pakai ringkasan saja jika detail gagal dimuat.
      }
      return _receiptFromApi(s, userId);
    }));
  }

  ReceiptModel _receiptFromApi(Map<String, dynamic> json, int userId) {
    final items = (json['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((m) {
      final cat = m['category'];
      return ReceiptItemModel(
        id: (m['id'] as num?)?.toInt(),
        receiptId: (json['id'] as num?)?.toInt(),
        categoryId: (m['category_id'] as num?)?.toInt() ?? 0,
        categoryName:
            cat is Map ? (cat['name'] as String? ?? '') : 'Tanpa kategori',
        itemName: (m['item_name'] as String?) ?? '-',
        itemPrice: (m['item_price'] as num?)?.toDouble() ?? 0,
        confidenceScore: (m['confidence_score'] as num?)?.toDouble(),
        isUserCorrected: m['is_user_corrected'] == true,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        predictedCategoryId: (m['predicted_category_id'] as num?)?.toInt(),
        predictionSource: m['prediction_source'] as String?,
      );
    }).toList();

    final created =
        DateTime.tryParse('${json['created_at']}')?.toLocal() ?? DateTime.now();
    return ReceiptModel(
      id: (json['id'] as num?)?.toInt(),
      userId: userId,
      merchantName:
          (json['merchant_name'] as String?)?.trim().isNotEmpty == true
              ? json['merchant_name'] as String
              : 'Tanpa nama toko',
      // transaction_date dari backend = waktu lokal WIB tanpa zona.
      merchantAddress:
          (json['merchant_address'] as String?)?.trim().isNotEmpty == true
              ? json['merchant_address'] as String
              : null,
      transactionDate:
          DateTime.tryParse('${json['transaction_date']}') ?? created,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ??
          items.fold<double>(0, (s, i) => s + i.itemPrice),
      imageUrl: json['image_url'] == null
          ? null
          : _client.absoluteUrl(json['image_url'] as String),
      createdAt: created,
      items: items,
    );
  }

  String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  String _localIso(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final l = d.isUtc ? d.toLocal() : d;
    return '${l.year}-${two(l.month)}-${two(l.day)}T${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}
