import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repository_provider.dart';
import '../dashboard/month_picker_sheet.dart';
import '../../models/receipt_model.dart';
import 'xlsx_report.dart';

/// Ekspor laporan bulanan ke Excel (.xlsx); CSV tetap tersedia lewat [buildCsv].
///
/// Pemisah titik koma (;) dan BOM UTF-8 agar Excel berbahasa Indonesia
/// langsung membaca kolom & huruf dengan benar.
class ExportService {
  const ExportService();

  static const String _sep = ';';

  String _cell(Object? value) {
    final text = '${value ?? ''}';
    if (text.contains(_sep) || text.contains('"') || text.contains('\n')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Satu baris per barang, ditambah ringkasan per kategori di bawahnya.
  String buildCsv(List<ReceiptModel> receipts) {
    final rows = <List<Object?>>[
      [
        'Tanggal',
        'Jam',
        'Toko',
        'Total struk',
        'Barang',
        'Jumlah',
        'Harga barang',
        'Kategori',
        'Dikoreksi'
      ],
    ];
    final byCategory = <String, double>{};
    double total = 0;
    for (final r in receipts) {
      total += r.totalAmount;
      if (r.items.isEmpty) {
        rows.add([
          _date(r.transactionDate),
          _time(r.transactionDate),
          r.merchantName,
          r.totalAmount.round(),
          '',
          '',
          '',
          '',
          ''
        ]);
      }
      for (final i in r.items) {
        byCategory[i.categoryName] =
            (byCategory[i.categoryName] ?? 0) + i.itemPrice;
        rows.add([
          _date(r.transactionDate),
          _time(r.transactionDate),
          r.merchantName,
          r.totalAmount.round(),
          i.itemName,
          i.quantity,
          i.itemPrice.round(),
          i.categoryName,
          i.isUserCorrected ? 'ya' : '',
        ]);
      }
    }
    rows
      ..add([])
      ..add(['Ringkasan per kategori'])
      ..add(['Kategori', 'Total'])
      ..addAll((byCategory.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => [e.key, e.value.round()]))
      ..add(['Total semua struk', total.round()])
      ..add(['Jumlah struk', receipts.length]);
    return rows.map((r) => r.map(_cell).join(_sep)).join('\r\n');
  }

  /// Buat file CSV untuk [month] lalu buka lembar bagikan (WhatsApp, Drive, email, ...).
  /// Mengembalikan jumlah struk yang diekspor.
  Future<int> shareMonth(int userId, DateTime month) async {
    final receipts = await AppRepositories.instance.receipts
        .getReceipts(userId, month: DateTime(month.year, month.month));
    receipts.sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
    // Tidak ada struk: jangan bagikan file kosong.
    if (receipts.isEmpty) return 0;
    final ym = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'Laporan_STRUKKU_$ym.xlsx'));
    await file.writeAsBytes(const XlsxReport().build(receipts, month), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile(file.path,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      ],
      subject: 'Laporan pengeluaran STRUKKU ${Fmt.monthYear(month)}',
      text: 'Laporan pengeluaran STRUKKU ${Fmt.monthYear(month)} (${receipts.length} struk).',
    ));
    return receipts.length;
  }

  /// Pilih bulan (hanya bulan yang punya struk), lalu ekspor & bagikan.
  Future<void> pickAndShare(BuildContext context, int userId) async {
    try {
      final months = await AppRepositories.instance.receipts.availableMonths(userId);
      if (!context.mounted) return;
      if (months.isEmpty) {
        showAppSnackBar(context, 'Belum ada struk untuk diekspor.');
        return;
      }
      final chosen = await showMonthPicker(context, months: months, selected: months.first);
      if (chosen == null || !context.mounted) return;
      final count = await shareMonth(userId, chosen);
      if (context.mounted && count == 0) {
        showAppSnackBar(context, 'Belum ada struk pada ${Fmt.monthYear(chosen)}.');
      }
    } catch (e) {
      if (context.mounted) showAppSnackBar(context, 'Ekspor gagal: $e', error: true);
    }
  }
}
