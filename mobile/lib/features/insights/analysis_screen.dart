import '../../core/widgets/photo_card.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/constants/app_categories.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/user_model.dart';
import '../export/export_service.dart';
import 'analysis_period.dart';
import 'bar_chart.dart';
import 'insight_service.dart';
import 'insights_section.dart';

/// Halaman Analisis lengkap: periode hari / bulan / tahun, grafik, persona,
/// temuan, saran per kategori, toko favorit, serta tren bulanan & tahunan.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.user, this.initialMonth});

  final UserModel user;
  final DateTime? initialMonth;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisData {
  const _AnalysisData({
    required this.analytics,
    required this.trends,
    required this.current,
  });

  final SpendingAnalytics analytics;
  final TrendAnalytics trends;
  final PeriodData current;
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late AnalysisPeriod _period;
  late Future<_AnalysisData> _future;

  @override
  void initState() {
    super.initState();
    final DateTime m = widget.initialMonth ?? DateTime.now();
    _period = AnalysisPeriod.month(m.year, m.month);
    _future = _load();
    AppState.dataVersion.addListener(_reload);
  }

  @override
  void dispose() {
    AppState.dataVersion.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() => _future = _load());

  void _setPeriod(AnalysisPeriod p) => setState(() {
        _period = p;
        _future = _load();
      });

  Future<_AnalysisData> _load() async {
    final repo = AppRepositories.instance.receipts;
    final int userId = widget.user.id;
    final AnalysisPeriod period = _period;
    final int year = period.start.year;
    final results = await Future.wait<Object>([
      repo.getPeriodData(userId, period.start, period.endExclusive),
      repo.getPeriodData(
          userId, period.previous.start, period.previous.endExclusive),
      repo.getMonthlyTotals(userId, year),
      repo.getMonthlyTotals(userId, year - 1),
      repo.getYearlyTotals(userId),
    ]);
    final current = results[0] as PeriodData;
    final previous = results[1] as PeriodData;
    const service = InsightService();
    final now = DateTime.now();
    return _AnalysisData(
      current: current,
      analytics: service.analyzePeriod(
        period: period,
        now: now,
        receipts: current.receipts,
        previousReceipts: previous.receipts,
        categories: current.categoryTotals,
      ),
      trends: service.analyzeTrends(
        year: year,
        now: now,
        monthlyTotals: results[2] as List<double>,
        previousYearMonthlyTotals: results[3] as List<double>,
        yearlyTotals: results[4] as Map<int, double>,
      ),
    );
  }

  String get _periodLabel {
    switch (_period.mode) {
      case PeriodMode.day:
        return Fmt.longDate(_period.start);
      case PeriodMode.month:
        return Fmt.monthYear(_period.start);
      case PeriodMode.year:
        return 'Tahun ${_period.start.year}';
    }
  }

  String get _previousLabel {
    switch (_period.mode) {
      case PeriodMode.day:
        return 'vs kemarin';
      case PeriodMode.month:
        return 'vs bulan lalu';
      case PeriodMode.year:
        return 'vs tahun lalu';
    }
  }

  /// Ekspor bulan dari periode yang sedang dilihat ke CSV lalu bagikan.
  Future<void> _export() async {
    final month = DateTime(
        _period.start.year,
        _period.mode == PeriodMode.year
            ? DateTime.now().month
            : _period.start.month);
    try {
      final count =
          await const ExportService().shareMonth(widget.user.id, month);
      if (mounted && count == 0) {
        showAppSnackBar(
            context, 'Belum ada struk pada ${Fmt.monthYear(month)}.');
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, 'Ekspor gagal: $e', error: true);
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _period.start.isAfter(now) ? now : _period.start,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Pilih tanggal',
    );
    if (picked != null) _setPeriod(AnalysisPeriod.day(picked));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analisis Pengeluaran'),
        actions: [
          IconButton(
            tooltip: 'Ekspor laporan bulan ini (CSV)',
            icon: const Icon(Icons.ios_share),
            onPressed: _export,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<PeriodMode>(
              segments: const [
                ButtonSegment(value: PeriodMode.day, label: Text('Hari')),
                ButtonSegment(value: PeriodMode.month, label: Text('Bulan')),
                ButtonSegment(value: PeriodMode.year, label: Text('Tahun')),
              ],
              selected: {_period.mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                final DateTime ref =
                    _period.isCurrent(now) ? now : _period.start;
                _setPeriod(AnalysisPeriod.containing(s.first, ref));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Periode sebelumnya',
                  onPressed: () => _setPeriod(_period.previous),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _period.mode == PeriodMode.day ? _pickDay : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_periodLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy)),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Periode berikutnya',
                  onPressed: _period.canGoNext(now)
                      ? () => _setPeriod(_period.next)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<_AnalysisData>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError || snap.data == null) {
                  return Center(
                    child:
                        ErrorState(message: '${snap.error}', onRetry: _reload),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: _buildBody(snap.data!),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _buildBody(_AnalysisData data) {
    final SpendingAnalytics a = data.analytics;
    final TrendAnalytics t = data.trends;
    final double? change = a.changePercent;
    final int year = _period.start.year;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        // Ringkasan.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total pengeluaran',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(Fmt.rupiah(a.total.round()),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              Text(
                '${a.transactionCount} struk'
                '${change == null ? '' : ' · ${change >= 0 ? '+' : '-'}${change.abs().round()}% $_previousLabel'}',
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (_period.mode != PeriodMode.day && a.hasData) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _MiniStat(
                      'Rata-rata / hari', Fmt.rupiah(a.averagePerDay.round()))),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  a.isCurrentMonth ? 'Proyeksi akhir periode' : 'Total periode',
                  Fmt.rupiah(a.projectedTotal.round()),
                ),
              ),
            ],
          ),
        ],

        // Grafik periode.
        if (_period.mode == PeriodMode.month && a.dailyTotals.isNotEmpty) ...[
          _section('Pengeluaran harian'),
          SimpleBarChart(
            values: a.dailyTotals,
            labels: [for (int d = 1; d <= a.dailyTotals.length; d++) '$d'],
            showEveryNthLabel: 5,
            highlightIndex: a.isCurrentMonth ? a.daysElapsed - 1 : null,
          ),
        ],
        if (_period.mode == PeriodMode.day) ...[
          _section('Struk hari ini'),
          if (data.current.receipts.isEmpty)
            const Text('Belum ada struk pada tanggal ini.',
                style: TextStyle(color: AppColors.textGrey))
          else
            for (final r in data.current.receipts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.receipt_long_outlined,
                    color: AppColors.primary),
                title: Text(r.merchantName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.navy)),
                subtitle: Text(
                    '${r.transactionDate.hour.toString().padLeft(2, '0')}:${r.transactionDate.minute.toString().padLeft(2, '0')}'),
                trailing: Text(Fmt.rupiah(r.totalAmount),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.navy)),
              ),
        ],

        if (a.hasData) ...[
          // Persona & temuan.
          _section('Analisis & rekomendasi'),
          if (a.persona != null) ...[
            PersonaCard(persona: a.persona!),
            const SizedBox(height: 10),
          ],
          for (final Insight i in a.insights)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InsightCard(insight: i)),

          // Kategori.
          if (a.categoryAdvice.isNotEmpty) ...[
            _section('Pengeluaran per kategori'),
            for (final CategoryAdvice c in a.categoryAdvice)
              _CategoryAdviceTile(advice: c),
          ],

          // Toko favorit.
          if (a.topMerchants.isNotEmpty) ...[
            _section('Toko favorit'),
            for (int i = 0; i < a.topMerchants.length; i++)
              _MerchantTile(rank: i + 1, merchant: a.topMerchants[i]),
          ],
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyState(
              title: 'Belum ada pengeluaran',
              message:
                  'Tidak ada struk pada periode ini. Pilih periode lain atau pindai struk baru.',
            ),
          ),

        // Tren bulanan & tahunan.
        _section('Tren bulanan $year'),
        SimpleBarChart(
          values: t.monthlyTotals,
          labels: const [
            'J',
            'F',
            'M',
            'A',
            'M',
            'J',
            'J',
            'A',
            'S',
            'O',
            'N',
            'D'
          ],
          highlightIndex:
              _period.mode == PeriodMode.year ? null : _period.start.month - 1,
        ),
        if (t.activeMonths > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Rata-rata ${Fmt.rupiah(t.monthlyAverage.round())} per bulan dari ${t.activeMonths} bulan tercatat.',
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
          ),
        if (t.yearlyTotals.length >= 2) ...[
          _section('Tren tahunan'),
          SimpleBarChart(
            values: t.yearlyTotals.values.toList(),
            labels: [for (final y in t.yearlyTotals.keys) '$y'],
            highlightIndex: t.yearlyTotals.keys.toList().indexOf(year),
            height: 110,
          ),
        ],
        const SizedBox(height: 12),
        for (final Insight i in t.insights)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InsightCard(insight: i)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy)),
          ),
        ],
      ),
    );
  }
}

