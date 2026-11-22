import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/features/scanner/steadiness_tracker.dart';

void main() {
  final t0 = DateTime(2026, 11, 22, 10);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('HP diam terdeteksi setelah gerakan kecil berturut-turut', () {
    final s = SteadinessTracker();
    for (var ms = 0; ms <= 1500; ms += 60) {
      s.add(0.05, 0.03, 0.04, at(ms));
    }
    expect(s.isSteady, isTrue);
    expect(s.steadyFor(at(1500)),
        greaterThanOrEqualTo(const Duration(milliseconds: 1200)));
  });

  test('guncangan membatalkan status diam', () {
    final s = SteadinessTracker();
    for (var ms = 0; ms <= 600; ms += 60) {
      s.add(0.05, 0.05, 0.05, at(ms));
    }
    expect(s.isSteady, isTrue);
    for (var ms = 660; ms <= 900; ms += 60) {
      s.add(2.5, 1.8, 0.9, at(ms));
    }
    expect(s.isSteady, isFalse);
    expect(s.steadyFor(at(900)), Duration.zero);
  });

  test('foto sangat buram atau terlalu gelap disarankan foto ulang', () {
    expect(
        CaptureVerdict.judge(blurLevel: 0.8, isDark: false, brightness: 180)
            .retake,
        isTrue);
    expect(
        CaptureVerdict.judge(blurLevel: 0.0, isDark: true, brightness: 50)
            .retake,
        isTrue);
    // Buram ringan masih bisa diperjelas otomatis -> tidak ditolak.
    final ok =
        CaptureVerdict.judge(blurLevel: 0.3, isDark: true, brightness: 100);
    expect(ok.retake, isFalse);
    expect(ok.reasons, isEmpty);
  });

  test('pantulan cahaya dan struk terlalu jauh disarankan foto ulang', () {
    final glare = CaptureVerdict.judge(
        blurLevel: 0, isDark: false, brightness: 200, glareRatio: 0.3);
    expect(glare.retake, isTrue);
    expect(glare.reasons.single, contains('pantulan'));
    final far = CaptureVerdict.judge(
        blurLevel: 0, isDark: false, brightness: 90, paperFill: 0.1);
    expect(far.reasons.single, contains('jauh'));
    expect(
        CaptureVerdict.judge(
                blurLevel: 0,
                isDark: false,
                brightness: 200,
                glareRatio: 0.05,
                paperFill: 0.6)
            .retake,
        isFalse);
  });
}
