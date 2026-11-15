import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_state.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/receipt_item_model.dart';
import '../../models/receipt_model.dart';

/// Pengeluaran berulang bulanan (langganan, tagihan, iuran).
class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.name,
    required this.amount,
    required this.categoryName,
    required this.dayOfMonth,
    required this.startMonth,
    this.lastGenerated,
    this.active = true,
  });

  final String id;
  final String name;
  final double amount;
  final String categoryName;

  /// 1-31; bulan yang lebih pendek memakai tanggal terakhirnya.
  final int dayOfMonth;

  /// Bulan pertama (tanggal 1) pencatatan.
  final DateTime startMonth;

  /// Bulan terakhir yang sudah dicatat (tanggal 1), null = belum pernah.
  final DateTime? lastGenerated;
  final bool active;

  /// Tanggal jatuh tempo pada [month].
  DateTime dueIn(DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, math.min(dayOfMonth, last), 8);
  }

  /// Bulan-bulan yang sudah jatuh tempo per [now] dan belum dicatat.
  List<DateTime> dueMonths(DateTime now) {
    if (!active) return const [];
    var m = lastGenerated == null
        ? DateTime(startMonth.year, startMonth.month)
        : DateTime(lastGenerated!.year, lastGenerated!.month + 1);
    final out = <DateTime>[];
    while (!dueIn(m).isAfter(now) && out.length < 24) {
      out.add(m);
      m = DateTime(m.year, m.month + 1);
    }
    return out;
  }

  RecurringExpense copyWith({DateTime? lastGenerated, bool? active}) =>
      RecurringExpense(
        id: id,
        name: name,
        amount: amount,
        categoryName: categoryName,
        dayOfMonth: dayOfMonth,
        startMonth: startMonth,
        lastGenerated: lastGenerated ?? this.lastGenerated,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'category': categoryName,
        'day': dayOfMonth,
        'start': startMonth.toIso8601String(),
        'last': lastGenerated?.toIso8601String(),
        'active': active,
      };

  factory RecurringExpense.fromJson(Map<String, dynamic> j) => RecurringExpense(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: (j['amount'] as num).toDouble(),
        categoryName: j['category'] as String,
        dayOfMonth: (j['day'] as num).toInt(),
        startMonth: DateTime.parse(j['start'] as String),
        lastGenerated:
            j['last'] == null ? null : DateTime.parse(j['last'] as String),
        active: j['active'] as bool? ?? true,
      );
}

/// Menyimpan daftar pengeluaran berulang (per pengguna, di HP) dan mencatat
/// struknya otomatis saat jatuh tempo.
class RecurringService {
  const RecurringService();

  String _key(int userId) => 'recurring_$userId';

  Future<List<RecurringExpense>> list(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(RecurringExpense.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(int userId, List<RecurringExpense> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(userId), jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> upsert(int userId, RecurringExpense item) async {
    final items = await list(userId);
    final i = items.indexWhere((e) => e.id == item.id);
    if (i >= 0) {
      items[i] = item;
    } else {
      items.add(item);
    }
    await _save(userId, items);
  }

  Future<void> remove(int userId, String id) async {
    final items = await list(userId)
      ..removeWhere((e) => e.id == id);
    await _save(userId, items);
  }

  /// Catat semua pengeluaran berulang yang sudah jatuh tempo. Mengembalikan jumlah struk dibuat.
  Future<int> generateDue(int userId, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final items = await list(userId);
    if (items.every((e) => e.dueMonths(today).isEmpty)) return 0;
    final repos = AppRepositories.instance;
    final categories = {
      for (final c in await repos.categories.getCategories()) c.name: c.id
    };
    var created = 0;
    for (var n = 0; n < items.length; n++) {
      var item = items[n];
      for (final month in item.dueMonths(today)) {
        final categoryId =
            categories[item.categoryName] ?? categories['Lainnya'];
        if (categoryId == null) break;
        await repos.receipts.saveReceipt(
          ReceiptModel(
            userId: userId,
            merchantName: item.name,
            transactionDate: item.dueIn(month),
            totalAmount: item.amount,
            createdAt: DateTime.now(),
            items: [
              ReceiptItemModel(
                categoryId: categoryId,
                categoryName: item.categoryName,
                itemName: '${item.name} (berulang)',
                itemPrice: item.amount,
              ),
            ],
          ),
          allowDuplicate: true,
        );
        item = item.copyWith(lastGenerated: month);
        items[n] = item;
        await _save(
            userId, items); // simpan tiap bulan agar tidak dobel bila terputus
        created++;
      }
    }
    if (created > 0) AppState.dataVersion.value++;
    return created;
  }
}
