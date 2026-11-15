import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/constants/app_categories.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repository_provider.dart';
import '../../models/receipt_item_model.dart';
import '../../models/receipt_model.dart';
import '../../models/user_model.dart';
import '../insights/price_history_screen.dart';
import '../stores/maps_launcher.dart';

/// Detail satu struk (item, kategori, confidence) + tombol hapus.
Future<void> showReceiptDetailSheet(
  BuildContext context, {
  required UserModel user,
  required ReceiptModel receipt,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => _ReceiptDetail(user: user, receipt: receipt),
  );
}

class _ReceiptDetail extends StatelessWidget {
  const _ReceiptDetail({required this.user, required this.receipt});

  final UserModel user;
  final ReceiptModel receipt;

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus struk?'),
        content:
            Text('Struk ${receipt.merchantName} akan dihapus dari data Anda.'),
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
    if (ok != true || !context.mounted) return;
    try {
      await AppRepositories.instance.receipts
          .deleteReceipt(user.id, receipt.id!);
      AppState.dataVersion.value++;
      if (context.mounted) {
        // Snackbar ditampilkan lewat ScaffoldMessenger root, jadi tetap terlihat
        // setelah sheet ditutup.
        showAppSnackBar(context, 'Struk dihapus.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Gagal menghapus: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(receipt.merchantName,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy)),
          const SizedBox(height: 2),
          Text(Fmt.longDate(receipt.transactionDate),
              style: const TextStyle(color: AppColors.textGrey)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => MapsLauncher.open(
                receipt.merchantName, receipt.merchantAddress),
            child: Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    receipt.merchantAddress ?? 'Cari lokasi toko di Maps',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.primary),
                  ),
                ),
                const Icon(Icons.open_in_new,
                    size: 16, color: AppColors.primary),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(Fmt.rupiah(receipt.totalAmount),
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          if (receipt.imageUrl != null) ...[
            const SizedBox(height: 14),
            _ReceiptPhoto(url: receipt.imageUrl!),
          ],
          const SizedBox(height: 18),
          Text('Daftar belanja (${receipt.items.length} item)',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.navy)),
          const SizedBox(height: 8),
          for (final item in receipt.items)
            _ItemRow(
              item: item,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PriceHistoryScreen(
                  user: user,
                  // Dua kata pertama cukup untuk mencocokkan varian barang yang sama.
                  initialQuery:
                      item.itemName.split(RegExp(r'\s+')).take(2).join(' '),
                ),
              )),
            ),
          if (receipt.items.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                  'Ketuk barang untuk membandingkan harganya di toko lain.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGrey)),
            ),
          if ((receipt.itemsSum - receipt.totalAmount).abs() > 0.5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Jumlah item ${Fmt.rupiah(receipt.itemsSum)} berbeda dari total struk '
                  '(mis. pajak atau biaya lain).',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textGrey)),
            ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            label: const Text('Hapus struk',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.onTap});

  final ReceiptItemModel item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final info = item.isUserCorrected
        ? 'Dikoreksi manual'
        : item.confidenceScore != null
            ? 'Kategori otomatis \u00B7 ${Fmt.percent(item.confidenceScore!)}'
            : 'Dipilih manual';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(AppCategories.iconOf(item.categoryName),
                color: AppCategories.colorOf(item.categoryName), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      item.quantity > 1
                          ? '${item.quantity}× ${item.itemName}'
                          : item.itemName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.navy)),
                  Text('${item.categoryName} \u00B7 $info',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textGrey)),
                ],
              ),
            ),
            Text(Fmt.rupiah(item.itemPrice),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.navy)),
          ],
        ),
      ),
    );
  }
}

/// Foto struk: dari server (butuh header Authorization) atau file di HP.
class _ReceiptPhoto extends StatelessWidget {
  const _ReceiptPhoto({required this.url});

  final String url;

  bool get _isRemote => url.startsWith('http://') || url.startsWith('https://');

  Widget _image({BoxFit fit = BoxFit.cover}) {
    Widget error(BuildContext context, Object e, StackTrace? s) => Container(
          color: AppColors.primarySoft,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: const Text('Foto struk tidak dapat dimuat.',
              style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
        );
    if (_isRemote) {
      return Image.network(
        url,
        fit: fit,
        headers: AppRepositories.instance.client?.authHeaders,
        errorBuilder: error,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final file = File(url);
    return Image.file(file, fit: fit, errorBuilder: error);
  }

  void _openFull(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Foto struk'),
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: _image(fit: BoxFit.contain)),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openFull(context),
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            SizedBox(height: 160, width: double.infinity, child: _image()),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in, size: 16, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Lihat foto',
                        style: TextStyle(fontSize: 12, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
