import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/repository_provider.dart';
import '../budget/budget_service.dart';
import '../recurring/recurring_service.dart';
import 'notification_service.dart';
import 'reminder_settings.dart';

/// Menyusun ulang jadwal notifikasi sesuai pengaturan dan mengecek anggaran.
class ReminderCoordinator {
  ReminderCoordinator._();

  static final NotificationService _notifications =
      NotificationService.instance;

  /// Dipanggil saat aplikasi dibuka dalam keadaan login. Tidak pernah melempar error.
  static Future<void> onAppOpened(int userId) async {
    try {
      final settings = await ReminderSettings.load();
      if (settings.notificationsEnabled) {
        await _notifications.requestPermission();
      }
      // Catat langganan/tagihan yang sudah jatuh tempo sebelum cek anggaran.
      await const RecurringService().generateDue(userId);
      await BudgetService().checkAndNotify(userId);
      await apply(settings, userId);
    } catch (e) {
      debugPrint('[STRUKKU] pengingat gagal disiapkan: $e');
    }
  }

  /// Setelah struk disimpan: cek anggaran & perbarui isi ringkasan mingguan.
  static Future<void> onReceiptSaved(int userId) async {
    try {
      await BudgetService().checkAndNotify(userId);
      await apply(await ReminderSettings.load(), userId);
    } catch (e) {
      debugPrint('[STRUKKU] cek anggaran gagal: $e');
    }
  }

  static Future<void> apply(ReminderSettings settings, int userId) async {
    if (!settings.notificationsEnabled) {
      await _notifications.cancelDaily();
      await _notifications.cancelWeekly();
      return;
    }
    if (settings.dailyReminder) {
      await _notifications.scheduleDailyReminder(
          hour: settings.reminderHour, minute: settings.reminderMinute);
    } else {
      await _notifications.cancelDaily();
    }
    if (settings.weeklySummary) {
      await _notifications.scheduleWeeklySummary(
          body: await weeklyBody(userId));
    } else {
      await _notifications.cancelWeekly();
    }
  }

  /// Ringkasan tujuh hari terakhir (dihitung saat dijadwalkan).
  static Future<String> weeklyBody(int userId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final data = await AppRepositories.instance.receipts.getPeriodData(
        userId,
        today.subtract(const Duration(days: 6)),
        today.add(const Duration(days: 1)));
    if (data.receipts.isEmpty) {
      return 'Belum ada struk 7 hari terakhir. Yuk mulai catat belanjamu!';
    }
    final top = [...data.categoryTotals]
      ..sort((a, b) => b.total.compareTo(a.total));
    return '${data.receipts.length} struk, total ${Fmt.rupiah(data.total.round())} dalam 7 hari terakhir'
        '${top.isEmpty ? '.' : '. Terbanyak: ${top.first.categoryName}.'}';
  }
}
