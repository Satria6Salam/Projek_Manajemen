import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/features/insights/insight_service.dart';
import 'package:strukku/models/dashboard_model.dart';
import 'package:strukku/models/receipt_model.dart';

ReceiptModel _r(int day, double total, {String merchant = 'Indomaret', int month = 10}) =>
    ReceiptModel(
      userId: 1,
      merchantName: merchant,
      transactionDate: DateTime(2026, month, day),
      totalAmount: total,
      createdAt: DateTime(2026, month, day),
    );

void main() {
  const service = InsightService();

  test('data sedikit memberi saran mencatat lebih banyak', () {
    final a = service.analyzeMonth(
      month: DateTime(2026, 10),
      now: DateTime(2026, 11, 14),
      receipts: [_r(3, 10000)],
      previousReceipts: const [],
      categories: const [CategoryTotal(categoryName: 'Makanan', total: 10000)],
    );
    expect(a.persona, isNull);
    expect(a.insights.single.title, 'Data masih sedikit');
    expect(a.categoryAdvice.single.categoryName, 'Makanan');
  });

  test('kategori dominan menghasilkan persona, peringatan, dan saran', () {
    final a = service.analyzeMonth(
      month: DateTime(2026, 10),
      now: DateTime(2026, 11, 14),
      receipts: [_r(1, 50000), _r(2, 60000), _r(5, 70000), _r(9, 20000)],
      previousReceipts: [_r(3, 40000, month: 9), _r(8, 40000, month: 9)],
      categories: const [
        CategoryTotal(categoryName: 'Minuman', total: 150000),
        CategoryTotal(categoryName: 'Makanan', total: 50000),
      ],
    );
    expect(a.persona!.title, 'Penikmat Minuman');
    expect(a.changePercent, closeTo(150, 0.01));
    final titles = a.insights.map((i) => i.title).toList();
    expect(titles.first, startsWith('Pengeluaran naik')); // peringatan di urutan atas
    expect(titles, contains('Minuman mendominasi'));
    expect(titles, contains('Langganan: Indomaret'));
    expect(a.insights.any((i) => i.kind == InsightKind.tip), isTrue);
  });

  test('nama kategori dari backend (pakai garis bawah) tetap dikenali', () {
    expect(InsightService.tipFor('Kebutuhan_Rumah_Tangga'), isNotNull);
    expect(InsightService.tipFor('Kebutuhan Rumah Tangga'), isNotNull);
    expect(InsightService.tipFor('Perawatan Diri'), isNotNull);
  });

  test('proyeksi akhir bulan dihitung untuk bulan berjalan', () {
    final a = service.analyzeMonth(
      month: DateTime(2026, 11),
      now: DateTime(2026, 11, 10),
      receipts: [_r(2, 30000, month: 11), _r(5, 30000, month: 11), _r(9, 40000, month: 11)],
      previousReceipts: const [],
      categories: const [CategoryTotal(categoryName: 'Makanan', total: 100000)],
    );
    expect(a.averagePerDay, closeTo(10000, 0.01));
    expect(a.projectedTotal, closeTo(300000, 0.01));
    expect(a.insights.map((i) => i.title), contains('Proyeksi akhir bulan'));
  });
}
