import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/features/export/xlsx_report.dart';
import 'package:strukku/models/receipt_item_model.dart';
import 'package:strukku/models/receipt_model.dart';

void main() {
  test('laporan xlsx: kolom terpisah, total, dan ringkasan', () {
    final receipts = [
      ReceiptModel(
        userId: 1,
        merchantName: 'Toko Sejahtera',
        transactionDate: DateTime(2026, 10, 12, 14, 32),
        totalAmount: 133000,
        createdAt: DateTime(2026, 10, 12),
        items: const [
          ReceiptItemModel(categoryId: 1, categoryName: 'Makanan', itemName: 'Beras 5kg', itemPrice: 62000),
          ReceiptItemModel(categoryId: 1, categoryName: 'Makanan', itemName: 'Mie Instan', itemPrice: 12500, quantity: 5),
          ReceiptItemModel(categoryId: 2, categoryName: 'Minuman', itemName: 'Teh', itemPrice: 58500, isUserCorrected: true),
        ],
      ),
    ];
    final bytes = const XlsxReport().build(receipts, DateTime(2026, 10));
    final out = Platform.environment['XLSX_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);

    final x = Excel.decodeBytes(bytes);
    expect(x.tables.keys, containsAll(['Laporan', 'Ringkasan']));
    final s = x.tables['Laporan']!;
    String v(int c, int r) => '${s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value ?? ''}';
    expect(v(0, 3), 'No');
    expect(v(4, 3), 'Barang');
    expect(v(3, 4), 'Toko Sejahtera');
    expect(v(4, 5), 'Mie Instan');
    expect(v(6, 5), '5');
    expect(v(8, 6), 'Ya');
    expect(v(4, 7), 'TOTAL BARANG');
    expect(double.parse(v(7, 7)), 133000);
    final r = x.tables['Ringkasan']!;
    expect('${r.cell(CellIndex.indexByString('A4')).value}', 'Makanan');
    expect(double.parse('${r.cell(CellIndex.indexByString('B4')).value}'), 74500);
  });
}
