import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan notifikasi dan pengingat, disimpan di perangkat
/// (diadaptasi dari smart_receipt_v2).
class ReminderSettings {
  const ReminderSettings({
    this.notificationsEnabled = true,
    this.dailyReminder = true,
    this.reminderHour = 20,
    this.reminderMinute = 0,
    this.weeklySummary = true,
    this.budgetAlerts = true,
  });

  final bool notificationsEnabled;
  final bool dailyReminder;
  final int reminderHour;
  final int reminderMinute;
  final bool weeklySummary;
  final bool budgetAlerts;

  static const String _keyEnabled = 'notif_enabled';
  static const String _keyDaily = 'notif_daily';
  static const String _keyHour = 'notif_hour';
  static const String _keyMinute = 'notif_minute';
  static const String _keyWeekly = 'notif_weekly';
  static const String _keyBudget = 'notif_budget';

  static Future<ReminderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const d = ReminderSettings();
    return ReminderSettings(
      notificationsEnabled:
          prefs.getBool(_keyEnabled) ?? d.notificationsEnabled,
      dailyReminder: prefs.getBool(_keyDaily) ?? d.dailyReminder,
      reminderHour: prefs.getInt(_keyHour) ?? d.reminderHour,
      reminderMinute: prefs.getInt(_keyMinute) ?? d.reminderMinute,
      weeklySummary: prefs.getBool(_keyWeekly) ?? d.weeklySummary,
      budgetAlerts: prefs.getBool(_keyBudget) ?? d.budgetAlerts,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, notificationsEnabled);
    await prefs.setBool(_keyDaily, dailyReminder);
    await prefs.setInt(_keyHour, reminderHour);
    await prefs.setInt(_keyMinute, reminderMinute);
    await prefs.setBool(_keyWeekly, weeklySummary);
    await prefs.setBool(_keyBudget, budgetAlerts);
  }

  ReminderSettings copyWith({
    bool? notificationsEnabled,
    bool? dailyReminder,
    int? reminderHour,
    int? reminderMinute,
    bool? weeklySummary,
    bool? budgetAlerts,
  }) =>
      ReminderSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        dailyReminder: dailyReminder ?? this.dailyReminder,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
        weeklySummary: weeklySummary ?? this.weeklySummary,
        budgetAlerts: budgetAlerts ?? this.budgetAlerts,
      );
}
