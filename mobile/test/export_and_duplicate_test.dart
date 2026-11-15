import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/features/export/export_service.dart';
import 'package:strukku/models/model_report.dart';
import 'package:strukku/models/receipt_item_model.dart';
import 'package:strukku/models/receipt_model.dart';

void main() {
  test('CSV berisi baris per barang, kutip untuk ; dan ringkasan kategori', () {
    final csv = const ExportService().buildCsv([
      ReceiptModel(
        userId: 1,
        merchantName: 'Toko; Maju',
        transactionDate: DateTime(2026, 11, 3, 9, 5),
        totalAmount: 30000,
        createdAt: DateTime(2026, 11, 3),
        items: const [
          ReceiptItemModel(categoryId: 1, categoryName: 'Makanan', itemName: 'Roti', itemPrice: 20000, quantity: 2),
          ReceiptItemModel(categoryId: 2, categoryName: 'Minuman', itemName: 'Teh', itemPrice: 10000, isUserCorrected: true),
        ],
      ),
    ]);
    final lines = csv.split('\r\n');
    expect(lines.first, startsWith('Tanggal;Jam;Toko'));
    expect(lines[1], '2026-11-03;09:05;"Toko; Maju";30000;Roti;2;20000;Makanan;');
    expect(lines[2], endsWith('Teh;1;10000;Minuman;ya'));
    expect(csv, contains('Makanan;20000'));
    expect(csv, contains('Total semua struk;30000'));
  });

  test('ModelReport membaca JSON evaluasi model', () {
    final r = ModelReport.fromJson({
      'total_items': 4,
      'corrected_items': 1,
      'accuracy': 75.0,
      'categories': [
        {'category': 'Makanan', 'items': 4, 'corrected': 1, 'accuracy': 75.0}
      ],
      'sources': [
        {'source': 'id_model', 'label': 'Model Indonesia', 'items': 4, 'accuracy': 75.0}
      ],
      'top_corrections': [
        {'item_name': 'TEH X', 'predicted': 'Makanan', 'corrected_to': 'Minuman', 'count': 1}
      ],
      'monthly': [
        {'month': '2026-11', 'month_label': 'November 2026', 'items': 4, 'accuracy': 75.0}
      ],
      'learned_corrections': 3,
      'training_samples': 10000,
      'trained_at': '2026-11-15T10:00:00',
    });
    expect(r.accuracy, 75);
    expect(r.topCorrections.single.correctedTo, 'Minuman');
    expect(r.learnedCorrections, 3);
    expect(r.trainedAt, DateTime(2026, 11, 15, 10));
  });
}
