// Tangkapan layar aplikasi STRUKKU (untuk Figma & laporan), dilewati secara default.
//   flutter test test/app_screens_capture_test.dart --dart-define=CAPTURE=true --update-goldens
// Hasil: test/goldens/screens/*.png
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strukku/core/app_state.dart';
import 'package:strukku/core/theme/app_theme.dart';
import 'package:strukku/core/utils/receipt_parser.dart';
import 'package:strukku/data/repositories/auth_repository.dart';
import 'package:strukku/data/repositories/category_repository.dart';
import 'package:strukku/data/repositories/receipt_repository.dart';
import 'package:strukku/data/repositories/repository_provider.dart';
import 'package:strukku/features/auth/auth_screen.dart';
import 'package:strukku/features/budget/budget_screen.dart';
import 'package:strukku/features/dashboard/receipt_detail_sheet.dart';
import 'package:strukku/features/insights/analysis_screen.dart';
import 'package:strukku/features/insights/model_report_screen.dart';
import 'package:strukku/features/insights/price_history_screen.dart';
import 'package:strukku/features/recurring/recurring_screen.dart';
import 'package:strukku/features/scanner/scan_result.dart';
import 'package:strukku/features/stores/stores_screen.dart';
import 'package:strukku/features/validation/validation_screen.dart';
import 'package:strukku/models/category_model.dart';
import 'package:strukku/models/dashboard_model.dart';
import 'package:strukku/models/model_report.dart';
import 'package:strukku/models/price_history.dart';
import 'package:strukku/models/receipt_item_model.dart';
import 'package:strukku/models/receipt_model.dart';
import 'package:strukku/models/user_model.dart';
import 'package:strukku/navigation/main_shell.dart';

const bool _capture = bool.fromEnvironment('CAPTURE');

final _user = UserModel(
    id: 1,
    email: 'satria@gmail.com',
    fullName: 'Satria Badrus Salam',
    createdAt: DateTime(2026, 11, 9));

const _cats = [
  CategoryModel(id: 1, name: 'Makanan', description: 'Makanan, camilan, dan bahan pangan'),
  CategoryModel(id: 2, name: 'Minuman', description: 'Minuman kemasan, kopi, teh, susu, dan air mineral'),
  CategoryModel(id: 3, name: 'Kebutuhan Rumah Tangga', description: 'Perlengkapan kebersihan dan kebutuhan rumah'),
  CategoryModel(id: 4, name: 'Perawatan Diri', description: 'Produk kebersihan badan, kosmetik, dan perawatan diri'),
  CategoryModel(id: 5, name: 'Kesehatan', description: 'Obat, vitamin, dan kebutuhan kesehatan'),
  CategoryModel(id: 6, name: 'Lainnya', description: 'Pengeluaran di luar kategori utama'),
];

ReceiptItemModel _i(int cat, String name, double price, {int qty = 1, double? conf, bool corrected = false}) =>
    ReceiptItemModel(
      categoryId: cat,
      categoryName: _cats[cat - 1].name,
      itemName: name,
      itemPrice: price,
      quantity: qty,
      confidenceScore: conf ?? 0.9,
      isUserCorrected: corrected,
    );

