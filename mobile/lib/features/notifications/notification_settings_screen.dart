import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/state_views.dart';
import '../../models/user_model.dart';
import 'notification_service.dart';
import 'reminder_coordinator.dart';
import 'reminder_settings.dart';

/// Pengaturan notifikasi: pengingat harian, ringkasan mingguan, peringatan anggaran.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  ReminderSettings? _settings;

  @override
  void initState() {
    super.initState();
    ReminderSettings.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  Future<void> _update(ReminderSettings next) async {
    setState(() => _settings = next);
    await next.save();
    if (next.notificationsEnabled) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted && mounted) {
        showAppSnackBar(context,
            'Izin notifikasi ditolak. Aktifkan di Setelan HP > Aplikasi > STRUKKU > Notifikasi.',
            error: true);
      }
    }
    await ReminderCoordinator.apply(next, widget.user.id);
  }

  Future<void> _pickTime(ReminderSettings s) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute),
      helpText: 'Jam pengingat harian',
    );
    if (picked != null) {
      await _update(
          s.copyWith(reminderHour: picked.hour, reminderMinute: picked.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                SwitchListTile(
                  title: const Text('Aktifkan notifikasi'),
                  subtitle: const Text('Semua notifikasi STRUKKU di HP ini'),
                  value: s.notificationsEnabled,
                  onChanged: (v) =>
                      _update(s.copyWith(notificationsEnabled: v)),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Pengingat harian'),
                  subtitle: Text('Ingatkan mencatat struk setiap hari pukul '
                      '${s.reminderHour.toString().padLeft(2, '0')}:${s.reminderMinute.toString().padLeft(2, '0')}'),
                  value: s.dailyReminder,
                  onChanged: s.notificationsEnabled
                      ? (v) => _update(s.copyWith(dailyReminder: v))
                      : null,
                ),
                ListTile(
                  enabled: s.notificationsEnabled && s.dailyReminder,
                  leading: const Icon(Icons.schedule, color: AppColors.primary),
                  title: const Text('Ubah jam pengingat'),
                  onTap: () => _pickTime(s),
                ),
                SwitchListTile(
                  title: const Text('Ringkasan mingguan'),
                  subtitle: const Text(
                      'Setiap Minggu pukul 19.00: total & kategori terbanyak 7 hari terakhir'),
                  value: s.weeklySummary,
                  onChanged: s.notificationsEnabled
                      ? (v) => _update(s.copyWith(weeklySummary: v))
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Peringatan anggaran'),
                  subtitle: const Text(
                      'Saat pemakaian anggaran mencapai 80% dan 100%'),
                  value: s.budgetAlerts,
                  onChanged: s.notificationsEnabled
                      ? (v) => _update(s.copyWith(budgetAlerts: v))
                      : null,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: s.notificationsEnabled
                        ? () async {
                            await NotificationService.instance.showNow(
                              id: 99,
                              title: 'Tes notifikasi STRUKKU',
                              body: await ReminderCoordinator.weeklyBody(
                                  widget.user.id),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Kirim notifikasi uji'),
                  ),
                ),
              ],
            ),
    );
  }
}
