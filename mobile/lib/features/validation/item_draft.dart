import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/utils/formatters.dart';

/// Satu baris barang yang sedang diedit di halaman Koreksi & Validasi.
class ItemDraft {
  ItemDraft({
    required String name,
    double? price,
    this.categoryId,
    this.confidence,
    this.quantity = 1,
    this.unitPrice,
    this.predictedCategoryId,
    this.predictionSource,
  })  : originalCategoryId = categoryId,
        nameCtl = TextEditingController(text: name),
        priceCtl =
            TextEditingController(text: price == null ? '' : Fmt.number(price));

  final TextEditingController nameCtl;

  /// Harga total baris (qty x harga satuan).
  final TextEditingController priceCtl;

  /// Kategori terpilih saat ini (null = belum dipilih).
  int? categoryId;

  /// Kategori prediksi awal (null jika item ditambah manual / tanpa prediksi).
  int? originalCategoryId;

  /// confidence_score prediksi ML (null untuk item manual).
  double? confidence;

  /// Jumlah barang (dibaca server dari struk, bisa diubah pengguna).
  int quantity;

  /// Harga satuan dari struk (null bila tidak tercetak / tidak terbaca).
  double? unitPrice;

  /// Kategori & sumber prediksi server, dikirim balik saat menyimpan.
  int? predictedCategoryId;
  String? predictionSource;

  /// Nama terakhir yang sudah ditebak kategorinya (hindari tebakan berulang).
  String? guessedFor;

  double get price => Fmt.parseAmount(priceCtl.text) ?? 0;

  /// Ubah jumlah; bila harga satuan diketahui, harga total ikut dihitung ulang.
  void setQuantity(int value) {
    final int next = value < 1 ? 1 : (value > 9999 ? 9999 : value);
    final double? unit =
        unitPrice ?? (quantity > 0 && price > 0 ? price / quantity : null);
    quantity = next;
    if (unit != null) {
      unitPrice = unit;
      priceCtl.text = Fmt.number((unit * next).round());
    }
  }

  /// true jika pengguna mengganti kategori hasil prediksi (is_user_corrected).
  bool get isUserCorrected =>
      originalCategoryId != null &&
      categoryId != null &&
      categoryId != originalCategoryId;

  /// Perlu diperiksa: kategori belum dipilih, atau confidence di bawah ambang
  /// dan belum dikoreksi pengguna. (Ambang: AppConfig.lowConfidenceThreshold)
  bool get needsCheck {
    if (categoryId == null) return true;
    final c = confidence;
    return c != null &&
        c < AppConfig.lowConfidenceThreshold &&
        !isUserCorrected;
  }

  void dispose() {
    nameCtl.dispose();
    priceCtl.dispose();
  }
}