final List<ReceiptModel> _receipts = [
  ReceiptModel(id: 1, userId: 1, merchantName: 'Toko Sejahtera', merchantAddress: 'Jl. Melati No. 12, Malang',
      transactionDate: DateTime(2026, 11, 12, 14, 32), totalAmount: 133000, createdAt: DateTime(2026, 11, 12),
      items: [_i(1, 'Beras 5kg', 62000), _i(1, 'Minyak Goreng 1L', 16500), _i(1, 'Telur Ayam 1kg', 28000),
        _i(1, 'Gula Pasir 1kg', 14000), _i(1, 'Mie Instan', 12500, qty: 5)]),
  ReceiptModel(id: 2, userId: 1, merchantName: 'Indomaret Gajayana', merchantAddress: 'Jl. Gajayana No. 45, Malang',
      transactionDate: DateTime(2026, 11, 5, 14, 32), totalAmount: 167100, createdAt: DateTime(2026, 11, 5),
      items: [_i(1, 'Beras 5kg', 62500), _i(1, 'Minyak Goreng 1L', 15800), _i(1, 'Telur Ayam 1kg', 28900),
        _i(1, 'Mie Instan', 14000, qty: 5), _i(2, 'Susu UHT 1L', 33400, qty: 2), _i(1, 'Roti Tawar', 12500)]),
  ReceiptModel(id: 3, userId: 1, merchantName: 'Kopi Kenangan', merchantAddress: 'Jl. Soekarno Hatta No. 9, Malang',
      transactionDate: DateTime(2026, 11, 14, 9, 10), totalAmount: 42000, createdAt: DateTime(2026, 11, 14),
      items: [_i(2, 'Es Kopi Kenangan Mantan', 24000), _i(2, 'Teh Tarik', 18000)]),
  ReceiptModel(id: 4, userId: 1, merchantName: 'Apotek Kimia Farma', merchantAddress: 'Jl. Ijen No. 4, Malang',
      transactionDate: DateTime(2026, 11, 8, 19, 2), totalAmount: 58500, createdAt: DateTime(2026, 11, 8),
      items: [_i(5, 'Paracetamol 500mg', 12500), _i(5, 'Vitamin C 1000mg', 46000)]),
  ReceiptModel(id: 5, userId: 1, merchantName: 'Alfamart Dinoyo', merchantAddress: null,
      transactionDate: DateTime(2026, 11, 2, 16, 45), totalAmount: 71400, createdAt: DateTime(2026, 11, 2),
      items: [_i(4, 'Pepsodent Pasta Gigi', 14900), _i(4, 'Lifebuoy Sabun Cair', 26500),
        _i(3, 'So Klin Lantai', 18500), _i(3, 'Tisu Paseo', 11500)]),
  ReceiptModel(id: 6, userId: 1, merchantName: 'FreshMart', merchantAddress: 'Jl. Melati No. 12, Malang',
      transactionDate: DateTime(2026, 10, 21, 10, 24), totalAmount: 175500, createdAt: DateTime(2026, 10, 21),
      items: [_i(1, 'Beras 5kg', 62000), _i(2, 'Susu UHT 1L', 30000, qty: 2), _i(1, 'Roti Tawar', 9500),
        _i(1, 'Telur Ayam 1kg', 27000), _i(1, 'Gula Pasir 1kg', 16000), _i(1, 'Mie Instan', 12500, qty: 5),
        _i(1, 'Minyak Goreng 1L', 18500)]),
];

List<ReceiptModel> _inRange(DateTime start, DateTime end) => _receipts
    .where((r) => !r.transactionDate.isBefore(start) && r.transactionDate.isBefore(end))
    .toList()
  ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

List<CategoryTotal> _catTotals(List<ReceiptModel> rs) {
  final m = <String, double>{};
  for (final r in rs) {
    for (final i in r.items) {
      m[i.categoryName] = (m[i.categoryName] ?? 0) + i.itemPrice;
    }
  }
  return m.entries.map((e) => CategoryTotal(categoryName: e.key, total: e.value)).toList()
    ..sort((a, b) => b.total.compareTo(a.total));
}

class _FakeAuth implements AuthRepository {
  @override
  Future<UserModel?> currentUser() async => _user;
  @override
  Future<UserModel> login({required String email, required String password}) async => _user;
  @override
  Future<void> logout() async {}
  @override
  Future<UserModel> register({required String fullName, required String email, required String password}) async =>
      _user;
}

class _FakeCategories implements CategoryRepository {
  @override
  Future<List<CategoryModel>> getCategories() async => _cats;
}

