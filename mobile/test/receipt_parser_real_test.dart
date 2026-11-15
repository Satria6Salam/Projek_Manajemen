import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/core/utils/receipt_parser.dart';

const freshmart = '''FreshMart
Jl. Melati No. 12, Malang
Tanggal : 01 Oktober 2026
No Nama Barang Qty Harga Total
1 Beras 5kg 1 62.000 62.000
2 Minyak Goreng 1L 1 18.500 18.500
5 Mie Instan (isi 5) il 12.500 12.500
6 Susu UHT 1L 2 15.000 30.000
Subtotal : 123.000
Total 8 123.000''';

const sejahtera = '''Toko Sejahtera
Jl. Melati No. 12, Jakarta Selatan
5 Tepung Terigu 1 kg 1 Rp 12.500 Rp 12.500
Tanggal : 02-10-2025
No. Nama Barang Qty Harga Total
1 Beras 5 kg 1 Rp 62.000 Rp 62.000
2 Minyak Goreng 1 L 2 Rp 15.500 Rp 31.000
3 Telur Ayam 1 kg 1 Rp 28.000 Rp 28.000
4 Gula Pasir 1 kg 1 Rp 14.000 Rp 14.000
Subtotal Rp 147.500
Pajak (PPN 11%) Rp 16.225
Total Rp 163.725''';

void main() {
  test('struk dengan kolom Total di judul tabel', () {
    final p = ReceiptParser.parse(freshmart);
    expect(p.items.map((i) => i.name).toList(),
        ['Beras 5kg', 'Minyak Goreng 1L', 'Mie Instan (isi 5)', 'Susu UHT 1L']);
    expect(p.totalAmount, 123000);
  });

  test('struk dengan "Rp" terpisah dan baris tidak berurutan', () {
    final p = ReceiptParser.parse(sejahtera);
    expect(p.items.map((i) => i.name).toList(),
        ['Tepung Terigu 1 kg', 'Beras 5 kg', 'Minyak Goreng 1 L', 'Telur Ayam 1 kg', 'Gula Pasir 1 kg']);
    expect(p.items.fold<double>(0, (s, i) => s + i.price), 147500);
    expect(p.totalAmount, 163725);
  });

  test('simbol sisa OCR dibuang dari nama toko', () {
    String m(String first) =>
        ReceiptParser.parse('$first\nBeras 5kg 62.000\nTotal 62.000').merchantName!;
    expect(m('] Toko Sejahtera'), 'Toko Sejahtera');
    expect(m('\u00a9EJ Toko Sejahtera'), 'Toko Sejahtera');
    expect(m('UD Sinar Jaya'), 'UD Sinar Jaya');
  });
}
