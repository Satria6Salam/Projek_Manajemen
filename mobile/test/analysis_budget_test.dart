import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/features/budget/budget_service.dart';
import 'package:strukku/features/insights/analysis_period.dart';
import 'package:strukku/features/insights/insight_service.dart';
import 'package:strukku/models/dashboard_model.dart';
import 'package:strukku/models/receipt_model.dart';

ReceiptModel _r(DateTime when, double total, {String merchant = 'Indomaret'}) => ReceiptModel(
      userId: 1,
      merchantName: merchant,
      transactionDate: when,
      totalAmount: total,
      createdAt: when,
    );

void main() {
  const service = InsightService();

  group('AnalysisPeriod', () {
    test('rentang hari, bulan, tahun', () {
      final day = AnalysisPeriod.day(DateTime(2026, 11, 14, 15));
      expect(day.start, DateTime(2026, 11, 14));
      expect(day.endExclusive, DateTime(2026, 11, 15));
      expect(AnalysisPeriod.month(2026, 2).totalDays, 28);
      expect(AnalysisPeriod.year(2024).totalDays, 366);
      expect(AnalysisPeriod.month(2026, 1).previous, AnalysisPeriod.month(2025, 12));
    });

    test('tidak bisa maju melewati hari ini', () {
      final now = DateTime(2026, 11, 14);
      expect(AnalysisPeriod.month(2026, 11).canGoNext(now), isFalse);
      expect(AnalysisPeriod.month(2026, 10).canGoNext(now), isTrue);
      expect(AnalysisPeriod.year(2026).canGoNext(now), isFalse);
    });
  });

  test('analisis harian membandingkan dengan kemarin tanpa proyeksi', () {
    final a = service.analyzePeriod(
      period: AnalysisPeriod.day(DateTime(2026, 11, 14)),
      now: DateTime(2026, 11, 14, 20),
      receipts: [_r(DateTime(2026, 11, 14, 9), 60000)],
      previousReceipts: [_r(DateTime(2026, 11, 13, 9), 30000)],
      categories: const [CategoryTotal(categoryName: 'Makanan', total: 60000)],
    );
    expect(a.changePercent, closeTo(100, 0.01));
    expect(a.insights.first.title, 'Pengeluaran naik 100%');
    expect(a.insights.map((i) => i.title), isNot(contains('Proyeksi akhir bulan')));
  });

  test('analisis bulan menghitung total harian untuk grafik', () {
    final a = service.analyzePeriod(
      period: AnalysisPeriod.month(2026, 10),
      now: DateTime(2026, 11, 14),
      receipts: [
        _r(DateTime(2026, 10, 3), 10000),
        _r(DateTime(2026, 10, 3, 18), 5000),
        _r(DateTime(2026, 10, 31), 20000),
      ],
      previousReceipts: const [],
      categories: const [CategoryTotal(categoryName: 'Makanan', total: 35000)],
    );
    expect(a.dailyTotals, hasLength(31));
    expect(a.dailyTotals[2], 15000);
    expect(a.dailyTotals[30], 20000);
  });

  test('tahun berjalan: proyeksi akhir tahun & perbandingan dengan tahun lalu', () {
    final a = service.analyzePeriod(
      period: AnalysisPeriod.year(2026),
      now: DateTime(2026, 7, 1),
      receipts: [
        for (int m = 1; m <= 6; m++) _r(DateTime(2026, m, 10), 100000),
      ],
      previousReceipts: [
        _r(DateTime(2025, 3, 1), 200000),
        _r(DateTime(2025, 11, 1), 900000), // setelah 1 Juli: tidak ikut dibandingkan
      ],
      categories: const [CategoryTotal(categoryName: 'Makanan', total: 600000)],
    );
    expect(a.previousToDate, 200000);
    expect(a.changePercent, closeTo(200, 0.01));
    expect(a.insights.map((i) => i.title), contains('Proyeksi akhir tahun'));
  });

  test('tren: bulan terboros, naik 3 bulan berturut-turut, dan vs tahun lalu', () {
    final t = service.analyzeTrends(
      year: 2026,
      now: DateTime(2026, 11, 14),
      monthlyTotals: [0, 0, 0, 0, 0, 0, 0, 100, 200, 300, 50, 0],
      previousYearMonthlyTotals: [0, 0, 0, 0, 0, 0, 0, 100, 100, 100, 100, 0],
      yearlyTotals: {2026: 650, 2025: 400},
    );
    expect(t.peakMonth, 10);
    expect(t.activeMonths, 4);
    expect(t.yearlyTotals.keys.toList(), [2025, 2026]); // terurut naik
    final titles = t.insights.map((i) => i.title).toList();
    expect(titles, contains('Bulan terboros: Oktober'));
    expect(titles, contains('November turun 83%'));
    expect(titles, contains('Lebih boros 63% dari tahun lalu'));
  });

  group('BudgetRow', () {
    test('tingkat peringatan 80% dan 100%', () {
      expect(const BudgetRow(name: 'Makanan', spent: 50).level, BudgetLevel.none);
      expect(const BudgetRow(name: 'Makanan', spent: 50, limit: 100).level, BudgetLevel.safe);
      expect(const BudgetRow(name: 'Makanan', spent: 80, limit: 100).level, BudgetLevel.warning);
      expect(const BudgetRow(name: 'Makanan', spent: 120, limit: 100).level, BudgetLevel.over);
      expect(const BudgetRow(name: 'Makanan', spent: 120, limit: 100).remaining, -20);
    });

    test('snapshot hanya memuat baris yang perlu diperingatkan', () {
      final s = BudgetSnapshot(
        month: DateTime(2026, 11),
        total: const BudgetRow(name: 'Total', spent: 100, limit: 1000, isTotal: true),
        rows: const [
          BudgetRow(name: 'Makanan', spent: 90, limit: 100),
          BudgetRow(name: 'Minuman', spent: 10, limit: 100),
          BudgetRow(name: 'Kesehatan', spent: 10),
        ],
      );
      expect(s.alerts.map((r) => r.name), ['Makanan']);
      expect(s.hasAnyLimit, isTrue);
    });
  });
}
