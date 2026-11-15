/// Riwayat harga satu barang (GET /items/price-history).
class PricePoint {
  const PricePoint({
    required this.itemName,
    required this.merchantName,
    required this.date,
    required this.quantity,
    required this.unitPrice,
  });

  final String itemName;
  final String merchantName;
  final DateTime? date;
  final int quantity;
  final double unitPrice;
}

class MerchantPrice {
  const MerchantPrice({
    required this.merchantName,
    required this.purchases,
    required this.lowest,
    required this.average,
    required this.latest,
  });

  final String merchantName;
  final int purchases;
  final double lowest;
  final double average;
  final double latest;
}

class PriceHistory {
  const PriceHistory(
      {required this.points, required this.merchants, this.cheapestMerchant});

  /// Terbaru lebih dulu.
  final List<PricePoint> points;

  /// Termurah (harga terakhir) lebih dulu.
  final List<MerchantPrice> merchants;
  final String? cheapestMerchant;

  bool get isEmpty => points.isEmpty;

  /// Ringkas titik harga menjadi perbandingan per toko (dipakai mode demo).
  factory PriceHistory.fromPoints(List<PricePoint> points) {
    final byStore = <String, List<double>>{};
    final names = <String, String>{};
    for (final p in points) {
      final key = p.merchantName.toUpperCase().trim();
      names.putIfAbsent(key, () => p.merchantName);
      byStore.putIfAbsent(key, () => []).add(p.unitPrice);
    }
    final merchants = [
      for (final e in byStore.entries)
        MerchantPrice(
          merchantName: names[e.key]!,
          purchases: e.value.length,
          lowest: e.value.reduce((a, b) => a < b ? a : b),
          average: e.value.reduce((a, b) => a + b) / e.value.length,
          latest: e.value.first,
        ),
    ]..sort((a, b) => a.latest.compareTo(b.latest));
    return PriceHistory(
      points: points,
      merchants: merchants,
      cheapestMerchant:
          merchants.length >= 2 ? merchants.first.merchantName : null,
    );
  }

  factory PriceHistory.fromJson(Map<String, dynamic> j) => PriceHistory(
        points: (j['points'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map((p) => PricePoint(
                  itemName: p['item_name'] as String,
                  merchantName:
                      (p['merchant_name'] as String?) ?? 'Tanpa nama toko',
                  date: DateTime.tryParse('${p['transaction_date']}'),
                  quantity: (p['quantity'] as num? ?? 1).toInt(),
                  unitPrice: (p['unit_price'] as num).toDouble(),
                ))
            .toList(),
        merchants: (j['merchants'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map((m) => MerchantPrice(
                  merchantName: m['merchant_name'] as String,
                  purchases: (m['purchases'] as num).toInt(),
                  lowest: (m['lowest'] as num).toDouble(),
                  average: (m['average'] as num).toDouble(),
                  latest: (m['latest'] as num).toDouble(),
                ))
            .toList(),
        cheapestMerchant: j['cheapest_merchant'] as String?,
      );
}
