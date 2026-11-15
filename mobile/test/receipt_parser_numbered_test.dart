import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/core/utils/receipt_parser.dart';

void main() {
  test('nomor urut & qty salah baca tidak masuk ke nama barang', () {
    const text = '''ELEKTRONIK PLUS
Tanggal : 01-10-2026 15:37
No. Nama Barang Qty Harga Jumlah
Al Headphone Bluetooth al 299.000 299.000
2 USB Flash Drive 64GB 1 89.000 89.000
3 Kabel Data Type-C il 49.000 49.000
Total 437.000''';
    final parsed = ReceiptParser.parse(text);
    expect(parsed.items.map((i) => i.name).toList(),
        ['Headphone Bluetooth', 'USB Flash Drive 64GB', 'Kabel Data Type-C']);
    expect(parsed.items.map((i) => i.price).toList(), [299000, 89000, 49000]);
  });

  test('qty x harga satuan terbaca', () {
    final parsed = ReceiptParser.parse('TOKO MAJU\n1. Sabun Mandi 2 5.000 10.000\n'
        '2. Pasta Gigi 1 12.000 12.000\nTOTAL 22.000');
    expect(parsed.items.first.name, 'Sabun Mandi');
    expect(parsed.items.first.quantity, 2);
    expect(parsed.items.first.unitPrice, 5000);
  });

  test('qty di depan nama tidak dianggap nomor urut', () {
    final parsed =
        ReceiptParser.parse('WARUNG BU SRI\n2 INDOMIE GORENG 7.000\n4 TELUR AYAM 10.000\nTOTAL 17.000');
    expect(parsed.items.map((i) => i.name).toList(), ['2 INDOMIE GORENG', '4 TELUR AYAM']);
  });
}