class _CategoryAdviceTile extends StatelessWidget {
  const _CategoryAdviceTile({required this.advice});

  final CategoryAdvice advice;

  @override
  Widget build(BuildContext context) {
    final Color color = AppCategories.colorOf(advice.categoryName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PhotoCard(
        photo: categoryPhoto(advice.categoryName),
        color: color,
        overlay: 0.92,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhotoIconBadge(
                    icon: AppCategories.iconOf(advice.categoryName),
                    color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(advice.categoryName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 15)),
                ),
                Text('${advice.sharePercent.round()}%',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFE2E8F0))),
              ],
            ),
            const SizedBox(height: 18),
            Text(Fmt.rupiah(advice.total.round()),
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 18)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (advice.sharePercent / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(advice.tip,
                style: const TextStyle(
                    fontSize: 12, color: Colors.white, height: 1.35)),
          ],
        ),
      ),
    );
  }
}

class _MerchantTile extends StatelessWidget {
  const _MerchantTile({required this.rank, required this.merchant});

  final int rank;
  final MerchantStat merchant;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: AppColors.primarySoft,
        child: Text('$rank',
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.primary)),
      ),
      title: Text(merchant.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.navy)),
      subtitle: Text('${merchant.visits}x belanja'),
      trailing: Text(Fmt.rupiah(merchant.total.round()),
          style: const TextStyle(
              fontWeight: FontWeight.w800, color: AppColors.navy)),
    );
  }
}
