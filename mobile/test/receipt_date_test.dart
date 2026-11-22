import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/core/utils/receipt_parser.dart';
import 'package:strukku/features/scanner/steadiness_tracker.dart';

void main() {
  DateTime? dateOf(String line) =>
      ReceiptParser.parse('TOKO MAJU\n$line\nTEH 5.000\nTOTAL 5.000')
          .transactionDate;

  test('tanggal dengan huruf mirip angka dan spasi', () {
    expect(dateOf('Tgl 19/1O/2O26'), DateTime(2026, 10, 19));
    expect(dateOf('19 / 10 / 2026'), DateTime(2026, 10, 19));
  });

  test('tanggal bulan di depan dan berlabel tanpa pemisah', () {
    expect(dateOf('Okt 19, 2026'), DateTime(2026, 10, 19));
    expect(dateOf('Tgl 19102026'), DateTime(2026, 10, 19));
  });

  test('foto sangat buram wajib foto ulang', () {
    final v =
        CaptureVerdict.judge(blurLevel: 0.7, isDark: false, brightness: 150);
    expect(v.mustRetake, isTrue);
    final mild =
        CaptureVerdict.judge(blurLevel: 0.45, isDark: false, brightness: 150);
    expect(mild.retake, isTrue);
    expect(mild.mustRetake, isFalse);
  });
}
