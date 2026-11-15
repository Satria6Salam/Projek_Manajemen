import 'package:flutter/material.dart';

import '../../models/receipt_model.dart';
import '../constants/app_colors.dart';
import '../constants/app_categories.dart';
import '../utils/formatters.dart';
import 'photo_card.dart';

/// Pilih ikon struk dari nama merchant, jika tidak cocok pakai kategori utama.
IconData receiptIcon(ReceiptModel r) {
  final m = r.merchantName.toLowerCase();
  if (m.contains('kopi') || m.contains('coffee') || m.contains('cafe')) {
    return Icons.local_cafe_outlined;
  }
  if (m.contains('grab') ||
      m.contains('gojek') ||
      m.contains('kai') ||
      m.contains('bus')) {
    return Icons.directions_bus_outlined;
  }
  if (m.contains('apotek') || m.contains('kimia') || m.contains('guardian')) {
    return Icons.favorite_border;
  }
  return Icons.shopping_bag_outlined;
}

/// Satu baris struk (merchant, tanggal, total) seperti pada Figma.
class ReceiptTile extends StatelessWidget {
  const ReceiptTile({super.key, required this.receipt, this.onTap});

  final ReceiptModel receipt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final category = receipt.mainCategoryName;
    final color =
        category == null ? AppColors.primary : AppCategories.colorOf(category);
    return SoftCard(
      radius: 18,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(categoryPhoto(category ?? 'Lainnya'),
                      fit: BoxFit.cover),
                  DecoratedBox(
                    decoration:
                        BoxDecoration(color: color.withValues(alpha: 0.35)),
                  ),
                  Icon(receiptIcon(receipt), color: Colors.white, size: 24),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(receipt.merchantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.2,
                        color: AppColors.navy)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(Fmt.shortDate(receipt.transactionDate),
                        style: const TextStyle(
                            color: AppColors.textGrey, fontSize: 12)),
                    if (category != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: color)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(Fmt.rupiah(receipt.totalAmount),
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.navy)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
