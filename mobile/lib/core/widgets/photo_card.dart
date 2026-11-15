import 'package:flutter/material.dart';

import '../constants/app_categories.dart';

/// Kartu berlatar foto penuh dengan gradasi gelap agar teks putih terbaca.
class PhotoCard extends StatelessWidget {
  const PhotoCard({
    super.key,
    required this.photo,
    required this.child,
    this.color = const Color(0xFF2160DD),
    this.onTap,
    this.height,
    this.radius = 20,
    this.padding = const EdgeInsets.all(14),
    this.overlay = 0.90,
  });

  /// Path asset foto.
  final String photo;
  final Widget child;

  /// Warna aksen (bayangan & tint).
  final Color color;
  final VoidCallback? onTap;
  final double? height;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Kepekatan gradasi gelap di bagian bawah (0-1).
  final double overlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 22,
              spreadRadius: -4,
              offset: const Offset(0, 12)),
          BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(
          color: Colors.black,
          child: Ink(
            decoration: BoxDecoration(
              image:
                  DecorationImage(image: AssetImage(photo), fit: BoxFit.cover),
            ),
            child: InkWell(
              onTap: onTap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Lebih gelap: lapisan gelap merata di seluruh foto,
                    // makin pekat ke bawah tempat teks berada.
                    colors: [
                      Color.alphaBlend(color.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.40)),
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: overlay),
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lencana ikon bulat berwarna untuk dipasang di atas foto.
class PhotoIconBadge extends StatelessWidget {
  const PhotoIconBadge(
      {super.key, required this.icon, required this.color, this.size = 36});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.55),
    );
  }
}

/// Foto latar untuk setiap kategori (assets/images/cat_*.jpg).
String categoryPhoto(String name) {
  switch (name.replaceAll('_', ' ')) {
    case AppCategories.makanan:
    case AppCategories.fnb:
      return 'assets/images/cat_makanan.jpg';
    case AppCategories.minuman:
      return 'assets/images/cat_minuman.jpg';
    case AppCategories.rumahTangga:
      return 'assets/images/cat_rumah_tangga.jpg';
    case AppCategories.perawatanDiri:
      return 'assets/images/cat_perawatan_diri.jpg';
    case AppCategories.kesehatan:
      return 'assets/images/cat_kesehatan.jpg';
    default:
      return 'assets/images/cat_lainnya.jpg';
  }
}

/// Kartu putih elegan dengan bayangan lembut (tanpa garis tepi tebal).
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0F1F3D).withValues(alpha: 0.07),
              blurRadius: 24,
              spreadRadius: -6,
              offset: const Offset(0, 10)),
          BoxShadow(
              color: const Color(0xFF0F1F3D).withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Judul bagian dengan garis aksen kecil.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF2160DD),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: Color(0xFF0F1F3D))),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