class _FakeReceipts implements ReceiptRepository {
  @override
  Future<List<DateTime>> availableMonths(int userId) async => [DateTime(2026, 11), DateTime(2026, 10)];
  @override
  Future<ClassificationResult> classifyItems(List<String> itemNames) async =>
      const ClassificationResult(predictions: [], isSimulated: false);
  @override
  Future<int> countReceipts(int userId) async => _receipts.length;
  @override
  Future<void> deleteReceipt(int userId, int receiptId) async {}
  @override
  Future<DashboardModel> getDashboard(int userId, DateTime month) async {
    final rs = _inRange(DateTime(month.year, month.month), DateTime(month.year, month.month + 1));
    return DashboardModel(
      month: DateTime(month.year, month.month),
      totalAmount: rs.fold(0, (s, r) => s + r.totalAmount),
      receiptCount: rs.length,
      categoryTotals: _catTotals(rs),
      recentReceipts: rs.take(4).toList(),
    );
  }
  @override
  Future<ModelReport?> getModelReport() async => ModelReport.fromJson({
        'total_items': 26,
        'corrected_items': 2,
        'accuracy': 92.3,
        'categories': [
          {'category': 'Makanan', 'items': 17, 'corrected': 1, 'accuracy': 94.1},
          {'category': 'Minuman', 'items': 5, 'corrected': 1, 'accuracy': 80.0},
          {'category': 'Kesehatan', 'items': 2, 'corrected': 0, 'accuracy': 100.0},
          {'category': 'Perawatan Diri', 'items': 2, 'corrected': 0, 'accuracy': 100.0},
        ],
        'sources': [
          {'source': 'keyword_rules', 'label': 'Kata kunci', 'items': 21, 'accuracy': 95.2},
          {'source': 'id_model', 'label': 'Model Indonesia (TF-IDF + NB)', 'items': 5, 'accuracy': 80.0},
        ],
        'top_corrections': [
          {'item_name': 'LOTUS BISCOFF FRESHMILK', 'predicted': 'Makanan', 'corrected_to': 'Minuman', 'count': 1},
          {'item_name': 'ULA PASIR 1KG', 'predicted': 'Kebutuhan Rumah Tangga', 'corrected_to': 'Makanan', 'count': 1},
        ],
        'monthly': [
          for (final (m, a) in [('Juni 2026', null), ('Juli 2026', null), ('Agustus 2026', null),
            ('September 2026', null), ('Oktober 2026', 85.7), ('November 2026', 94.7)])
            {'month': '', 'month_label': m, 'items': a == null ? 0 : 10, 'accuracy': a},
        ],
        'learned_corrections': 2,
        'training_samples': 10080,
        'trained_at': '2026-11-16T09:00:00',
      });
  @override
  Future<List<double>> getMonthlyTotals(int userId, int year) async {
    final t = List<double>.filled(12, 0);
    for (final r in _receipts) {
      if (r.transactionDate.year == year) t[r.transactionDate.month - 1] += r.totalAmount;
    }
    if (year == 2026) {
      t[7] = 380000;
      t[8] = 420000;
    }
    return t;
  }
  @override
  Future<PeriodData> getPeriodData(int userId, DateTime start, DateTime endExclusive) async {
    final rs = _inRange(start, endExclusive);
    return PeriodData(receipts: rs, categoryTotals: _catTotals(rs));
  }
  @override
  Future<PriceHistory> getPriceHistory(int userId, String query) async {
    final q = query.toLowerCase();
    return PriceHistory.fromPoints([
      for (final r in _receipts)
        for (final i in r.items)
          if (i.itemName.toLowerCase().contains(q))
            PricePoint(
                itemName: i.itemName,
                merchantName: r.merchantName,
                date: r.transactionDate,
                quantity: i.quantity,
                unitPrice: i.itemPrice / i.quantity),
    ]);
  }
  @override
  Future<List<ReceiptModel>> getReceiptSummaries(int userId, {required DateTime month}) async =>
      _inRange(DateTime(month.year, month.month), DateTime(month.year, month.month + 1));
  @override
  Future<List<ReceiptModel>> getReceipts(int userId, {DateTime? month}) async => month == null
      ? ([..._receipts]..sort((a, b) => b.transactionDate.compareTo(a.transactionDate)))
      : _inRange(DateTime(month.year, month.month), DateTime(month.year, month.month + 1));
  @override
  Future<List<StoreSummary>> getStores(int userId) async => StoreSummary.fromReceipts(_receipts);
  @override
  Future<Map<int, double>> getYearlyTotals(int userId) async => {2025: 1850000, 2026: 1474500};
  @override
  Future<DateTime?> latestMonthWithData(int userId) async => DateTime(2026, 11);
  @override
  Future<ReceiptModel> saveReceipt(ReceiptModel receipt, {bool allowDuplicate = false}) async => receipt;
  @override
  Future<ServerScan?> scanReceipt(String imagePath,
          {String? deviceText}) async =>
      null;
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String n) async => ByteData.view(File('$dir/$n').readAsBytesSync().buffer);
  final roboto = FontLoader('Roboto');
  for (final n in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf', 'roboto-italic.ttf']) {
    roboto.addFont(f(n));
  }
  await roboto.load();
  // Teks tanpa fontFamily memakai font bawaan tes ("FlutterTest"): arahkan ke Roboto juga.
  for (final family in ['FlutterTest', 'Ahem']) {
    final fallback = FontLoader(family);
    for (final n in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
      fallback.addFont(f(n));
    }
    await fallback.load();
  }
  final icons = FontLoader('MaterialIcons')..addFont(f('materialicons-regular.otf'));
  await icons.load();
}

