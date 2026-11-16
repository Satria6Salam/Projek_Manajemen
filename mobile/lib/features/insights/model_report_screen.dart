import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/model_report.dart';
import 'bar_chart.dart';

/// Kinerja model klasifikasi: akurasi menurut koreksi pengguna.
class ModelReportScreen extends StatefulWidget {
  const ModelReportScreen({super.key});

  @override
  State<ModelReportScreen> createState() => _ModelReportScreenState();
}

class _ModelReportScreenState extends State<ModelReportScreen> {
  late Future<ModelReport?> _future;

  @override
  void initState() {
    super.initState();
    _future = AppRepositories.instance.receipts.getModelReport();
  }

  void _reload() => setState(
      () => _future = AppRepositories.instance.receipts.getModelReport());

  Color _color(double? acc) {
    if (acc == null) return AppColors.textGrey;
    if (acc >= 85) return AppColors.successText;
    if (acc >= 65) return const Color(0xFFE59A00);
    return AppColors.danger;
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navy)),
      );

  Widget _accRow(AccuracyRow r) {
    final acc = r.accuracy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.navy)),
              ),
              Text('${r.items} barang  ',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textGrey)),
              Text(acc == null ? '-' : '${acc.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: _color(acc))),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (acc ?? 0) / 100,
              minHeight: 6,
              backgroundColor: AppColors.primarySoft,
              color: _color(acc),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kinerja Model')),
      body: FutureBuilder<ModelReport?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: ErrorState(message: '${snap.error}', onRetry: _reload));
          }
          final r = snap.data;
          if (r == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                title: 'Hanya tersedia di mode server',
                message:
                    'Evaluasi model memakai data prediksi dari backend STRUKKU.',
              ),
            );
          }
          if (r.totalItems == 0) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                title: 'Belum ada data',
                message:
                    'Pindai dan simpan beberapa struk. Akurasi dihitung dari kategori '
                    'otomatis yang Anda biarkan (benar) atau koreksi (salah).',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Akurasi kategori otomatis',
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.textGrey)),
                      Text(
                          r.accuracy == null
                              ? '-'
                              : '${r.accuracy!.toStringAsFixed(1)}%',
                          style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: _color(r.accuracy))),
                      Text(
                          '${r.totalItems - r.correctedItems} dari ${r.totalItems} barang tidak '
                          'perlu dikoreksi · ${r.correctedItems} dikoreksi',
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.navy)),
                      const SizedBox(height: 8),
                      Text(
                        'Model telah mempelajari ${r.learnedCorrections} koreksi '
                        '(${Fmt.number(r.trainingSamples)} contoh latih)'
                        '${r.trainedAt == null ? '' : ', dilatih ${Fmt.shortDate(r.trainedAt!)}'}.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textGrey),
                      ),
                    ],
                  ),
                ),
                _title('Tren akurasi per bulan'),
                SimpleBarChart(
                  values: [for (final m in r.monthly) m.accuracy ?? 0],
                  labels: [
                    for (final m in r.monthly)
                      m.label.split(' ').first.substring(0, 3)
                  ],
                  height: 110,
                  format: (v) => '${v.round()}%',
                ),
                _title('Per kategori prediksi'),
                for (final c in r.categories) _accRow(c),
                _title('Per sumber prediksi'),
                for (final s in r.sources) _accRow(s),
                if (r.topCorrections.isNotEmpty) ...[
                  _title('Barang yang paling sering dikoreksi'),
                  for (final c in r.topCorrections)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading:
                          const Icon(Icons.edit_note, color: AppColors.primary),
                      title: Text(c.itemName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy)),
                      subtitle: Text('${c.predicted} → ${c.correctedTo}'),
                      trailing: Text('${c.count}x'),
                    ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Koreksi Anda otomatis menjadi data latih: model dilatih ulang di server '
                  'sehingga barang serupa berikutnya ikut terklasifikasi benar.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textGrey, height: 1.4),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
