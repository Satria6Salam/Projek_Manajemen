import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motif ikon berulang yang samar dan sedikit miring, digambar oleh kode
/// (tanpa gambar tambahan). Dipakai sebagai latar kartu.
class IconPatternPainter extends CustomPainter {
  IconPatternPainter({
    required this.icons,
    required this.color,
    this.iconSize = 22,
    this.spacing = 46,
    this.angle = -0.35,
  });

  final List<IconData> icons;
  final Color color;
  final double iconSize;
  final double spacing;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    if (icons.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final diagonal =
        math.sqrt(size.width * size.width + size.height * size.height);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    var row = 0;
    for (double y = -diagonal / 2; y < diagonal / 2; y += spacing, row++) {
      final offsetX = row.isEven ? 0.0 : spacing / 2;
      var col = 0;
      for (double x = -diagonal / 2 + offsetX;
          x < diagonal / 2;
          x += spacing, col++) {
        final icon = icons[(row + col) % icons.length];
        final painter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: iconSize,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant IconPatternPainter old) =>
      old.color != color || old.icons != icons || old.iconSize != iconSize;
}

/// Kartu dengan latar bermotif: gradasi warna + motif ikon samar,
/// atau foto (asset) dengan lapisan warna agar teks tetap terbaca.
class DecoratedCard extends StatelessWidget {
  const DecoratedCard({
    super.key,
    required this.child,
    required this.color,
    this.icons = const [Icons.receipt_long_outlined],
    this.photo,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.dark = false,
    this.onTap,
    this.border,
  });

  final Widget child;

  /// Warna utama kartu.
  final Color color;

  /// Ikon untuk motif latar.
  final List<IconData> icons;

  /// Path asset foto latar (opsional).
  final String? photo;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// true = kartu gelap (teks putih), false = kartu terang berwarna lembut.
  final bool dark;
  final VoidCallback? onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final deep =
        hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();
    final gradient = dark
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: photo == null ? 1 : 0.92),
              deep.withValues(alpha: photo == null ? 1 : 0.97)
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.13),
              color.withValues(alpha: 0.04)
            ],
          );
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          if (photo != null)
            Positioned.fill(child: Image.asset(photo!, fit: BoxFit.cover)),
          Positioned.fill(
              child:
                  DecoratedBox(decoration: BoxDecoration(gradient: gradient))),
          Positioned.fill(
            child: CustomPaint(
              painter: IconPatternPainter(
                icons: icons,
                color: dark
                    ? Colors.white.withValues(alpha: 0.07)
                    : color.withValues(alpha: 0.09),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: dark ? deep : Colors.white,
        border: dark
            ? null
            : Border.all(color: border ?? color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: dark ? 0.30 : 0.10),
            blurRadius: dark ? 18 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}
