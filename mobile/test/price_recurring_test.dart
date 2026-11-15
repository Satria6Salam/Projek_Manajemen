import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/features/recurring/recurring_service.dart';
import 'package:strukku/models/price_history.dart';

RecurringExpense _r({int day = 5, DateTime? last, bool active = true}) => RecurringExpense(
      id: '1',
      name: 'Netflix',
      amount: 54000,
      categoryName: 'Lainnya',
      dayOfMonth: day,
      startMonth: DateTime(2026, 9),
      lastGenerated: last,
      active: active,
    );

void main() {
  test('riwayat harga: perbandingan per toko, termurah lebih dulu', () {
    final h = PriceHistory.fromPoints([
      PricePoint(itemName: 'Indomie', merchantName: 'Indomaret', date: DateTime(2026, 2), quantity: 1, unitPrice: 3600),
      PricePoint(itemName: 'Indomie', merchantName: 'Alfamart', date: DateTime(2026, 1, 9), quantity: 1, unitPrice: 3200),
      PricePoint(itemName: 'Indomie', merchantName: 'INDOMARET', date: DateTime(2026, 1, 2), quantity: 2, unitPrice: 3500),
    ]);
    expect(h.cheapestMerchant, 'Alfamart');
    final indo = h.merchants.last;
    expect(indo.purchases, 2);
    expect(indo.latest, 3600);
    expect(indo.lowest, 3500);
    expect(indo.average, 3550);
  });

  group('pengeluaran berulang', () {
    test('bulan jatuh tempo sejak bulan mulai sampai hari ini', () {
      final due = _r().dueMonths(DateTime(2026, 11, 14));
      expect(due, [DateTime(2026, 9), DateTime(2026, 10), DateTime(2026, 11)]);
    });

    test('belum jatuh tempo bulan ini bila tanggalnya belum lewat', () {
      final due = _r(day: 20, last: DateTime(2026, 10)).dueMonths(DateTime(2026, 11, 14));
      expect(due, isEmpty);
    });

    test('tanggal 31 di bulan pendek memakai tanggal terakhir', () {
      expect(_r(day: 31).dueIn(DateTime(2026, 2)).day, 28);
    });

    test('dijeda = tidak dicatat', () {
      expect(_r(active: false).dueMonths(DateTime(2026, 11, 14)), isEmpty);
    });

    test('simpan & baca JSON', () {
      final r = _r(last: DateTime(2026, 10));
      final back = RecurringExpense.fromJson(r.toJson());
      expect(back.lastGenerated, DateTime(2026, 10));
      expect(back.dayOfMonth, 5);
    });
  });
}