/// Muat semua gambar asset di layar lalu render ulang beberapa kali.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(MaterialApp));
      final providers = <ImageProvider>{};
      for (final e in find.byWidgetPredicate((w) => w is Image).evaluate()) {
        providers.add((e.widget as Image).image);
      }
      for (final e in find.byWidgetPredicate((w) => w is Ink || w is Container || w is DecoratedBox).evaluate()) {
        final w = e.widget;
        final Decoration? d = w is Ink ? w.decoration : (w is Container ? w.decoration : (w as DecoratedBox).decoration);
        if (d is BoxDecoration && d.image != null) providers.add(d.image!.image);
      }
      for (final p in providers) {
        await precacheImage(p, ctx);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _shot(WidgetTester tester, String name, Widget home, {double height = 844, Future<void> Function()? after}) async {
  tester.view.physicalSize = Size(390 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: home,
  ));
  await _settle(tester);
  if (after != null) {
    await after();
    await _settle(tester);
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/screens/$name.png'));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'budget_limits_1': '{"__total__":2000000,"Makanan":350000,"Minuman":120000,"Kesehatan":150000,'
          '"Perawatan Diri":100000,"Kebutuhan Rumah Tangga":150000}',
      'recurring_1': '[{"id":"1","name":"Kos Bulanan","amount":800000,"category":"Lainnya","day":1,'
          '"start":"2026-11-01T00:00:00.000","last":"2026-11-01T00:00:00.000","active":true},'
          '{"id":"2","name":"Netflix","amount":54000,"category":"Lainnya","day":5,'
          '"start":"2026-11-01T00:00:00.000","last":"2026-11-01T00:00:00.000","active":true},'
          '{"id":"3","name":"Internet IndiHome","amount":345000,"category":"Kebutuhan Rumah Tangga","day":20,'
          '"start":"2026-11-01T00:00:00.000","last":"2026-10-01T00:00:00.000","active":true}]',
      'notif_enabled': false,
    });
    AppRepositories.useForTesting(auth: _FakeAuth(), categories: _FakeCategories(), receipts: _FakeReceipts());
    AppState.selectedMonth.value = DateTime(2026, 11);
  });

  tearDown(() {});

  Widget shell(int tab) => _ShellAt(tab: tab);

  testWidgets('01 login', (t) async {
    await _shot(t, '01_login', AuthScreen(authRepository: _FakeAuth(), onAuthenticated: (_) {}));
  }, skip: !_capture);

  testWidgets('02 beranda', (t) async {
    await _shot(t, '02_beranda', shell(0), height: 2380);
  }, skip: !_capture);

  testWidgets('03 kategori', (t) async {
    await _shot(t, '03_kategori', shell(1), height: 1500);
  }, skip: !_capture);

  testWidgets('04 fitur', (t) async {
    await _shot(t, '04_fitur', shell(2), height: 1180);
  }, skip: !_capture);

  testWidgets('05 profil', (t) async {
    await _shot(t, '05_profil', shell(3));
  }, skip: !_capture);

  testWidgets('06 validasi', (t) async {
    await _shot(
        t,
        '06_koreksi_validasi',
        ValidationScreen(
          user: _user,
          scan: ScanResult(
            imagePath: null,
            rawText: '',
            scanId: 'demo',
            parsed: ParsedReceipt(
              merchantName: 'Toko Sejahtera',
              merchantAddress: 'Jl. Melati No. 12, Malang',
              transactionDate: DateTime(2026, 11, 12, 14, 32),
              totalAmount: 133000,
              items: const [
                ParsedItem('Beras 5kg', 62000, unitPrice: 62000),
                ParsedItem('Minyak Goreng 1L', 16500, unitPrice: 16500),
                ParsedItem('Telur Ayam 1kg', 28000, unitPrice: 28000),
                ParsedItem('ula Pasir 1kg', 14000, unitPrice: 14000),
                ParsedItem('Mie Instan', 12500, quantity: 5, unitPrice: 2500),
              ],
            ),
            classification: const ClassificationResult(isSimulated: false, predictions: [
              ItemPrediction(itemName: 'Beras 5kg', categoryName: 'Makanan', confidence: 0.9, categoryId: 1),
              ItemPrediction(itemName: 'Minyak Goreng 1L', categoryName: 'Makanan', confidence: 0.9, categoryId: 1),
              ItemPrediction(itemName: 'Telur Ayam 1kg', categoryName: 'Makanan', confidence: 0.9, categoryId: 1),
              ItemPrediction(itemName: 'ula Pasir 1kg', categoryName: 'Makanan', confidence: 0.62, categoryId: 1),
              ItemPrediction(itemName: 'Mie Instan', categoryName: 'Makanan', confidence: 0.9, categoryId: 1),
            ]),
          ),
        ),
        height: 1900);
  }, skip: !_capture);

  testWidgets('07 detail struk', (t) async {
    await _shot(t, '07_detail_struk', Builder(builder: (c) => const Scaffold(body: SizedBox())), after: () async {
      showReceiptDetailSheet(t.element(find.byType(Scaffold)), user: _user, receipt: _receipts[0]);
      await t.pump(const Duration(seconds: 1));
    });
  }, skip: !_capture);

  testWidgets('08 analisis', (t) async {
    await _shot(t, '08_analisis', AnalysisScreen(user: _user, initialMonth: DateTime(2026, 11)), height: 3200);
  }, skip: !_capture);

  testWidgets('09 anggaran', (t) async {
    await _shot(t, '09_anggaran', BudgetScreen(user: _user), height: 1400);
  }, skip: !_capture);

  testWidgets('10 berulang', (t) async {
    await _shot(t, '10_pengeluaran_berulang', RecurringScreen(user: _user));
  }, skip: !_capture);

  testWidgets('11 lokasi toko', (t) async {
    await _shot(t, '11_lokasi_toko', StoresScreen(user: _user), height: 1000);
  }, skip: !_capture);

  testWidgets('12 riwayat harga', (t) async {
    await _shot(t, '12_riwayat_harga', PriceHistoryScreen(user: _user, initialQuery: 'beras'));
  }, skip: !_capture);

  testWidgets('13 kinerja model', (t) async {
    await _shot(t, '13_kinerja_model', const ModelReportScreen(), height: 1250);
  }, skip: !_capture);
}

/// MainShell dibuka pada tab tertentu (dengan mengetuk navigasi bawah).
class _ShellAt extends StatefulWidget {
  const _ShellAt({required this.tab});

  final int tab;

  @override
  State<_ShellAt> createState() => _ShellAtState();
}

class _ShellAtState extends State<_ShellAt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.tab == 0 || !mounted) return;
      final labels = ['Beranda', 'Kategori', 'Fitur', 'Profil'];
      final finder = find.text(labels[widget.tab]);
      final el = finder.evaluate();
      if (el.isEmpty) return;
      final nav = el.first.findAncestorWidgetOfExactType<NavigationBar>();
      nav?.onDestinationSelected?.call(widget.tab);
    });
  }

  @override
  Widget build(BuildContext context) => MainShell(user: _user, onLogout: () async {});
}
