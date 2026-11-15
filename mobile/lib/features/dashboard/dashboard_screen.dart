import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/constants/app_categories.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/decorated_card.dart';
import '../../core/widgets/photo_card.dart';
import '../../core/widgets/receipt_tile.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/dashboard_model.dart';
import '../../models/receipt_model.dart';
import '../../models/user_model.dart';
import '../../core/utils/receipt_parser.dart';
import '../../navigation/app_router.dart';
import '../scanner/scan_result.dart';
import '../hub/quick_features.dart';
import '../insights/insights_section.dart';
import 'month_picker_sheet.dart';
import 'receipt_detail_sheet.dart';

/// Beranda: total pengeluaran, distribusi per kategori, struk terbaru.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.user, required this.onScan});

  final UserModel user;
  final VoidCallback onScan;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardModel? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppState.dataVersion.addListener(_load);
    AppState.selectedMonth.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.dataVersion.removeListener(_load);
    AppState.selectedMonth.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = AppRepositories.instance.receipts;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final month = AppState.selectedMonth.value ??
          await repo.latestMonthWithData(widget.user.id) ??
          DateTime.now();
      final data = await repo.getDashboard(widget.user.id, month);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickMonth() async {
    final data = _data;
    if (data == null) return;
    final months =
        await AppRepositories.instance.receipts.availableMonths(widget.user.id);
    if (!mounted) return;
    final picked =
        await showMonthPicker(context, months: months, selected: data.month);
    if (picked != null) AppState.selectedMonth.value = picked;
  }

  void _openReceipt(ReceiptModel r) {
    showReceiptDetailSheet(context, user: widget.user, receipt: r);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              if (_loading && _data == null)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _data == null)
                ErrorState(message: _error!, onRetry: _load)
              else if (_data != null)
                ..._buildContent(_data!),
            ],
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildScanBar()),
      ],
    );
  }

  Widget _buildHeader() {
    return DecoratedCard(
      dark: true,
      color: AppColors.navy,
      photo: 'assets/images/bg_header_grocery.jpg',
      icons: const [Icons.receipt_long_outlined, Icons.shopping_cart_outlined],
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 20, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Fmt.greeting(DateTime.now()),
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFFD7E4FF))),
                const SizedBox(height: 2),
                Text('${widget.user.fullName} \u{1F44B}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 4),
                const Text(
                    'Catat belanja dari struk, otomatis rapi per kategori.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFD7E4FF))),
              ],
            ),
          ),
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Text(widget.user.initial,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 17)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent(DashboardModel data) {
    final now = DateTime.now();
    final isCurrent =
        data.month.year == now.year && data.month.month == now.month;
    final sorted = [...data.categoryTotals]
      ..sort((a, b) => b.total.compareTo(a.total));

    return [
      _TotalCard(
        title: isCurrent
            ? 'Total pengeluaran bulan ini'
            : 'Total pengeluaran periode ini',
        data: data,
      ),
      const SizedBox(height: 22),
      const SectionTitle('Jelajahi fitur'),
      const SizedBox(height: 12),
      QuickFeatures(user: widget.user),
      const SizedBox(height: 10),
      SectionTitle(
        'Distribusi pengeluaran',
        trailing: InkWell(
          onTap: _pickMonth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                Text(Fmt.monthYear(data.month),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const Icon(Icons.expand_more,
                    size: 18, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (sorted.isEmpty)
        const EmptyState(
          title: 'Belum ada struk pada bulan ini',
          message: 'Pindai struk pertamamu dengan tombol kamera di bawah.',
        )
      else ...[
        SoftCard(
          child: Column(
            children: [
              _DistributionBar(totals: sorted),
              const SizedBox(height: 10),
              for (final c in sorted)
                _LegendRow(
                  name: c.categoryName,
                  amount: c.total,
                  fraction: data.fractionFor(c.categoryName),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final c = sorted[i];
              final color = AppCategories.colorOf(c.categoryName);
              return SizedBox(
                width: 150,
                child: PhotoCard(
                  photo: categoryPhoto(c.categoryName),
                  color: color,
                  radius: 18,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          PhotoIconBadge(
                              icon: AppCategories.iconOf(c.categoryName),
                              color: color,
                              size: 28),
                          const Spacer(),
                          Text(Fmt.percent(data.fractionFor(c.categoryName)),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const Spacer(),
                      Text(c.categoryName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFE2E8F0), fontSize: 11.5)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(Fmt.rupiah(c.total.round()),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
      if (sorted.isNotEmpty) ...[
        const SizedBox(height: 20),
        InsightsSection(user: widget.user, data: data),
      ],
      const SizedBox(height: 20),
      SectionTitle(
        'Struk terbaru',
        trailing: InkWell(
          onTap: () => Navigator.pushNamed(context, AppRoutes.receipts,
              arguments: widget.user),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Lihat semua',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (data.recentReceipts.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Belum ada struk tersimpan.',
              style: TextStyle(color: AppColors.textGrey)),
        )
      else
        for (final r in data.recentReceipts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ReceiptTile(receipt: r, onTap: () => _openReceipt(r)),
          ),
    ];
  }

  /// Pengeluaran tanpa struk (parkir, ojek, warung): formulir validasi kosong.
  Future<void> _openManualEntry() async {
    await Navigator.pushNamed(
      context,
      AppRoutes.validation,
      arguments: ValidationArgs(
        user: widget.user,
        scan: ScanResult(
          imagePath: null,
          rawText: '',
          parsed: ParsedReceipt(transactionDate: DateTime.now()),
          classification: null,
          isManual: true,
        ),
      ),
    );
  }

  Widget _buildScanBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Colors.white, Colors.white],
          stops: [0, 0.35, 1],
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Catat pengeluaran baru',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy)),
                SizedBox(height: 2),
                Text('Pindai struk, atau catat manual tanpa struk',
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.textGrey)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _openManualEntry,
              child: const Tooltip(
                message: 'Catat manual tanpa struk',
                child: SizedBox(
                  width: 50,
                  height: 58,
                  child:
                      Icon(Icons.edit_note, color: AppColors.primary, size: 26),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(18),
            elevation: 4,
            shadowColor: const Color(0x552160DD),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onScan,
              child: const SizedBox(
                width: 58,
                height: 58,
                child: Icon(Icons.photo_camera_outlined,
                    color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.title, required this.data});

  final String title;
  final DashboardModel data;

  @override
  Widget build(BuildContext context) {
    return DecoratedCard(
      dark: true,
      color: AppColors.primary,
      photo: 'assets/images/bg_total_vegetables.jpg',
      icons: const [Icons.payments_outlined, Icons.receipt_long_outlined],
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style:
                      const TextStyle(color: Color(0xFFD7E4FF), fontSize: 13)),
              const Icon(Icons.calendar_today_outlined,
                  color: Color(0xFFD7E4FF), size: 18),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(Fmt.rupiah(data.totalAmount),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(Fmt.monthYear(data.month),
                  style: const TextStyle(
                      color: Color(0xFFD7E4FF), fontSize: 12.5)),
              Text('${data.receiptCount} struk tersimpan',
                  style: const TextStyle(
                      color: Color(0xFFD7E4FF), fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grafik batang horizontal bersegmen; lebar tiap segmen sebanding nominal.
class _DistributionBar extends StatelessWidget {
  const _DistributionBar({required this.totals});

  final List<CategoryTotal> totals;

  @override
  Widget build(BuildContext context) {
    final sum = totals.fold<double>(0, (s, c) => s + c.total);

    // flex harus integer; skala 1000 agar segmen kecil tetap terlihat.
    int flexOf(CategoryTotal c) {
      final flex = sum <= 0 ? 1 : (c.total / sum * 1000).round();
      return flex < 1 ? 1 : flex;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (var i = 0; i < totals.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: flexOf(totals[i]),
                child: Container(
                    color: AppCategories.colorOf(totals[i].categoryName)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(
      {required this.name, required this.amount, required this.fraction});

  final String name;
  final double amount;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: AppCategories.colorOf(name), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style:
                    const TextStyle(fontSize: 13.5, color: AppColors.textGrey)),
          ),
          Text(Fmt.rupiah(amount),
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy)),
          SizedBox(
            width: 44,
            child: Text(Fmt.percent(fraction),
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 11.5, color: AppColors.textGrey)),
          ),
        ],
      ),
    );
  }
}
