import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/core/utils/receipt_parser.dart';
import 'package:strukku/data/repositories/receipt_repository.dart';
import 'package:strukku/features/stores/maps_launcher.dart';
import 'package:strukku/models/receipt_model.dart';

ReceiptModel _r(String name, String? addr, double total, int day) => ReceiptModel(
      userId: 1, merchantName: name, merchantAddress: addr,
      transactionDate: DateTime(2026, 11, day), totalAmount: total, createdAt: DateTime(2026, 11, day));

void main() {
  test('alamat toko terbaca dari struk, J1. diperbaiki jadi Jl.', () {
    final p = ReceiptParser.parse('ELEKTRONIK PLUS\nJ1. Merdeka No. 88, Bandung\nTelp. 022-8765\nTotal 437.000');
    expect(p.merchantAddress, 'Jl. Merdeka No. 88, Bandung');
  });

  test('toko dikelompokkan per nama + alamat (cabang berbeda terpisah)', () {
    final s = StoreSummary.fromReceipts([
      _r('Indomaret', 'Jl. Dago 1', 10000, 1),
      _r('INDOMARET', 'Jl. Dago 1', 20000, 5),
      _r('Indomaret', 'Jl. Merdeka 5', 5000, 3),
    ]);
    expect(s.first.visits, 2);
    expect(s.first.totalSpent, 30000);
    expect(s.first.lastVisit, DateTime(2026, 11, 5));
    expect(s, hasLength(2));
  });

  test('tautan Maps memuat nama toko dan alamat', () {
    final uri = MapsLauncher.searchUri('Indomaret', 'Jl. Dago 1, Bandung');
    expect(uri.host, 'www.google.com');
    expect(uri.queryParameters['query'], 'Indomaret, Jl. Dago 1, Bandung');
  });
}
