// Pratinjau visual (dilewati secara default):
//   flutter test test/visual_preview_test.dart --dart-define=PREVIEW=true --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/core/theme/app_theme.dart';
import 'package:strukku/core/widgets/photo_card.dart';
import 'package:strukku/core/widgets/receipt_tile.dart';
import 'package:strukku/features/hub/features_screen.dart';
import 'package:strukku/features/hub/quick_features.dart';
import 'package:strukku/features/insights/insight_service.dart';
import 'package:strukku/features/insights/insights_section.dart';
import 'package:strukku/models/receipt_item_model.dart';
import 'package:strukku/models/receipt_model.dart';
import 'package:strukku/models/user_model.dart';

const bool _preview = bool.fromEnvironment('PREVIEW');

void main() {
  testWidgets('pratinjau tab Fitur', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final user = UserModel(
        id: 1, fullName: 'Satria', email: 's@x.id', createdAt: DateTime(2026));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: SafeArea(child: FeaturesScreen(user: user))),
    ));
    await tester.runAsync(() async {
      for (final e in tester.widgetList<Ink>(find.byType(Ink))) {
        final img = (e.decoration as BoxDecoration?)?.image?.image;
        if (img != null) await precacheImage(img, tester.element(find.byType(FeaturesScreen)));
      }
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/features_tab.png'));
  }, skip: !_preview);

  testWidgets('pratinjau komponen Beranda', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final user = UserModel(id: 1, fullName: 'Satria', email: 's@x.id', createdAt: DateTime(2026));
    final r = ReceiptModel(userId: 1, merchantName: 'Kopi Kenangan', transactionDate: DateTime(2026, 11, 14),
        totalAmount: 42000, createdAt: DateTime(2026, 11, 14), items: const [
          ReceiptItemModel(categoryId: 2, categoryName: 'Minuman', itemName: 'Es Kopi', itemPrice: 42000)]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F9FC),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const SectionTitle('Jelajahi fitur'),
          const SizedBox(height: 12),
          QuickFeatures(user: user),
          const SectionTitle('Analisis & rekomendasi'),
          const SizedBox(height: 12),
          const PersonaCard(persona: SpendingPersona(title: 'Penikmat Minuman', description: 'Kopi dan teh jadi pos terbesar Anda.', categoryName: 'Minuman', sharePercent: 52)),
          const SizedBox(height: 10),
          const InsightCard(insight: Insight(kind: InsightKind.warning, title: 'Pengeluaran naik 18%', message: 'Lebih tinggi dari bulan lalu.')),
          const SizedBox(height: 8),
          const InsightCard(insight: Insight(kind: InsightKind.tip, title: 'Saran untuk Minuman', message: 'Seduh kopi sendiri di rumah.')),
          const SizedBox(height: 16),
          const SectionTitle('Struk terbaru'),
          const SizedBox(height: 10),
          ReceiptTile(receipt: r),
        ]),
      ),
    ));
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(ListView).first);
      for (final f in ['feat_analysis', 'feat_budget', 'feat_stores', 'cat_minuman']) {
        await precacheImage(AssetImage('assets/images/$f.jpg'), ctx);
      }
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home_parts.png'));
  }, skip: !_preview);
}
