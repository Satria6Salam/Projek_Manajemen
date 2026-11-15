import 'package:url_launcher/url_launcher.dart';

/// Membuka Google Maps (aplikasi atau browser) dengan pencarian nama toko + alamat.
/// Tanpa API key: pengguna sendiri yang memilih hasil yang tepat di Maps.
class MapsLauncher {
  const MapsLauncher._();

  static Uri searchUri(String merchantName, String? address) {
    final query = [
      merchantName,
      if (address != null && address.trim().isNotEmpty) address
    ].join(', ');
    return Uri.https(
        'www.google.com', '/maps/search/', {'api': '1', 'query': query});
  }

  /// Mengembalikan false bila tidak ada aplikasi yang bisa membuka tautan.
  static Future<bool> open(String merchantName, String? address) =>
      launchUrl(searchUri(merchantName, address),
          mode: LaunchMode.externalApplication);
}
