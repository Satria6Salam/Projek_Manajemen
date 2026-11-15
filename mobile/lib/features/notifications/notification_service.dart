import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notifikasi lokal (tanpa internet): pengingat harian, ringkasan mingguan,
/// dan peringatan anggaran (diadaptasi dari smart_receipt_v2).
class NotificationService {
  NotificationService._(this._plugin);

  static final NotificationService instance =
      NotificationService._(FlutterLocalNotificationsPlugin());

  final FlutterLocalNotificationsPlugin _plugin;

  static const int dailyReminderId = 1;
  static const int weeklySummaryId = 2;

  /// ID peringatan anggaran = [budgetAlertBaseId] + urutan baris anggaran.
  static const int budgetAlertBaseId = 1000;

  static const String _channelId = 'strukku_main';
  static const String _channelName = 'STRUKKU';
  static const String _channelDescription =
      'Pengingat pencatatan, ringkasan mingguan, dan peringatan anggaran';

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  bool _ready = false;

  /// Siapkan plugin & zona waktu. Aman dipanggil berulang; gagal diam-diam
  /// (mis. di tes atau platform tanpa notifikasi) agar aplikasi tetap jalan.
  Future<bool> initialize() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      try {
        final String zone =
            (await FlutterTimezone.getLocalTimezone()).identifier;
        tz.setLocalLocation(tz.getLocation(zone));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
      }
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('[STRUKKU] notifikasi tidak tersedia: $e');
    }
    return _ready;
  }

  /// Minta izin notifikasi (wajib Android 13 ke atas).
  Future<bool> requestPermission() async {
    if (!await initialize()) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> scheduleDailyReminder(
      {required int hour, required int minute}) async {
    if (!await initialize()) return;
    await _plugin.cancel(dailyReminderId);
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      dailyReminderId,
      'STRUKKU',
      'Sudah catat struk belanja hari ini? Pindai sekarang biar rekapnya akurat.',
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Ringkasan mingguan setiap Minggu pukul 19.00. [body] dihitung saat dijadwalkan.
  Future<void> scheduleWeeklySummary({required String body}) async {
    if (!await initialize()) return;
    await _plugin.cancel(weeklySummaryId);
    final now = tz.TZDateTime.now(tz.local);
    final int daysToSunday = (DateTime.sunday - now.weekday + 7) % 7;
    var when = tz.TZDateTime(
        tz.local, now.year, now.month, now.day + daysToSunday, 19);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 7));
    await _plugin.zonedSchedule(
      weeklySummaryId,
      'Ringkasan minggu ini',
      body,
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> showNow(
      {required int id, required String title, required String body}) async {
    if (!await initialize()) return;
    await _plugin.show(id, title, body, _details);
  }

  Future<void> cancelDaily() async {
    if (await initialize()) await _plugin.cancel(dailyReminderId);
  }

  Future<void> cancelWeekly() async {
    if (await initialize()) await _plugin.cancel(weeklySummaryId);
  }
}
