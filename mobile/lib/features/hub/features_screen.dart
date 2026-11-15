import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/photo_card.dart';
import '../../models/user_model.dart';
import '../budget/budget_screen.dart';
import '../export/export_service.dart';
import '../insights/analysis_screen.dart';
import '../insights/model_report_screen.dart';
import '../insights/price_history_screen.dart';
import '../notifications/notification_settings_screen.dart';
import '../recurring/recurring_screen.dart';
import '../stores/stores_screen.dart';

class _Feature {
  const _Feature({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.photo,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String photo;
  final void Function(BuildContext context) onTap;
}

/// Tab "Fitur": semua fitur tambahan STRUKKU dalam kartu berlatar foto.
class FeaturesScreen extends StatelessWidget {
  const FeaturesScreen({super.key, required this.user});

  final UserModel user;

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _export(BuildContext context) =>
      const ExportService().pickAndShare(context, user.id);

  List<_Feature> _features() => [
        _Feature(
          title: 'Analisis & Tren',
          subtitle: 'Hari, bulan, tahun & persona',
          icon: Icons.insights,
          color: const Color(0xFF2160DD),
          photo: 'assets/images/feat_analysis.jpg',
          onTap: (c) => _push(c, AnalysisScreen(user: user)),
        ),
        _Feature(
          title: 'Anggaran',
          subtitle: 'Batas total & per kategori',
          icon: Icons.savings,
          color: const Color(0xFFE5537A),
          photo: 'assets/images/feat_budget.jpg',
          onTap: (c) => _push(c, BudgetScreen(user: user)),
        ),
        _Feature(
          title: 'Berulang',
          subtitle: 'Langganan & tagihan bulanan',
          icon: Icons.event_repeat,
          color: const Color(0xFF8A5CF6),
          photo: 'assets/images/feat_recurring.jpg',
          onTap: (c) => _push(c, RecurringScreen(user: user)),
        ),
        _Feature(
          title: 'Lokasi Toko',
          subtitle: 'Alamat & Google Maps',
          icon: Icons.place,
          color: const Color(0xFFEF4444),
          photo: 'assets/images/feat_stores.jpg',
          onTap: (c) => _push(c, StoresScreen(user: user)),
        ),
        _Feature(
          title: 'Riwayat Harga',
          subtitle: 'Bandingkan antar toko',
          icon: Icons.sell,
          color: const Color(0xFFB7791F),
          photo: 'assets/images/feat_price.jpg',
          onTap: (c) => _push(c, PriceHistoryScreen(user: user)),
        ),
        _Feature(
          title: 'Ekspor CSV',
          subtitle: 'Laporan bulan ini',
          icon: Icons.ios_share,
          color: const Color(0xFF14B8A6),
          photo: 'assets/images/feat_export.jpg',
          onTap: _export,
        ),
        _Feature(
          title: 'Kinerja Model',
          subtitle: 'Akurasi & koreksi dipelajari',
          icon: Icons.model_training,
          color: const Color(0xFF6366F1),
          photo: 'assets/images/feat_model.jpg',
          onTap: (c) => _push(c, const ModelReportScreen()),
        ),
        _Feature(
          title: 'Notifikasi',
          subtitle: 'Pengingat & peringatan',
          icon: Icons.notifications_active,
          color: const Color(0xFFF59E0B),
          photo: 'assets/images/feat_notif.jpg',
          onTap: (c) => _push(c, NotificationSettingsScreen(user: user)),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final features = _features();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          sliver: SliverToBoxAdapter(
            child: PhotoCard(
              photo: 'assets/images/bg_header_grocery.jpg',
              color: AppColors.primary,
              height: 150,
              radius: 24,
              overlay: 0.92,
              padding: const EdgeInsets.all(18),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Fitur STRUKKU',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Kelola, analisis, dan rencanakan pengeluaranmu.',
                      style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.88,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final f = features[i];
                return PhotoCard(
                  photo: f.photo,
                  color: f.color,
                  onTap: () => f.onTap(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PhotoIconBadge(icon: f.icon, color: f.color),
                      const Spacer(),
                      Text(f.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(f.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFE2E8F0),
                              fontSize: 11.5,
                              height: 1.3)),
                    ],
                  ),
                );
              },
              childCount: features.length,
            ),
          ),
        ),
      ],
    );
  }
}
