import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'image_enhancer.dart';

/// Foto struk yang sudah diperjelas dan siap dibaca ulang oleh OCR.
class EnhancedImage {
  const EnhancedImage({required this.path, required this.quality});

  /// Lokasi file sementara hasil perbaikan.
  final String path;

  /// Mutu foto aslinya.
  final ImageQuality quality;
}

class _EnhanceInput {
  const _EnhanceInput(this.bytes, this.forceSharpen);

  final Uint8List bytes;
  final bool forceSharpen;
}

class _EnhanceOutput {
  const _EnhanceOutput(this.jpg, this.quality);

  final Uint8List jpg;
  final ImageQuality quality;
}

/// Memperjelas foto struk yang buram, pudar, gelap, atau berbayang sebelum OCR.
/// Pengolahan piksel dijalankan di isolate agar antarmuka tidak tersendat.
class ImageEnhancementService {
  /// Sisi terpanjang gambar saat diolah (menjaga waktu dan memori).
  static const int maxSide = 1800;

  /// Foto kecil diperbesar sampai sisi terpanjang ini: huruf buram yang
  /// lebih besar lebih mudah dikenali ML Kit.
  static const int minSide = 1400;

  /// Mengembalikan null bila format gambar tidak dapat diolah (mis. HEIC);
  /// pemanggil cukup memakai hasil OCR dari foto asli.
  Future<EnhancedImage?> enhance(String imagePath,
      {bool forceSharpen = false}) async {
    try {
      final Uint8List bytes = await File(imagePath).readAsBytes();
      final _EnhanceOutput? output =
          await compute(_enhanceBytes, _EnhanceInput(bytes, forceSharpen));
      if (output == null) return null;

      final Directory directory = await getTemporaryDirectory();
      final String name =
          'enhanced_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final File file = File(p.join(directory.path, name));
      await file.writeAsBytes(output.jpg, flush: true);
      return EnhancedImage(path: file.path, quality: output.quality);
    } catch (e) {
      debugPrint('[STRUKKU] perbaikan foto gagal: $e');
      return null;
    }
  }

  /// Ukur mutu foto saja (buram/gelap/pudar) tanpa menulis file, untuk
  /// memutuskan apakah pengguna sebaiknya memotret ulang. null = gagal diukur.
  Future<ImageQuality?> assess(String imagePath) async {
    try {
      final Uint8List bytes = await File(imagePath).readAsBytes();
      return await compute(_assessBytes, bytes);
    } catch (e) {
      debugPrint('[STRUKKU] pengukuran mutu foto gagal: $e');
      return null;
    }
  }

  /// Menghapus file sementara hasil perbaikan.
  Future<void> discard(EnhancedImage image) async {
    try {
      final File file = File(image.path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // File sementara; kegagalan menghapus tidak perlu ditampilkan.
    }
  }
}

/// Mutu foto diukur pada ukuran tetap (sisi terpanjang 1400 px), sama dengan
/// ukuran minimum saat foto diperjelas, agar ambang buram tetap sebanding.
ImageQuality? _assessBytes(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  img.Image image = img.bakeOrientation(decoded);
  final bool landscape = image.width >= image.height;
  image = landscape
      ? img.copyResize(image,
          width: ImageEnhancementService.minSide,
          interpolation: img.Interpolation.average)
      : img.copyResize(image,
          height: ImageEnhancementService.minSide,
          interpolation: img.Interpolation.average);
  final int width = image.width;
  final int height = image.height;
  final Uint8List gray = Uint8List(width * height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final img.Pixel pixel = image.getPixel(x, y);
      final double luminance =
          0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      gray[y * width + x] =
          luminance <= 0 ? 0 : (luminance >= 255 ? 255 : luminance.round());
    }
  }
  return const ImageEnhancer().enhance(gray, width, height).quality;
}

_EnhanceOutput? _enhanceBytes(_EnhanceInput input) {
  final img.Image? decoded = img.decodeImage(input.bytes);
  if (decoded == null) return null;

  img.Image image = img.bakeOrientation(decoded);
  final int longest = image.width > image.height ? image.width : image.height;
  int? target;
  if (longest > ImageEnhancementService.maxSide) {
    target = ImageEnhancementService.maxSide;
  } else if (longest < ImageEnhancementService.minSide) {
    target = ImageEnhancementService.minSide;
  }
  if (target != null) {
    final img.Interpolation interpolation =
        longest > target ? img.Interpolation.average : img.Interpolation.cubic;
    image = image.width >= image.height
        ? img.copyResize(image, width: target, interpolation: interpolation)
        : img.copyResize(image, height: target, interpolation: interpolation);
  }

  final int width = image.width;
  final int height = image.height;
  final Uint8List gray = Uint8List(width * height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final img.Pixel pixel = image.getPixel(x, y);
      final double luminance =
          0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      gray[y * width + x] =
          luminance <= 0 ? 0 : (luminance >= 255 ? 255 : luminance.round());
    }
  }

  final EnhancedPixels result = const ImageEnhancer()
      .enhance(gray, width, height, forceSharpen: input.forceSharpen);

  final img.Image output = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int value = result.pixels[y * width + x];
      output.setPixelRgb(x, y, value, value, value);
    }
  }
  return _EnhanceOutput(img.encodeJpg(output, quality: 92), result.quality);
}
