import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/price_history.dart';
import '../../models/user_model.dart';

/// Riwayat & perbandingan harga satu barang antar toko.
class PriceHistoryScreen extends StatefulWidget {
  const PriceHistoryScreen({super.key, required this.user, this.initialQuery});

  final UserModel user;
  final String? initialQuery;

  @override
  State<PriceHistoryScreen> createState() => _PriceHistoryScreenState();
}

class _PriceHistoryScreenState extends State<PriceHistoryScreen> {
  late final TextEditingController _ctl;
  Future<PriceHistory>? _future;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initialQuery ?? '');
    if ((widget.initialQuery ?? '').trim().length >= 2) _search();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _search() {
    final q = _ctl.text.trim();
    if (q.length < 2) return;
    setState(() {
      _future =
          AppRepositories.instance.receipts.getPriceHistory(widget.user.id, q);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Harga')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              controller: _ctl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Nama barang, mis. indomie goreng',
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward), onPressed: _search),
              ),
            ),
          ),
          Expanded(
            child: _future == null
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: EmptyState(
                      title: 'Bandingkan harga',
                      message:
                          'Ketik nama barang untuk melihat harganya di setiap toko '
                          'tempat Anda pernah membelinya.',
                    ),
                  )
                : FutureBuilder<PriceHistory>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                            child: ErrorState(
                                message: '${snap.error}', onRetry: _search));
                      }
                      final h = snap.data!;
                      if (h.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: EmptyState(
                            title: 'Belum pernah dibeli',
                            message:
                                'Tidak ada barang yang cocok di struk Anda.',
                          ),
                        );
                      }
                      return _buildResult(h);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(PriceHistory h) {
    final cheapest = h.merchants.first;
    final dearest = h.merchants.last;
    final saving = dearest.latest - cheapest.latest;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (h.cheapestMerchant != null && saving > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.savings_outlined,
                    color: AppColors.successText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Termurah di ${cheapest.merchantName} (${Fmt.rupiah(cheapest.latest.round())}). '
                    'Hemat ${Fmt.rupiah(saving.round())} per barang dibanding ${dearest.merchantName}.',
                    style: const TextStyle(
                        color: AppColors.successText, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Text('Per toko',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navy)),
        const SizedBox(height: 8),
        for (final m in h.merchants)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: m.merchantName == h.cheapestMerchant
                      ? AppColors.successText
                      : AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.merchantName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy)),
                      Text(
                          '${m.purchases}x dibeli · termurah ${Fmt.rupiah(m.lowest.round())} '
                          '· rata-rata ${Fmt.rupiah(m.average.round())}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textGrey)),
                    ],
                  ),
                ),
                Text(Fmt.rupiah(m.latest.round()),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.navy)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Text('Riwayat pembelian',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navy)),
        for (final p in h.points)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(p.itemName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.navy)),
            subtitle: Text(
                '${p.merchantName}${p.date == null ? '' : ' · ${Fmt.shortDate(p.date!)}'}'
                '${p.quantity > 1 ? ' · ${p.quantity} barang' : ''}'),
            trailing: Text('${Fmt.rupiah(p.unitPrice.round())}/brg',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
