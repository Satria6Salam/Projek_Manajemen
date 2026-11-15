import 'package:flutter/material.dart';

import '../../core/widgets/photo_card.dart';
import '../../models/user_model.dart';
import '../budget/budget_screen.dart';
import '../insights/analysis_screen.dart';
import '../insights/price_history_screen.dart';
import '../recurring/recurring_screen.dart';
import '../stores/stores_screen.dart';

/// Baris kartu foto bergeser di Beranda: pintasan ke fitur utama.
class QuickFeatures extends StatelessWidget {
  const QuickFeatures({super.key, required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final items =
        <(String, String, IconData, Color, String, Widget Function())>[
      (
        'Analisis',
        'Tren & persona',
        Icons.insights,
        const Color(0xFF2160DD),
        'assets/images/feat_analysis.jpg',
        () => AnalysisScreen(user: user)
      ),
      (
        'Anggaran',
        'Batas bulanan',
        Icons.savings,
        const Color(0xFFE5537A),
        'assets/images/feat_budget.jpg',
        () => BudgetScreen(user: user)
      ),
      (
        'Lokasi Toko',
        'Buka di Maps',
        Icons.place,
        const Color(0xFFEF4444),
        'assets/images/feat_stores.jpg',
        () => StoresScreen(user: user)
      ),
      (
        'Harga',
        'Bandingkan toko',
        Icons.sell,
        const Color(0xFFB7791F),
        'assets/images/feat_price.jpg',
        () => PriceHistoryScreen(user: user)
      ),
      (
        'Berulang',
        'Langganan',
        Icons.event_repeat,
        const Color(0xFF8A5CF6),
        'assets/images/feat_recurring.jpg',
        () => RecurringScreen(user: user)
      ),
    ];
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(bottom: 14),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final (title, subtitle, icon, color, photo, page) = items[i];
          return SizedBox(
            width: 132,
            child: PhotoCard(
              photo: photo,
              color: color,
              radius: 18,
              padding: const EdgeInsets.all(12),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => page())),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PhotoIconBadge(icon: icon, color: color, size: 32),
                  const Spacer(),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFE2E8F0), fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
