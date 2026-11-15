import '../../core/widgets/photo_card.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_categories.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/dashboard_model.dart';
import '../../models/receipt_model.dart';
import '../../models/user_model.dart';
import '../budget/budget_screen.dart';
import '../budget/budget_service.dart';
import 'analysis_screen.dart';
import 'insight_service.dart';

/// Memuat struk bulan terpilih + bulan sebelumnya lalu menganalisisnya.
Future<SpendingAnalytics> loadSpendingAnalytics(
    int userId, DashboardModel data) async {
  final repo = AppRepositories.instance.receipts;
  final DateTime month = DateTime(data.month.year, data.month.month);
  final DateTime previous = DateTime(month.year, month.month - 1);
  final List<List<ReceiptModel>> lists =
      await Future.wait(<Future<List<ReceiptModel>>>[
    repo.getReceiptSummaries(userId, month: month),
    repo.getReceiptSummaries(userId, month: previous),
  ]);
  return const InsightService().analyzeMonth(
    month: month,
    now: DateTime.now(),
    receipts: lists[0],
    previousReceipts: lists[1],
    categories: data.categoryTotals,
  );
}

/// Bagian "Analisis & Rekomendasi" di Beranda: persona + temuan + saran.
class InsightsSection extends StatefulWidget {
  const InsightsSection({super.key, required this.user, required this.data});

  final UserModel user;
  final DashboardModel data;

  int get userId => user.id;

  @override
  State<InsightsSection> createState() => _InsightsSectionState();
}

class _InsightsSectionState extends State<InsightsSection> {
  late Future<SpendingAnalytics> _future;
  late Future<BudgetSnapshot?> _budget;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = loadSpendingAnalytics(widget.userId, widget.data);
    final now = DateTime.now();
    final m = widget.data.month;
    // Peringatan anggaran hanya untuk bulan berjalan.
    _budget = (m.year == now.year && m.month == now.month)
        ? BudgetService()
            .snapshot(widget.userId, now)
            .then<BudgetSnapshot?>((s) => s, onError: (_) => null)
        : Future<BudgetSnapshot?>.value(null);
  }

  @override
  void didUpdateWidget(covariant InsightsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _load();
  }

  void _openAnalysis() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          AnalysisScreen(user: widget.user, initialMonth: widget.data.month)));

  void _openBudget() => Navigator.of(context)
          .push(MaterialPageRoute<void>(
              builder: (_) => BudgetScreen(user: widget.user)))
          .then((_) {
        if (mounted) setState(_load);
      });

  Widget _budgetAlerts() {
    return FutureBuilder<BudgetSnapshot?>(
      future: _budget,
      builder: (context, snap) {
        final alerts = snap.data?.alerts ?? const <BudgetRow>[];
        if (alerts.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: _openBudget,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                for (final row in alerts.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InsightCard(
                      insight: Insight(
                        kind: InsightKind.warning,
                        title: row.ratio >= 1
                            ? '${row.isTotal ? 'Anggaran total' : 'Anggaran ${row.name}'} terlampaui'
                            : '${row.isTotal ? 'Anggaran total' : 'Anggaran ${row.name}'} ${(row.ratio * 100).round()}% terpakai',
                        message: '${Fmt.rupiah(row.spent.round())} dari batas '
                            '${Fmt.rupiah(row.limit!.round())}. Ketuk untuk melihat anggaran.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpendingAnalytics>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final SpendingAnalytics? a = snapshot.data;
        if (snapshot.hasError || a == null || !a.hasData) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              'Analisis & rekomendasi',
              trailing: InkWell(
                onTap: _openAnalysis,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Lihat lengkap',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _budgetAlerts(),
            if (a.persona != null) ...[
              PersonaCard(persona: a.persona!),
              const SizedBox(height: 10),
            ],
            _StatsRow(analytics: a),
            const SizedBox(height: 10),
            for (final Insight i in a.insights.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InsightCard(insight: i),
              ),
            if (a.topMerchants.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Toko favorit',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
              const SizedBox(height: 6),
              for (final m in a.topMerchants.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.storefront_outlined,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${m.name} · ${m.visits}x',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.navy)),
                      ),
                      Text(Fmt.rupiah(m.total.round()),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openAnalysis,
                icon: const Icon(Icons.insights_outlined),
                label: const Text('Analisis hari / bulan / tahun & tren'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PersonaCard extends StatelessWidget {
  const PersonaCard({super.key, required this.persona});

  final SpendingPersona persona;

  @override
  Widget build(BuildContext context) {
    final String? category = persona.categoryName;
    final Color color =
        category == null ? AppColors.primary : AppCategories.colorOf(category);
    return PhotoCard(
      photo: category == null
          ? 'assets/images/feat_analysis.jpg'
          : categoryPhoto(category),
      color: color,
      overlay: 0.92,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhotoIconBadge(
                icon: category == null
                    ? Icons.balance
                    : AppCategories.iconOf(category),
                color: color,
                size: 40,
              ),
              const SizedBox(width: 10),
              const Text('Tipe pengeluaran Anda',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE2E8F0))),
            ],
          ),
          const SizedBox(height: 26),
          Text(persona.title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          if (category != null)
            Text('${persona.sharePercent.round()}% untuk $category',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFDE68A))),
          const SizedBox(height: 6),
          Text(persona.description,
              style: const TextStyle(
                  fontSize: 12.5, color: Colors.white, height: 1.35)),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.analytics});

  final SpendingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final double? change = analytics.changePercent;
    return Row(
      children: [
        Expanded(
          child: _Stat(
            label: 'Rata-rata / hari',
            value: Fmt.rupiah(analytics.averagePerDay.round()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Stat(
            label: analytics.isCurrentMonth
                ? 'Proyeksi bulan ini'
                : 'Total bulan ini',
            value: Fmt.rupiah(analytics.projectedTotal.round()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Stat(
            label: 'vs bulan lalu',
            value: change == null
                ? '-'
                : '${change >= 0 ? '+' : '-'}${change.abs().round()}%',
            valueColor: change == null
                ? AppColors.navy
                : (change > 0 ? AppColors.danger : AppColors.successText),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.label,
      required this.value,
      this.valueColor = AppColors.navy});

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 10.5, color: AppColors.textGrey)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: valueColor)),
          ),
        ],
      ),
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    late final Color fg;
    late final IconData icon;
    switch (insight.kind) {
      case InsightKind.warning:
        fg = const Color(0xFFD97706);
        icon = Icons.trending_up_rounded;
      case InsightKind.positive:
        fg = const Color(0xFF16A34A);
        icon = Icons.thumb_up_alt_rounded;
      case InsightKind.info:
        fg = AppColors.primary;
        icon = Icons.insights_rounded;
      case InsightKind.tip:
        fg = const Color(0xFF7C3AED);
        icon = Icons.lightbulb_rounded;
    }
    return SoftCard(
      radius: 16,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: fg,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 19, color: fg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(insight.title,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: fg)),
                          const SizedBox(height: 3),
                          Text(insight.message,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.navy,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
