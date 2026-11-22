import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/core/utils/receipt_parser.dart';

/// Regresi format struk berbeda & salah baca OCR (sama dengan tes backend).
void main() {
  test('format Alfamart: nama lalu baris qty x harga, ribuan koma', () {
    final r = ReceiptParser.parse('ALFAMART\nJL. SOEKARNO HATTA NO.9 MALANG\n'
        'TEH BTL SOSRO 450ML\n2 x 5,200 10,400\n'
        'ABC SMBL ASLI 335\n2 xX 12,700 25,400\n'
        'TOTAL BELANJA 35,800\nTUNAI 50,000');
    expect(r.items.map((i) => i.name).toList(),
        ['TEH BTL SOSRO 450ML', 'ABC SMBL ASLI 335']);
    expect(r.items.map((i) => i.quantity).toList(), [2, 2]);
    expect(r.items.map((i) => i.price).toList(), [10400, 25400]);
    expect(r.totalAmount, 35800);
  });

  test('format "Rp x = Rp"', () {
    final r = ReceiptParser.parse('TOKO BERKAH JAYA\nKecap Bango 520ml\n'
        '1 pcs x Rp 24.800 = Rp 24.800\nKopi Kapal Api 165g\n'
        '2 pcs x Rp 13.000 = Rp 26.000\nTotal : Rp 50.800');
    expect(r.items.map((i) => i.name).toList(),
        ['Kecap Bango 520ml', 'Kopi Kapal Api 165g']);
    expect(r.items.map((i) => i.quantity).toList(), [1, 2]);
    expect(r.items.map((i) => i.price).toList(), [24800, 26000]);
  });

  test('qty di depan nama (kafe)', () {
    final r = ReceiptParser.parse(
        'KOPI SENJA\n2 Air Mineral 16.000\n1 Americano 22.000\nTotal 38.000');
    expect(r.items.map((i) => i.name).toList(), ['Air Mineral', 'Americano']);
    expect(r.items.map((i) => i.quantity).toList(), [2, 1]);
  });

  test('angka terpecah spasi & huruf mirip angka', () {
    expect(ReceiptParser.normalizeLine('TOTAL 84, 300'), 'TOTAL 84,300');
    expect(ReceiptParser.normalizeLine('Antangin 3 4.000,00 12.000, 00'),
        'Antangin 3 4.000,00 12.000,00');
    expect(ReceiptParser.normalizeLine('Telp. (@341) 58O123'),
        'Telp. (0341) 580123');
  });

  test('harga salah baca 1 digit dikoreksi oleh qty x harga', () {
    final r = ReceiptParser.parse(
        'No Nama Barang Qty Harga Jumlah\n1 Beras 5kg 1 62.500 62.509\nTotal 62.500');
    expect(r.items.single.price, 62500);
  });

  test('satu harga salah baca dikoreksi oleh total', () {
    final r = ReceiptParser.parse(
        'TOKO A\nGula 1kg 16.000\nRoti Tawar 13.000\nTotal 34.000');
    expect(r.items.map((i) => i.price).toList(), [16000, 18000]);
  });

  test('total salah baca dikoreksi bila barang konsisten', () {
    final r = ReceiptParser.parse(
        'APOTEK\nParacetamol 500mg 1 5.000,00 5.000,00\n'
        'Vitamin C 1000mg 1 35.000,00 35.000,00\nTOTAL 49.000,00\nTUNAI 40.000,00');
    expect(r.totalAmount, 40000);
  });

  test('format "1 x Nama" dan kolom qty di depan (struk Indomaret)', () {
    final r = ReceiptParser.parse('Indomaret\n1 x Air Mineral 600m1 Rp 3.000\n'
        '1x Roti Tawar Rp 7.500\nTotal Belanja : Rp 10.500');
    expect(r.items.map((i) => i.name).toList(),
        ['Air Mineral 600ml', 'Roti Tawar']);
    final q = ReceiptParser.parse('Qty Nama Barang Harga Total\n'
        '1 Air Mineral 600ml 3.000 3.000\n2 Roti Cokelat 6.500 13.000\n'
        'Total Belanja : 16.000');
    expect(q.items.map((i) => i.name).toList(),
        ['Air Mineral 600ml', 'Roti Cokelat']);
    expect(q.items.map((i) => i.quantity).toList(), [1, 2]);
  });

  test('kode PLU di depan nama dibuang (supermarket)', () {
    final r = ReceiptParser.parse('SUPERINDO\n8994330348 TEH BTL SOSRO 450ML\n'
        '1 @ 5,200 5,200\nTOTAL 5,200');
    expect(r.items.single.name, 'TEH BTL SOSRO 450ML');
  });

  test('harga yang dikoreksi otomatis diberi tanda', () {
    final r = ReceiptParser.parse(
        'TOKO A\nGula 1kg 16.000\nRoti Tawar 13.000\nTotal 34.000');
    expect(r.items.map((i) => i.priceCorrected).toList(), [false, true]);
  });
}
