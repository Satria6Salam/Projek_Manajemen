import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/core/utils/receipt_parser.dart';
import 'package:strukku/features/scanner/image_enhancer.dart';
import 'package:strukku/features/scanner/receipt_selector.dart';

/// Gambar abu-abu sintetis: kertas terang dengan garis "tulisan" gelap.
Uint8List _receipt(int w, int h, {int blur = 0, int paper = 230, int ink = 30}) {
  final Uint8List px = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final bool text = (y % 12) < 4 && (x % 9) < 6 && x > 10 && x < w - 10;
      px[y * w + x] = text ? ink : paper;
    }
  }
  if (blur == 0) return px;
  // Blur kotak sederhana.
  final Uint8List out = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int sum = 0, n = 0;
      for (int dy = -blur; dy <= blur; dy++) {
        for (int dx = -blur; dx <= blur; dx++) {
          final int yy = y + dy, xx = x + dx;
          if (yy < 0 || yy >= h || xx < 0 || xx >= w) continue;
          sum += px[yy * w + xx];
          n++;
        }
      }
      out[y * w + x] = sum ~/ n;
    }
  }
  return out;
}

void main() {
  group('ImageEnhancer', () {
    test('foto tajam tidak ditandai buram', () {
      final r = const ImageEnhancer().enhance(_receipt(200, 200), 200, 200);
      expect(r.quality.isBlurry, isFalse);
    });

    test('foto buram terdeteksi dan kontras tinta dipertegas', () {
      final Uint8List blurred = _receipt(200, 200, blur: 3);
      final r = const ImageEnhancer().enhance(blurred, 200, 200);
      expect(r.quality.isBlurry, isTrue);
      expect(r.quality.notes, contains('foto buram'));
      int darkBefore = 0, darkAfter = 0;
      for (int i = 0; i < blurred.length; i++) {
        if (blurred[i] < 100) darkBefore++;
        if (r.pixels[i] < 100) darkAfter++;
      }
      expect(darkAfter, greaterThan(darkBefore));
    });

    test('foto gelap terdeteksi', () {
      final r = const ImageEnhancer()
          .enhance(_receipt(120, 120, paper: 80, ink: 20), 120, 120);
      expect(r.quality.isDark, isTrue);
    });
  });

  group('ReceiptSelector', () {
    const selector = ReceiptSelector();
    final ReceiptReading weak = ReceiptReading(
      rawText: 'INDOMRT\nTOTL 2.000',
      parsed: const ParsedReceipt(totalAmount: 2000),
    );
    final ReceiptReading strong = ReceiptReading(
      rawText: 'INDOMARET\n21/10/2026\nROTI 10.000\nSUSU 5.000\nTOTAL 15.000',
      parsed: ParsedReceipt(
        merchantName: 'INDOMARET',
        transactionDate: DateTime(2026, 10, 21),
        totalAmount: 15000,
        items: const [ParsedItem('ROTI', 10000), ParsedItem('SUSU', 5000)],
      ),
      fromEnhancedImage: true,
    );

    test('hasil lengkap dan cocok dianggap selesai', () {
      expect(selector.isComplete(strong.parsed), isTrue);
      expect(selector.isComplete(weak.parsed), isFalse);
    });

    test('memilih bacaan dari foto yang diperjelas bila lebih baik', () {
      final chosen = selector.choose(weak, strong);
      expect(chosen.fromEnhancedImage, isTrue);
      expect(chosen.parsed.items, hasLength(2));
    });

    test('foto asli dipertahankan bila hasil diperjelas lebih buruk', () {
      final chosen = selector.choose(strong, weak);
      expect(chosen.parsed.merchantName, 'INDOMARET');
    });
  });
}
