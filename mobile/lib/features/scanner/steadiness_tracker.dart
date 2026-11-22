import 'dart:math' as math;

/// Menilai apakah HP sedang diam dari data akselerometer (tanpa gravitasi).
///
/// Foto struk yang diambil saat HP bergerak hampir pasti buram (goyang), dan
/// foto goyang berat tidak bisa diperbaiki oleh pengolahan gambar apa pun.
/// Karena itu kamera menunggu HP diam sebelum memotret.
///
/// Logika murni (tanpa plugin) agar bisa diuji: panggil [add] setiap ada
/// pembacaan sensor, lalu baca [isSteady] / [steadyFor].
class SteadinessTracker {
  SteadinessTracker({
    this.threshold = 0.35,
    this.window = const Duration(milliseconds: 400),
  });

  /// Rata-rata percepatan (m/s²) di bawah nilai ini dianggap diam.
  final double threshold;

  /// Lama jendela rata-rata.
  final Duration window;

  final List<_Sample> _samples = <_Sample>[];
  DateTime? _steadySince;

  /// [x], [y], [z] = percepatan pengguna (tanpa gravitasi), m/s².
  void add(double x, double y, double z, DateTime at) {
    _samples.add(_Sample(at, math.sqrt(x * x + y * y + z * z)));
    final cutoff = at.subtract(window);
    _samples.removeWhere((s) => s.at.isBefore(cutoff));
    if (level < threshold) {
      _steadySince ??= at;
    } else {
      _steadySince = null;
    }
  }

  /// Rata-rata gerakan dalam jendela terakhir.
  double get level {
    if (_samples.isEmpty) return double.infinity;
    return _samples.map((s) => s.magnitude).reduce((a, b) => a + b) /
        _samples.length;
  }

  bool get isSteady => _steadySince != null;

  /// Berapa lama HP sudah diam (Duration.zero bila sedang bergerak).
  Duration steadyFor(DateTime now) =>
      _steadySince == null ? Duration.zero : now.difference(_steadySince!);

  void reset() {
    _samples.clear();
    _steadySince = null;
  }
}

class _Sample {
  const _Sample(this.at, this.magnitude);
  final DateTime at;
  final double magnitude;
}

/// Keputusan setelah foto diambil: apakah sebaiknya foto ulang?
class CaptureVerdict {
  const CaptureVerdict({required this.retake, required this.reasons});

  final bool retake;
  final List<String> reasons;

  /// Foto sangat buram/goyang atau gelap berat -> sarankan foto ulang.
  /// (Buram ringan masih bisa diperjelas otomatis, jadi tidak ditolak.)
  static CaptureVerdict judge({
    required double blurLevel,
    required bool isDark,
    required double brightness,
  }) {
    final reasons = <String>[
      if (blurLevel >= 0.6) 'foto buram/goyang',
      if (isDark && brightness < 70) 'foto terlalu gelap',
    ];
    return CaptureVerdict(retake: reasons.isNotEmpty, reasons: reasons);
  }
}
