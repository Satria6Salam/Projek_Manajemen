import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/decorated_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/user_model.dart';
import 'maps_launcher.dart';

/// Toko tempat pengguna berbelanja beserta alamat dari struk + tombol Maps.
class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  late Future<List<StoreSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = AppRepositories.instance.receipts.getStores(widget.user.id);
  }

  void _reload() => setState(() =>
      _future = AppRepositories.instance.receipts.getStores(widget.user.id));

  Future<void> _open(StoreSummary s) async {
    final ok = await MapsLauncher.open(s.name, s.address);
    if (!ok && mounted) {
      showAppSnackBar(
          context, 'Tidak ada aplikasi peta/browser untuk membuka lokasi.',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lokasi Toko')),
      body: FutureBuilder<List<StoreSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: ErrorState(message: '${snap.error}', onRetry: _reload));
          }
          final stores = snap.data ?? const [];
          if (stores.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                title: 'Belum ada toko',
                message: 'Toko muncul di sini setelah Anda menyimpan struk.',
              ),
            );
          }
          final withAddress = stores.where((s) => s.address != null).length;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                DecoratedCard(
                  dark: true,
                  color: AppColors.primary,
                  icons: const [
                    Icons.map_outlined,
                    Icons.storefront_outlined,
                    Icons.place_outlined
                  ],
                  child: Row(
                    children: [
                      const Icon(Icons.travel_explore,
                          color: Colors.white, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${stores.length} toko · $withAddress dengan alamat dari struk.\n'
                          'Ketuk toko untuk membukanya di Google Maps.',
                          style: const TextStyle(
                              color: Colors.white, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final s in stores)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedCard(
                      color: AppColors.primary,
                      icons: const [
                        Icons.place_outlined,
                        Icons.storefront_outlined
                      ],
                      radius: 16,
                      padding: const EdgeInsets.all(12),
                      onTap: () => _open(s),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: AppColors.primarySoft,
                            child: Icon(Icons.storefront,
                                color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navy)),
                                Text(
                                    s.address ??
                                        'Alamat tidak ada di struk (dicari dari nama toko)',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: s.address == null
                                            ? AppColors.textGrey
                                            : AppColors.navy)),
                                const SizedBox(height: 2),
                                Text(
                                    '${s.visits}x belanja · ${Fmt.rupiah(s.totalSpent.round())}'
                                    '${s.lastVisit == null ? '' : ' · terakhir ${Fmt.shortDate(s.lastVisit!)}'}',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textGrey)),
                              ],
                            ),
                          ),
                          const Icon(Icons.open_in_new,
                              color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
