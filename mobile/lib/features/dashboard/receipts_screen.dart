import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/receipt_tile.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/receipt_model.dart';
import '../../models/user_model.dart';
import 'receipt_detail_sheet.dart';

/// Riwayat seluruh struk ("Lihat semua" di Beranda).
class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  List<ReceiptModel> _receipts = [];
  bool _loading = true;
  String? _error;

  // Filter riwayat.
  final TextEditingController _queryCtl = TextEditingController();
  String _query = '';
  String? _category;
  DateTimeRange? _range;

  List<String> get _categoryNames {
    final names = <String>{
      for (final r in _receipts)
        for (final i in r.items)
          if (i.categoryName.isNotEmpty) i.categoryName,
    }.toList()
      ..sort();
    return names;
  }

  List<ReceiptModel> get _filtered {
    final q = _query.trim().toLowerCase();
    return _receipts.where((r) {
      if (_range != null) {
        final d = DateTime(r.transactionDate.year, r.transactionDate.month,
            r.transactionDate.day);
        if (d.isBefore(_range!.start) || d.isAfter(_range!.end)) return false;
      }
      if (_category != null &&
          !r.items.any((i) => i.categoryName == _category)) {
        return false;
      }
      if (q.isEmpty) return true;
      return r.merchantName.toLowerCase().contains(q) ||
          r.items.any((i) => i.itemName.toLowerCase().contains(q));
    }).toList();
  }

  bool get _hasFilter =>
      _query.isNotEmpty || _category != null || _range != null;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _range,
      helpText: 'Rentang tanggal',
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  void initState() {
    super.initState();
    AppState.dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.dataVersion.removeListener(_load);
    _queryCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await AppRepositories.instance.receipts.getReceipts(widget.user.id);
      if (!mounted) return;
      setState(() {
        _receipts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading && _receipts.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _receipts.isEmpty) {
      body = Center(child: ErrorState(message: _error!, onRetry: _load));
    } else if (_receipts.isEmpty) {
      body = const Center(
        child: EmptyState(
          title: 'Belum ada struk',
          message: 'Struk yang kamu simpan akan muncul di sini.',
        ),
      );
    } else {
      final list = _filtered;
      final total = list.fold<double>(0, (s, r) => s + r.totalAmount);
      body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: TextField(
              controller: _queryCtl,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Cari nama toko atau barang',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _queryCtl.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(_range == null
                        ? 'Semua tanggal'
                        : '${Fmt.shortDate(_range!.start)} - ${Fmt.shortDate(_range!.end)}'),
                    onPressed: _pickRange,
                  ),
                ),
                for (final c in _categoryNames)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (on) =>
                          setState(() => _category = on ? c : null),
                    ),
                  ),
              ],
            ),
          ),
          if (_hasFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        '${list.length} struk · ${Fmt.rupiah(total.round())}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _queryCtl.clear();
                      _query = '';
                      _category = null;
                      _range = null;
                    }),
                    child: const Text('Hapus filter'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: EmptyState(
                      title: 'Tidak ada yang cocok',
                      message:
                          'Coba kata kunci, kategori, atau rentang tanggal lain.',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = list[i];
                        return ReceiptTile(
                          receipt: r,
                          onTap: () => showReceiptDetailSheet(context,
                              user: widget.user, receipt: r),
                        );
                      },
                    ),
                  ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Semua Struk')),
      body: body,
    );
  }
}
