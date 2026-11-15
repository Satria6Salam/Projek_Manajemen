import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/category_model.dart';
import '../notifications/notification_service.dart';
import '../notifications/reminder_settings.dart';

/// Satu baris anggaran: pengeluaran bulan ini dan batasnya (jika ada).
class BudgetRow {
  const BudgetRow(
      {required this.name,
      required this.spent,
      this.limit,
      this.isTotal = false});

  /// Nama kategori, atau "Total" untuk batas keseluruhan.
  final String name;
  final double spent;
  final double? limit;
  final bool isTotal;

  bool get hasLimit => limit != null && limit! > 0;

  /// Pemakaian 0 hingga >1 (di atas 1 = melewati batas).
  double get ratio => hasLimit ? spent / limit! : 0;
  double get remaining => hasLimit ? limit! - spent : 0;

  BudgetLevel get level {
    if (!hasLimit) return BudgetLevel.none;
    if (ratio >= 1) return BudgetLevel.over;
    if (ratio >= BudgetService.warnRatio) return BudgetLevel.warning;
    return BudgetLevel.safe;
  }
}

enum BudgetLevel { none, safe, warning, over }

/// Ringkasan anggaran satu bulan.
class BudgetSnapshot {
  const BudgetSnapshot(
      {required this.month, required this.total, required this.rows});

  final DateTime month;

  /// Baris batas total keseluruhan.
  final BudgetRow total;

  /// Baris per kategori.
  final List<BudgetRow> rows;

  /// Baris (termasuk total) yang sudah >= 80% atau melewati batas.
  List<BudgetRow> get alerts => <BudgetRow>[
        if (total.level == BudgetLevel.warning ||
            total.level == BudgetLevel.over)
          total,
        ...rows.where((r) =>
            r.level == BudgetLevel.warning || r.level == BudgetLevel.over),
      ];

  bool get hasAnyLimit => total.hasLimit || rows.any((r) => r.hasLimit);
}

/// Anggaran bulanan per kategori (disimpan di perangkat, per pengguna) dan
/// peringatan 80% / 100% (diadaptasi dari BudgetService smart_receipt_v2).
class BudgetService {
  BudgetService({NotificationService? notifications})
      : _notifications = notifications ?? NotificationService.instance;

  final NotificationService _notifications;

  static const double warnRatio = 0.8;
  static const String totalKey = '__total__';

  String _limitsKey(int userId) => 'budget_limits_$userId';
  String _alertedKey(int userId, DateTime month) =>
      'budget_alerted_${userId}_${month.year}-${month.month.toString().padLeft(2, '0')}';

  /// Batas per kategori (nama kategori -> nominal). Kunci [totalKey] = batas total.
  Future<Map<String, double>> getLimits(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_limitsKey(userId));
    if (raw == null) return <String, double>{};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return <String, double>{};
    }
  }

  /// Simpan batas; [amount] null atau 0 = hapus batas.
  Future<void> setLimit(int userId, String name, double? amount) async {
    final limits = await getLimits(userId);
    if (amount == null || amount <= 0) {
      limits.remove(name);
    } else {
      limits[name] = amount;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_limitsKey(userId), jsonEncode(limits));
    // Batas berubah: peringatan bulan ini boleh dikirim ulang.
    await prefs.remove(_alertedKey(userId, DateTime.now()));
  }

  Future<BudgetSnapshot> snapshot(int userId, DateTime month) async {
    final DateTime start = DateTime(month.year, month.month);
    final DateTime end = DateTime(month.year, month.month + 1);
    final repos = AppRepositories.instance;
    final results = await Future.wait<Object>([
      repos.receipts.getPeriodData(userId, start, end),
      repos.categories.getCategories(),
      getLimits(userId),
    ]);
    final period = results[0] as PeriodData;
    final categories = results[1] as List<CategoryModel>;
    final limits = results[2] as Map<String, double>;
    final spent = <String, double>{
      for (final c in period.categoryTotals) c.categoryName: c.total,
    };
    return BudgetSnapshot(
      month: start,
      total: BudgetRow(
          name: 'Total',
          spent: period.total,
          limit: limits[totalKey],
          isTotal: true),
      rows: [
        for (final c in categories)
          BudgetRow(
              name: c.name, spent: spent[c.name] ?? 0, limit: limits[c.name]),
      ],
    );
  }

  /// Kirim notifikasi saat pemakaian mencapai 80% atau 100%. Setiap ambang
  /// hanya diberitahukan sekali per bulan per kategori.
  Future<void> checkAndNotify(int userId) async {
    final settings = await ReminderSettings.load();
    if (!settings.notificationsEnabled || !settings.budgetAlerts) return;
    final now = DateTime.now();
    final snap = await snapshot(userId, now);
    if (!snap.hasAnyLimit) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _alertedKey(userId, now);
    final alerted = (prefs.getStringList(key) ?? const <String>[]).toSet();
    var id = NotificationService.budgetAlertBaseId;
    for (final row in [snap.total, ...snap.rows]) {
      id++;
      if (!row.hasLimit) continue;
      final int threshold =
          row.ratio >= 1 ? 100 : (row.ratio >= warnRatio ? 80 : 0);
      if (threshold == 0) continue;
      final tag = '${row.name}:$threshold';
      if (alerted.contains(tag)) continue;
      final label = row.isTotal ? 'Anggaran total' : 'Anggaran ${row.name}';
      await _notifications.showNow(
        id: id,
        title: threshold == 100 ? '$label terlampaui' : '$label hampir habis',
        body: threshold == 100
            ? 'Pengeluaran ${Fmt.rupiah(row.spent.round())} melewati batas ${Fmt.rupiah(row.limit!.round())} bulan ini.'
            : 'Sudah terpakai ${(row.ratio * 100).round()}% (${Fmt.rupiah(row.spent.round())} dari ${Fmt.rupiah(row.limit!.round())}).',
      );
      alerted.add(tag);
    }
    await prefs.setStringList(key, alerted.toList());
  }
}
