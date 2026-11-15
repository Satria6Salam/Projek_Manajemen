// Uji integrasi dengan backend yang sedang berjalan (dilewati secara default).
//
// Jalankan backend, lalu:
//   flutter test test/server_scan_integration_test.dart \
//     --dart-define=RUN_SERVER_TESTS=true \
//     --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
//     --dart-define=TEST_RECEIPT_IMAGE=C:/path/foto_struk.jpg
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:strukku/data/remote/api_config.dart';
import 'package:strukku/features/export/export_service.dart';
import 'package:strukku/data/remote/fastapi_client.dart';
import 'package:strukku/data/repositories/fastapi_receipt_repository.dart';
import 'package:strukku/models/receipt_item_model.dart';
import 'package:strukku/models/receipt_model.dart';

const bool _run = bool.fromEnvironment('RUN_SERVER_TESTS');
const String _image = String.fromEnvironment('TEST_RECEIPT_IMAGE');

void main() {
  test('pindai di server, simpan dengan scan_id & qty, lalu foto bisa dibuka', () async {
    final base = '${ApiConfig.baseUrl}${ApiConfig.apiPrefix}';
    final email = 'uji${DateTime.now().millisecondsSinceEpoch}@strukku-uji.id';
    const password = 'Strukku!2026xy';
    final reg = await http.post(Uri.parse('$base/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'full_name': 'Uji Integrasi', 'email': email, 'password': password}));
    expect(reg.statusCode, 201, reason: reg.body);
    final login = await http.post(Uri.parse('$base/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}));
    expect(login.statusCode, 200, reason: login.body);

    final client = FastApiClient()
      ..accessToken = (jsonDecode(login.body) as Map)['access_token'] as String;
    final repo = FastApiReceiptRepository(client);

    // 1. Pindai.
    final scan = await repo.scanReceipt(_image);
    expect(scan, isNotNull);
    expect(scan!.scanId, isNotEmpty);
    expect(scan.parsed.items, isNotEmpty);
    expect(scan.classification.predictions.length, scan.parsed.items.length);
    // ignore: avoid_print
    print('scan: ${scan.parsed.merchantName} total=${scan.parsed.totalAmount} '
        'items=${scan.parsed.items.map((i) => '${i.quantity}x ${i.name} ${i.price}').toList()} '
        'warnings=${scan.warnings}');

    // 2. Simpan dengan qty 3 pada barang pertama + scan_id.
    final preds = scan.classification.predictions;
    final items = [
      for (var n = 0; n < scan.parsed.items.length; n++)
        ReceiptItemModel(
          categoryId: preds[n].categoryId ?? 1,
          itemName: scan.parsed.items[n].name,
          itemPrice: scan.parsed.items[n].price,
          confidenceScore: preds[n].confidence,
          quantity: n == 0 ? 3 : scan.parsed.items[n].quantity,
          predictedCategoryId: preds[n].categoryId,
          predictionSource: preds[n].source,
        ),
    ];
    final saved = await repo.saveReceipt(ReceiptModel(
      userId: 0,
      merchantName: scan.parsed.merchantName ?? 'Uji',
      transactionDate: scan.parsed.transactionDate ?? DateTime.now(),
      totalAmount: scan.parsed.totalAmount ?? 1000,
      createdAt: DateTime.now(),
      scanId: scan.scanId,
      items: items,
    ));
    expect(saved.id, isNotNull);
    expect(saved.imageUrl, isNotNull, reason: 'foto harus tertaut lewat scan_id');
    expect(saved.items.first.quantity, 3);

    // 3. Foto bisa dibuka dengan token.
    final img = await http.get(Uri.parse(saved.imageUrl!), headers: client.authHeaders);
    expect(img.statusCode, 200);
    expect(img.headers['content-type'], contains('image/jpeg'));
    expect(img.bodyBytes.length, greaterThan(1000));

    // 4. Riwayat memuat foto & qty.
    final list = await repo.getReceipts(0, month: saved.transactionDate);
    final again = list.firstWhere((r) => r.id == saved.id);
    expect(again.imageUrl, isNotNull);
    expect(again.items.first.quantity, 3);

    // 5. Data analisis: hari, tren bulanan, tren tahunan.
    final d = saved.transactionDate;
    final day = await repo.getPeriodData(
        0, DateTime(d.year, d.month, d.day), DateTime(d.year, d.month, d.day + 1));
    expect(day.receipts.map((r) => r.id), contains(saved.id));
    expect(day.total, saved.totalAmount);
    expect(day.categoryTotals, isNotEmpty);
    final monthly = await repo.getMonthlyTotals(0, d.year);
    expect(monthly, hasLength(12));
    expect(monthly[d.month - 1], saved.totalAmount);
    final yearly = await repo.getYearlyTotals(0);
    expect(yearly[d.year], saved.totalAmount);

    // 6. Laporan CSV bulan struk berisi barang (bukan file kosong).
    final csv = const ExportService().buildCsv(list);
    expect(csv, contains(saved.items.first.itemName));
    expect(csv, contains('Total semua struk'));

    await repo.deleteReceipt(0, saved.id!);
  }, skip: _run ? false : 'Butuh backend berjalan (RUN_SERVER_TESTS=true)');
}
