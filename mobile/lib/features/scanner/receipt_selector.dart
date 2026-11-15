import '../../core/utils/receipt_parser.dart';

/// Satu hasil baca struk: teks OCR beserta hasil parsing-nya.
class ReceiptReading {
  const ReceiptReading({
    required this.rawText,
    required this.parsed,
    this.fromEnhancedImage = false,
  });

  final String rawText;
  final ParsedReceipt parsed;

  /// True bila teks dibaca dari foto yang sudah diperjelas.
  final bool fromEnhancedImage;
}

/// Menilai hasil baca struk dan memilih yang terbaik di antara hasil dari
/// foto asli dan foto yang sudah diperjelas (diadaptasi dari smart_receipt_v2).
class ReceiptSelector {
  const ReceiptSelector();

  /// Toleransi selisih jumlah harga barang terhadap total struk.
  static const double _sumTolerance = 0.01;
  static const int _maxScoredItems = 20;
  static final RegExp _alphanumeric = RegExp(r'[A-Za-z0-9]');

  static double itemsTotal(ParsedReceipt parsed) =>
      parsed.items.fold<double>(0, (double s, ParsedItem i) => s + i.price);

  /// True bila jumlah harga barang sama dengan total struk.
  bool isConsistent(ParsedReceipt parsed) {
    final double? total = parsed.totalAmount;
    if (total == null || total <= 0 || parsed.items.isEmpty) return false;
    return (itemsTotal(parsed) - total).abs() <= total * _sumTolerance;
  }

  /// True bila semua data utama terbaca dan saling cocok, sehingga foto
  /// tidak perlu diperjelas lalu dibaca ulang.
  bool isComplete(ParsedReceipt parsed) =>
      parsed.merchantName != null &&
      parsed.transactionDate != null &&
      isConsistent(parsed);

  /// Makin tinggi makin lengkap dan makin dapat dipercaya.
  double score(ReceiptReading reading) {
    final ParsedReceipt parsed = reading.parsed;
    final int items = parsed.items.length > _maxScoredItems
        ? _maxScoredItems
        : parsed.items.length;
    double value = items * 3.0;
    if (parsed.totalAmount != null) value += 4;
    if (parsed.transactionDate != null) value += 2;
    if (parsed.merchantName != null) value += 1;
    if (isConsistent(parsed)) value += 6;
    final int characters = _alphanumeric.allMatches(reading.rawText).length;
    value += characters >= 200 ? 5 : characters / 40;
    return value;
  }

  /// Memilih bacaan dengan nilai tertinggi (foto asli menang bila seri),
  /// lalu melengkapi data utama yang kosong dari bacaan lainnya.
  ReceiptReading choose(ReceiptReading original, ReceiptReading? enhanced) {
    if (enhanced == null) return original;
    final bool useEnhanced = score(enhanced) > score(original);
    final ReceiptReading best = useEnhanced ? enhanced : original;
    final ReceiptReading other = useEnhanced ? original : enhanced;

    final ParsedReceipt a = best.parsed;
    final ParsedReceipt b = other.parsed;
    return ReceiptReading(
      rawText: best.rawText,
      parsed: ParsedReceipt(
        merchantName: a.merchantName ?? b.merchantName,
        merchantAddress: a.merchantAddress ?? b.merchantAddress,
        transactionDate: a.transactionDate ?? b.transactionDate,
        totalAmount: a.totalAmount ?? b.totalAmount,
        items: a.items.isNotEmpty ? a.items : b.items,
      ),
      fromEnhancedImage: best.fromEnhancedImage,
    );
  }
}
