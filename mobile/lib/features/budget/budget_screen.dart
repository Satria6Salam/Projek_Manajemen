import '../../core/widgets/photo_card.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/constants/app_categories.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/state_views.dart';
import '../../models/user_model.dart';
import 'budget_service.dart';

Color budgetColor(BudgetLevel level) {
  switch (level) {
    case BudgetLevel.over:
      return AppColors.danger;
    case BudgetLevel.warning:
      return const Color(0xFFE59A00);
    case BudgetLevel.safe:
      return AppColors.successText;
    case BudgetLevel.none:
      return AppColors.textGrey;
  }
}

/// Halaman Anggaran: batas bulanan total & per kategori beserta pemakaiannya.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final BudgetService _service = BudgetService();
  late Future<BudgetSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.snapshot(widget.user.id, DateTime.now());
  }

  void _reload() => setState(
      () => _future = _service.snapshot(widget.user.id, DateTime.now()));

  Future<void> _edit(BudgetRow row) async {
    final ctl = TextEditingController(
        text: row.hasLimit ? Fmt.number(row.limit!.round()) : '');
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row.isTotal ? 'Batas total bulanan' : 'Batas ${row.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Terpakai bulan ini: ${Fmt.rupiah(row.spent.round())}',
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textGrey)),
            const SizedBox(height: 12),
            AppTextField(
              controller: ctl,
              label: 'Batas per bulan',
              prefixText: 'Rp',
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
            ),
            const SizedBox(height: 6),
            const Text('Kosongkan untuk menghapus batas.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGrey)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, Fmt.parseAmount(ctl.text) ?? 0),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (result == null) return;
    await _service.setLimit(widget.user.id,
        row.isTotal ? BudgetService.totalKey : row.name, result);
    _reload();
    AppState.dataVersion.value++; // segarkan peringatan anggaran di Beranda
    await _service.checkAndNotify(widget.user.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anggaran Bulanan')),
      body: FutureBuilder<BudgetSnapshot>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return Center(
                child: ErrorState(message: '${snap.error}', onRetry: _reload));
          }
          final s = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                  'Batas pengeluaran ${Fmt.monthYear(s.month)}. Anda akan diberi peringatan '
                  'saat pemakaian mencapai 80% dan 100%.',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textGrey, height: 1.4)),
              const SizedBox(height: 16),
              BudgetTile(
                  row: s.total, onTap: () => _edit(s.total), highlighted: true),
              const SizedBox(height: 18),
              const Text('Per kategori',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
              const SizedBox(height: 10),
              for (final row in s.rows)
                BudgetTile(row: row, onTap: () => _edit(row)),
            ],
          );
        },
      ),
    );
  }
}

/// Satu baris anggaran dengan bilah pemakaian.
class BudgetTile extends StatelessWidget {
  const BudgetTile(
      {super.key, required this.row, this.onTap, this.highlighted = false});

  final BudgetRow row;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final levelColor = budgetColor(row.level);
    final accent =
        row.isTotal ? AppColors.primary : AppCategories.colorOf(row.name);
    final String status;
    switch (row.level) {
      case BudgetLevel.none:
        status = 'Belum ada batas \u00B7 ketuk untuk mengatur';
      case BudgetLevel.over:
        status = 'Lewat ${Fmt.rupiah((-row.remaining).round())}';
      case BudgetLevel.warning:
      case BudgetLevel.safe:
        status = 'Sisa ${Fmt.rupiah(row.remaining.round())}';
    }
    final barColor = switch (row.level) {
      BudgetLevel.over => const Color(0xFFFF6B6B),
      BudgetLevel.warning => const Color(0xFFFBBF24),
      _ => const Color(0xFF4ADE80),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PhotoCard(
        photo: row.isTotal
            ? 'assets/images/feat_budget.jpg'
            : categoryPhoto(row.name),
        color: row.level == BudgetLevel.over ? levelColor : accent,
        onTap: onTap,
        overlay: 0.92,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhotoIconBadge(
                  icon: row.isTotal
                      ? Icons.account_balance_wallet
                      : AppCategories.iconOf(row.name),
                  color: accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(row.isTotal ? 'Total semua kategori' : row.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 15)),
                ),
                const Icon(Icons.edit, size: 18, color: Colors.white70),
              ],
            ),
            SizedBox(height: highlighted ? 30 : 16),
            Text(
              row.hasLimit
                  ? '${Fmt.rupiah(row.spent.round())} / ${Fmt.rupiah(row.limit!.round())}'
                  : Fmt.rupiah(row.spent.round()),
              style: TextStyle(
                  fontSize: highlighted ? 20 : 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            if (row.hasLimit) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: row.ratio.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  color: barColor,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              row.hasLimit
                  ? '${(row.ratio * 100).round()}% terpakai \u00B7 $status'
                  : status,
              style: TextStyle(
                  fontSize: 11.5,
                  color: row.hasLimit ? barColor : const Color(0xFFE2E8F0),
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
