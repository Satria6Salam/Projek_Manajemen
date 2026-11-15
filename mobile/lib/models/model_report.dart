/// Kinerja prediksi kategori (GET /analytics/model).
class ModelReport {
  const ModelReport({
    required this.totalItems,
    required this.correctedItems,
    required this.accuracy,
    required this.categories,
    required this.sources,
    required this.topCorrections,
    required this.monthly,
    required this.learnedCorrections,
    required this.trainingSamples,
    this.trainedAt,
  });

  final int totalItems;
  final int correctedItems;
  final double? accuracy;
  final List<AccuracyRow> categories;
  final List<AccuracyRow> sources;
  final List<CorrectionRow> topCorrections;
  final List<AccuracyRow> monthly;
  final int learnedCorrections;
  final int trainingSamples;
  final DateTime? trainedAt;

  factory ModelReport.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) =>
        (j[k] as List? ?? const []).cast<Map<String, dynamic>>();
    return ModelReport(
      totalItems: (j['total_items'] as num? ?? 0).toInt(),
      correctedItems: (j['corrected_items'] as num? ?? 0).toInt(),
      accuracy: (j['accuracy'] as num?)?.toDouble(),
      categories: list('categories')
          .map((c) => AccuracyRow(
                label: c['category'] as String,
                items: (c['items'] as num).toInt(),
                accuracy: (c['accuracy'] as num?)?.toDouble(),
              ))
          .toList(),
      sources: list('sources')
          .map((c) => AccuracyRow(
                label: c['label'] as String,
                items: (c['items'] as num).toInt(),
                accuracy: (c['accuracy'] as num?)?.toDouble(),
              ))
          .toList(),
      topCorrections: list('top_corrections')
          .map((c) => CorrectionRow(
                itemName: c['item_name'] as String,
                predicted: c['predicted'] as String,
                correctedTo: c['corrected_to'] as String,
                count: (c['count'] as num).toInt(),
              ))
          .toList(),
      monthly: list('monthly')
          .map((c) => AccuracyRow(
                label: c['month_label'] as String,
                items: (c['items'] as num).toInt(),
                accuracy: (c['accuracy'] as num?)?.toDouble(),
              ))
          .toList(),
      learnedCorrections: (j['learned_corrections'] as num? ?? 0).toInt(),
      trainingSamples: (j['training_samples'] as num? ?? 0).toInt(),
      trainedAt: j['trained_at'] == null
          ? null
          : DateTime.tryParse('${j['trained_at']}'),
    );
  }
}

class AccuracyRow {
  const AccuracyRow({required this.label, required this.items, this.accuracy});

  final String label;
  final int items;

  /// 0-100, null bila belum ada data.
  final double? accuracy;
}

class CorrectionRow {
  const CorrectionRow({
    required this.itemName,
    required this.predicted,
    required this.correctedTo,
    required this.count,
  });

  final String itemName;
  final String predicted;
  final String correctedTo;
  final int count;
}
