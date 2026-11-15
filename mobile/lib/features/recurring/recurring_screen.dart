import 'package:flutter/material.dart';

import '../../core/constants/app_categories.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/category_model.dart';
import '../../models/user_model.dart';
import 'recurring_service.dart';

/// Daftar pengeluaran berulang bulanan (langganan, tagihan, iuran).
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  final RecurringService _service = const RecurringService();
  late Future<List<RecurringExpense>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.list(widget.user.id);
  }

  void _reload() => setState(() => _future = _service.list(widget.user.id));

  Future<void> _edit([RecurringExpense? existing]) async {
    final categories =
        await AppRepositories.instance.categories.getCategories();
    if (!mounted) return;
    final result = await showDialog<RecurringExpense>(
      context: context,
      builder: (_) =>
          _RecurringDialog(existing: existing, categories: categories),
    );
    if (result == null) return;
    await _service.upsert(widget.user.id, result);
    final created = await _service.generateDue(widget.user.id);
    if (mounted && created > 0) {
      showAppSnackBar(context,
          '$created pengeluaran berulang yang sudah jatuh tempo dicatat.');
    }
    _reload();
  }

  Future<void> _delete(RecurringExpense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus "${e.name}"?'),
        content: const Text('Struk yang sudah tercatat tidak ikut terhapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    await _service.remove(widget.user.id, e.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran Berulang')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      body: FutureBuilder<List<RecurringExpense>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          final monthly = items
              .where((e) => e.active)
              .fold<double>(0, (s, e) => s + e.amount);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            children: [
              const Text(
                'Langganan, tagihan, atau iuran yang dibayar setiap bulan. Struknya dicatat '
                'otomatis pada tanggal jatuh tempo saat aplikasi dibuka.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textGrey, height: 1.4),
              ),
              const SizedBox(height: 14),
              if (items.isEmpty)
                const EmptyState(
                  title: 'Belum ada',
                  message:
                      'Contoh: Netflix Rp54.000 tanggal 5, kos Rp800.000 tanggal 1.',
                )
              else ...[
                Text('Total per bulan: ${Fmt.rupiah(monthly.round())}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.navy)),
                const SizedBox(height: 8),
                for (final e in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(AppCategories.iconOf(e.categoryName),
                          color: AppCategories.colorOf(e.categoryName)),
                      title: Text(e.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${e.categoryName} · tiap tanggal ${e.dayOfMonth}'
                          '${e.active ? '' : ' · dijeda'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(Fmt.rupiah(e.amount.round()),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') await _edit(e);
                              if (v == 'toggle') {
                                await _service.upsert(widget.user.id,
                                    e.copyWith(active: !e.active));
                                _reload();
                              }
                              if (v == 'delete') await _delete(e);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'edit', child: Text('Ubah')),
                              PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(e.active ? 'Jeda' : 'Aktifkan')),
                              const PopupMenuItem(
                                  value: 'delete', child: Text('Hapus')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RecurringDialog extends StatefulWidget {
  const _RecurringDialog({required this.categories, this.existing});

  final List<CategoryModel> categories;
  final RecurringExpense? existing;

  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late String _category;
  late int _day;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(
        text: e == null ? '' : Fmt.number(e.amount.round()));
    final names = widget.categories.map((c) => c.name).toList();
    _category = e?.categoryName ??
        (names.contains('Lainnya')
            ? 'Lainnya'
            : (names.isEmpty ? 'Lainnya' : names.first));
    _day = e?.dayOfMonth ?? DateTime.now().day;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final c in widget.categories) c.name,
      _category,
    }.toList();
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Pengeluaran berulang'
          : 'Ubah pengeluaran'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: _name,
                label: 'Nama (mis. Netflix, Kos, Internet)',
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              AppTextField(
                controller: _amount,
                label: 'Nominal per bulan',
                prefixText: 'Rp',
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                validator: (v) => (Fmt.parseAmount(v ?? '') ?? 0) <= 0
                    ? 'Nominal wajib diisi'
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  for (final n in names)
                    DropdownMenuItem(value: n, child: Text(n))
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _day,
                decoration: const InputDecoration(
                    labelText: 'Tanggal jatuh tempo tiap bulan'),
                items: [
                  for (int d = 1; d <= 31; d++)
                    DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) => setState(() => _day = v ?? _day),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final now = DateTime.now();
            final e = widget.existing;
            Navigator.pop(
              context,
              RecurringExpense(
                id: e?.id ?? now.microsecondsSinceEpoch.toString(),
                name: _name.text.trim(),
                amount: Fmt.parseAmount(_amount.text)!,
                categoryName: _category,
                dayOfMonth: _day,
                // Baru: mulai bulan ini (tidak mencatat bulan-bulan lalu).
                startMonth: e?.startMonth ?? DateTime(now.year, now.month),
                lastGenerated: e?.lastGenerated,
                active: e?.active ?? true,
              ),
            );
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
