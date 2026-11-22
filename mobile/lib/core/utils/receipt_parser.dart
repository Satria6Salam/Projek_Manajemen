import 'formatters.dart';

/// Satu baris barang hasil parsing teks OCR.
class ParsedItem {
  const ParsedItem(this.name, this.price,
      {this.quantity = 1,
      this.unitPrice,
      this.priceCorrected = false,
      this.nameCorrected = false,
      this.suspicious = false});

  final String name;

  /// Harga total baris (qty x harga satuan).
  final double price;
  final int quantity;
  final double? unitPrice;

  /// Harga diubah otomatis (diduga salah baca OCR) -> tandai untuk dicek.
  final bool priceCorrected;

  /// Nama diperbaiki otomatis (huruf hilang / koreksi pengguna sebelumnya).
  final bool nameCorrected;

  /// Tampak janggal (harga tidak lazim / sisa angka di nama) -> minta dicek.
  final bool suspicious;
}

/// Hasil parsing teks OCR struk. Semua field boleh null jika tidak ditemukan.
class ParsedReceipt {
  const ParsedReceipt({
    this.merchantName,
    this.merchantAddress,
    this.transactionDate,
    this.totalAmount,
    this.items = const [],
  });

  final String? merchantName;

  /// Alamat toko (baris alamat di bagian atas struk), bila ada.
  final String? merchantAddress;
  final DateTime? transactionDate;
  final double? totalAmount;
  final List<ParsedItem> items;

  bool get isEmpty =>
      merchantName == null &&
      transactionDate == null &&
      totalAmount == null &&
      items.isEmpty;
}

/// Parsing teks mentah OCR menjadi merchant, tanggal, total, dan daftar barang
/// menggunakan aturan regex (tahap "Smart Parsing" pada flowchart).
class ReceiptParser {
  ReceiptParser._();

  static final RegExp _isoDate = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})');
  static final RegExp _textDate =
      RegExp(r'(\d{1,2})\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})');
  static final RegExp _numericDate =
      RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})');
  static final RegExp _numberToken = RegExp(r'^[\d.,]+$');
  static final RegExp _rpPrefix = RegExp(r'\bRp\.?\s*', caseSensitive: false);

  /// Baris yang bukan barang (ringkasan pembayaran, metode bayar, info struk).
  static final RegExp _skipLine = RegExp(
    r'\b(total|subtotal|sub total|grand total|tunai|cash|kembali|kembalian|change|bayar|'
    r'ppn|pajak|tax|pb1|diskon|discount|disc|kasir|cashier|npwp|telp|tel|phone|hp|wa|'
    r'kartu|debit|kredit|credit|card|qris|member|edc|transfer|bca|bri|bni|mandiri|cimb|'
    r'btn|bsi|permata|ovo|gopay|go-pay|dana|shopeepay|linkaja|flazz|brizzi|tapcash|'
    r'e-money|emoney|visa|mastercard|service|biaya|pembulatan|rounding|sisa|receipt|'
    r'order|bill|invoice|collected|table|meja|notes?|admin|saldo|poin|point|voucher|waktu|pukul)\b'
    r'|terima kasih|thank|struk|harga jual|jumlah item|total item|www\.|\.com|\S+@\S+\.\S+',
    caseSensitive: false,
  );

  /// Baris alamat toko (OCR sering membaca "Jl." sebagai "J1." / "Ji.").
  static final RegExp _addressLine = RegExp(
    r'(^|[\s,])(j[l1i]\.|jl\b|jln\b|jalan\b|kec\.|kec\b|kecamatan|kel\.|kelurahan|'
    r'kab\.|kabupaten|kota\b|provinsi|desa\b|blok\b|ruko\b|gedung|'
    r'jawa|sumatera|sumatra|kalimantan|sulawesi|bali\b|papua|dki\b|diy\b|'
    r'rt\.?\s*\d|rw\.?\s*\d|no\.\s*\d)'
    r'|,\s*\d{5}\b',
    caseSensitive: false,
  );

  /// Token jumlah / harga satuan di akhir nama, mis. "x1", "2x", "3", "@3.500".
  static final RegExp _qtyToken =
      RegExp(r'^(x\d+|\d+x|x|@[\d.,]*|\d{1,3})$', caseSensitive: false);

  static bool _isNonItem(String line) =>
      _skipLine.hasMatch(line) || _addressLine.hasMatch(line);

  static const Map<String, int> _monthByPrefix = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'mei': 5,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'agu': 8,
    'aug': 8,
    'sep': 9,
    'okt': 10,
    'oct': 10,
    'nov': 11,
    'des': 12,
    'dec': 12,
  };

  // ------------------------------------------------------- normalisasi baris
  static final RegExp _qtyUnit = RegExp(
      r'\b(\d{1,3})\s*(?:pcs|pc|psc|buah|bh|btl|pck|pack|pak|bks|unit|ea|lbr|sachet|sct|porsi|cup)\b\.?',
      caseSensitive: false);
  static final List<RegExp> _splitNumbers = [
    RegExp(r'(\d)\s*([.,])\s+(\d{3})(?!\d)'),
    RegExp(r'(\d)\s+([.,])(\d{3})(?!\d)'),
    RegExp(r'(\d[.,]\d{3})\s*([.,])\s+(\d{2,3})(?![\d.,])'),
  ];
  static final RegExp _digitish = RegExp(r'^[\dOo@lI|.,\-]+$');
  static const Map<String, String> _digitFix = {
    'O': '0',
    'o': '0',
    '@': '0',
    'l': '1',
    'I': '1',
    '|': '1',
  };

  /// Rapikan baris OCR: tanda "=", satuan "pcs", angka terpecah spasi, huruf mirip angka.
  static String normalizeLine(String line) {
    final tokens = <String>[];
    for (var token in line.trim().split(RegExp(r'\s+'))) {
      if (token == '=') continue;
      final m = RegExp(r'^([(\[:;]*)(.*?)([)\]:;]*)$').firstMatch(token)!;
      final core = m.group(2)!;
      if (_digitish.hasMatch(core)) {
        final digits = RegExp(r'\d').allMatches(core).length;
        final alnum = RegExp(r'[0-9A-Za-z@|]').allMatches(core).length;
        if (digits > 0 && digits / (alnum == 0 ? 1 : alnum) >= 0.5) {
          final fixed = core.split('').map((c) => _digitFix[c] ?? c).join();
          token = '${m.group(1)}$fixed${m.group(3)}';
        }
      }
      tokens.add(token);
    }
    var out = tokens.join(' ');
    for (final p in _splitNumbers) {
      out = out.replaceAllMapped(p, (m) => '${m[1]}${m[2]}${m[3]}');
    }
    return out.replaceAllMapped(_qtyUnit, (m) => m[1]!);
  }

  static int _letters(String s) => RegExp(r'[A-Za-z]').allMatches(s).length;

  /// Baris tanpa nama barang, hanya qty/harga: "  2 x 5,200   10,400".
  static bool _isPriceOnly(String line) {
    if (line.isEmpty || _skipLine.hasMatch(line)) return false;
    final stripped =
        line.replaceAll(_rpPrefix, ' ').replaceAll(RegExp(r'[xX×@]'), '');
    if (_letters(stripped) >= 2) return false;
    return line
        .split(RegExp(r'\s+'))
        .any((t) => _numberToken.hasMatch(t) && RegExp(r'\d').hasMatch(t));
  }

  static ParsedReceipt parse(String rawText) {
    final rawLines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final lines = rawLines.map(normalizeLine).toList();

    final merchant = _findMerchant(rawLines);
    final items = <ParsedItem>[];
    var previousWasItem = false;
    var numberedHeader = false;
    var qtyFirstHeader = false;
    String? pendingName;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final next = index + 1 < lines.length ? lines[index + 1] : '';
      if (rawLines[index] == merchant) {
        previousWasItem = false;
        continue;
      }
      if (RegExp(
              r'^\s*(qty|jml|kuantitas)\.?\s+(nama|barang|item|deskripsi|produk)\b',
              caseSensitive: false)
          .hasMatch(line)) {
        // "Qty Nama Barang Harga Total": angka di depan baris adalah qty.
        qtyFirstHeader = true;
        previousWasItem = false;
        pendingName = null;
        continue;
      }
      if (_itemHeader.hasMatch(line)) {
        // Judul kolom tabel barang, mis. "No. Nama Barang Qty Harga Jumlah".
        numberedHeader = numberedHeader || _numberedHeader.hasMatch(line);
        previousWasItem = false;
        pendingName = null;
        continue;
      }
      // Nama barang di satu baris, qty & harga di baris berikutnya (format Alfamart / "Rp x = Rp").
      if (!_isNonItem(line) &&
          _parseDate(line) == null &&
          _letters(line) >= 3 &&
          RegExp(r'\d[.,]\d{3}').allMatches(line).isEmpty &&
          _isPriceOnly(next)) {
        // Kode barang (PLU/barcode) di depan nama ikut dibuang.
        pendingName = line
            .replaceAll(RegExp(r'^[\s\-:.*#|]+|[\s\-:.*#|]+$'), '')
            .replaceFirst(RegExp(r'^\d{4,}\s+'), '');
        previousWasItem = false;
        continue;
      }
      final item = _parseItemLine(line, nameFallback: pendingName);
      pendingName = null;
      if (item != null) {
        items.add(item);
        previousWasItem = true;
        continue;
      }
      // Lanjutan nama barang di baris berikutnya (mis. "Lotus Biscoff" lalu
      // "Freshmilk"): baris pendek tanpa angka tepat setelah baris barang.
      if (previousWasItem && _isNameContinuation(line)) {
        final last = items.removeLast();
        items.add(ParsedItem('${last.name} $line', last.price,
            quantity: last.quantity,
            unitPrice: last.unitPrice,
            priceCorrected: last.priceCorrected));
      }
      previousWasItem = false;
    }

    final cleanedItems =
        (qtyFirstHeader ? items : _stripRowNumbers(items, numberedHeader))
            .map(_leadingQuantity)
            .toList();
    final total = _findTotal(lines);
    return ParsedReceipt(
      merchantName: merchant == null ? null : _cleanMerchant(merchant),
      merchantAddress: _findAddress(rawLines),
      transactionDate: _findDate(lines),
      totalAmount: _reconcileTotal(lines, cleanedItems, total),
      items: _reconcileItems(lines, cleanedItems, total),
    );
  }

  // ------------------------------------------------------------ konsistensi
  static const Map<String, String> _confusable = {
    '0': '8963',
    '8': '0396',
    '9': '0874',
    '6': '0858',
    '3': '885',
    '5': '638',
    '1': '74',
    '7': '1',
    '4': '19',
    '2': '7',
  };

  /// Nominal yang berbeda 1 digit "mirip" (0<->8/9/6, 3<->8, ...).
  static Set<double> _confusionVariants(double value) {
    final s = value.round().toString();
    final out = <double>{};
    for (var i = 0; i < s.length; i++) {
      for (final alt in (_confusable[s[i]] ?? '').split('')) {
        if (i == 0 && alt == '0') continue;
        out.add(double.parse(s.substring(0, i) + alt + s.substring(i + 1)));
      }
    }
    return out;
  }

  static bool _hasCharges(List<String> lines) => lines.any((l) =>
      RegExp(r'\b(ppn|pajak|tax|service|servis|layanan|pb1|svc)\b',
              caseSensitive: false)
          .hasMatch(l) &&
      (_lastAmount(l) ?? 0) > 0);

  static double? _subtotal(List<String> lines) {
    for (final l in lines) {
      if (RegExp(r'sub\s*total', caseSensitive: false).hasMatch(l)) {
        final a = _lastAmount(l);
        if (a != null && a >= 100) return a;
      }
    }
    return null;
  }

  static double? _reconcileTotal(
      List<String> lines, List<ParsedItem> items, double? total) {
    if (items.isEmpty || _hasCharges(lines) || _subtotal(lines) != null) {
      return total;
    }
    final sum = items.fold<double>(0, (a, i) => a + i.price);
    if (total == null) {
      // Total tak terbaca: pakai nominal debit/bayar yang sama dengan jumlah barang.
      for (final l in lines) {
        if (RegExp(r'\b(debit|bayar|pembayaran|qris|tunai|cash)\b',
                    caseSensitive: false)
                .hasMatch(l) &&
            ((_lastAmount(l) ?? -1) - sum).abs() < 1) {
          return sum;
        }
      }
      return null;
    }
    // Total tercetak hanya diganti bila ada bukti kuat: nominal bayar/debit sama dengan
    // jumlah barang, atau total tercetak tidak lazim (bukan kelipatan 100).
    final supported = lines.any((l) =>
        RegExp(r'\b(debit|bayar|pembayaran|qris|tunai|cash)\b',
                caseSensitive: false)
            .hasMatch(l) &&
        ((_lastAmount(l) ?? -1) - sum).abs() < 1);
    final oddTotal = total % 100 != 0 && sum % 100 == 0;
    if ((total - sum).abs() >= 1 &&
        (supported || oddTotal) &&
        _confusionVariants(total).contains(sum)) {
      // Barang konsisten, total salah baca 1 digit (mis. 49.000 untuk 40.000).
      final itemFix = items.where(
          (i) => _confusionVariants(i.price).contains(i.price + total - sum));
      if (itemFix.isEmpty) return sum;
    }
    return total;
  }

  /// Bila tepat satu harga barang (beda 1 digit mirip) membuat jumlah = subtotal/total, koreksi.
  static List<ParsedItem> _reconcileItems(
      List<String> lines, List<ParsedItem> items, double? total) {
    if (items.isEmpty) return items;
    final sub = _subtotal(lines);
    final target = sub ?? (_hasCharges(lines) ? null : total);
    if (target == null) return items;
    final sum = items.fold<double>(0, (a, i) => a + i.price);
    if ((sum - target).abs() < 1) return items;
    final fixes = <int, double>{};
    for (var k = 0; k < items.length; k++) {
      for (final v in _confusionVariants(items[k].price)) {
        if (v >= 100 && (sum - items[k].price + v - target).abs() < 1) {
          fixes[k] = v;
        }
      }
    }
    if (fixes.length != 1) return items;
    final k = fixes.keys.first;
    final v = fixes[k]!;
    final old = items[k];
    final copy = [...items];
    copy[k] = ParsedItem(old.name, v,
        quantity: old.quantity,
        unitPrice: old.quantity > 1 && v % old.quantity == 0
            ? v / old.quantity
            : (old.quantity == 1 ? v : old.unitPrice),
        priceCorrected: true);
    return copy;
  }

  /// Format kafe/warung: qty di depan nama ("2 Croissant Butter 44.000").
  static ParsedItem _leadingQuantity(ParsedItem raw) {
    // OCR membaca "ml" sebagai "m1" ("Air Mineral 600m1").
    final item = ParsedItem(
        raw.name
            .replaceAllMapped(RegExp(r'(\d)\s?m[1I|]\b'), (m) => '${m[1]}ml'),
        raw.price,
        quantity: raw.quantity,
        unitPrice: raw.unitPrice,
        priceCorrected: raw.priceCorrected);
    // "2 Croissant", "1 x Air Mineral", "1x Roti Tawar".
    final m =
        RegExp(r"^(\d{1,2})\s*(?:[xX×]\s+|\s+)(?=[A-Za-z][A-Za-z.\-']{2,})")
            .firstMatch(item.name);
    if (m == null || item.quantity != 1) return item;
    final qty = int.parse(m.group(1)!);
    if (qty < 1 || item.price % qty != 0 || item.price / qty < 100) return item;
    // Kolom harga satuan sendiri yang tidak cocok -> angka di depan bukan qty.
    if (item.unitPrice != null &&
        (qty * item.unitPrice! - item.price).abs() >= 1) {
      return item;
    }
    return ParsedItem(item.name.substring(m.end).trim(), item.price,
        quantity: qty,
        unitPrice: item.price / qty,
        priceCorrected: item.priceCorrected);
  }

  /// Alamat toko: baris alamat berurutan (maks. 2) di 10 baris teratas.
  static String? _findAddress(List<String> lines) {
    final parts = <String>[];
    final exclude = RegExp(
        r'\b(telp|tlp|phone|hp|wa|npwp|transaksi|struk|kasir)\b',
        caseSensitive: false);
    for (final line in lines.take(10)) {
      if (_addressLine.hasMatch(line) && !exclude.hasMatch(line)) {
        parts.add(line.replaceAll(RegExp(r'\bJ[1iI]\.'), 'Jl.').trim());
        if (parts.length == 2) break;
      } else if (parts.isNotEmpty) {
        break;
      }
    }
    if (parts.isEmpty) return null;
    final joined = parts.join(', ');
    return joined.length > 300 ? joined.substring(0, 300) : joined;
  }

  static bool _isNameContinuation(String line) {
    if (RegExp(r'\d').hasMatch(line)) return false;
    if (!RegExp(r'[A-Za-z]{3,}').hasMatch(line)) return false;
    if (_isNonItem(line)) return false;
    if (line.contains(':')) return false;
    return line.split(RegExp(r'\s+')).length <= 3;
  }

  /// Merchant = nama toko di bagian atas struk: baris berhuruf tanpa angka
  /// yang bukan alamat/info pembayaran. Jika tidak ada, pakai aturan lama.
  /// Buang simbol sisa OCR di depan/belakang nama toko ("] Toko Sejahtera").
  static String _cleanMerchant(String line) {
    final hadJunk = RegExp(r'^\s*[^0-9A-Za-z\s]').hasMatch(line);
    var cleaned = line
        .replaceFirst(RegExp(r'^[^0-9A-Za-z]+'), '')
        .replaceFirst(RegExp(r'[^0-9A-Za-z)]+$'), '');
    if (hadJunk) {
      // Logo terbaca jadi 1-2 huruf yatim ("EJ Toko ..."); "UD Sinar Jaya" tidak disentuh.
      cleaned = cleaned.replaceFirst(
          RegExp(r'^(?:[A-Z]{1,2}|[a-z])\s+(?=[A-Z][a-z])'), '');
    }
    final result = cleaned.trim();
    return result.isEmpty ? line.trim() : result;
  }

  static String? _findMerchant(List<String> lines) {
    final top = lines.take(8);
    for (final line in top) {
      if (!RegExp(r'[A-Za-z]{3,}').hasMatch(line)) continue;
      if (RegExp(r'\d').hasMatch(line)) continue;
      if (_isNonItem(line)) continue;
      return line;
    }
    for (final line in lines) {
      if (!RegExp(r'[A-Za-z]{3,}').hasMatch(line)) continue;
      if (_isNonItem(line)) continue;
      if (_parseDate(line) != null) continue;
      if (_parseItemLine(line) != null) continue;
      return line;
    }
    return null;
  }

  static DateTime? _findDate(List<String> lines) {
    for (final line in lines) {
      if (line.toLowerCase().contains('total')) continue;
      final d = _parseDate(line);
      if (d != null) return d;
    }
    return null;
  }

  static DateTime? _parseDate(String line) {
    final iso = _isoDate.firstMatch(line);
    if (iso != null) {
      return _validDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
          int.parse(iso.group(3)!));
    }
    final text = _textDate.firstMatch(line);
    if (text != null) {
      final month =
          _monthByPrefix[text.group(2)!.toLowerCase().substring(0, 3)];
      if (month != null) {
        return _validDate(
            int.parse(text.group(3)!), month, int.parse(text.group(1)!));
      }
    }
    final numeric = _numericDate.firstMatch(line);
    if (numeric != null) {
      var year = int.parse(numeric.group(3)!);
      if (year < 100) year += 2000;
      return _validDate(
          year, int.parse(numeric.group(2)!), int.parse(numeric.group(1)!));
    }
    return null;
  }

  /// Menolak tanggal tidak valid (misal 31/02/2026).
  static DateTime? _validDate(int year, int month, int day) {
    if (year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final d = DateTime(year, month, day);
    return (d.year == year && d.month == month && d.day == day) ? d : null;
  }

  static double? _findTotal(List<String> lines) {
    for (final line in lines) {
      final low = line.toLowerCase();
      if (!low.contains('total')) continue;
      if (low.contains('subtotal') ||
          low.contains('sub total') ||
          low.contains('item') ||
          low.contains('qty')) {
        continue;
      }
      final amount = _lastAmount(line);
      if (amount != null && amount >= 100) return amount;
    }
    return null;
  }

  static double? _lastAmount(String line) {
    final tokens = line.replaceAll(_rpPrefix, '').trim().split(RegExp(r'\s+'));
    for (var i = tokens.length - 1; i >= 0; i--) {
      if (_numberToken.hasMatch(tokens[i])) return Fmt.parseAmount(tokens[i]);
    }
    return null;
  }

  static final RegExp _qtySign = RegExp(r'^[xX×@*]{1,2}$');

  /// Baris barang: `<nama> [qty] [harga satuan] <harga>`. Angka terakhir = harga.
  static ParsedItem? _parseItemLine(String line, {String? nameFallback}) {
    if (_isNonItem(line)) return null;
    if (_parseDate(line) != null) return null;
    final tokens = line
        .replaceAll(_rpPrefix, ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && t.toLowerCase() != 'rp')
        .toList();
    var end = tokens.length;
    final numbers = <String>[];
    int? qtyHint;
    while (end > 0 &&
        (_numberToken.hasMatch(tokens[end - 1]) ||
            _qtySign.hasMatch(tokens[end - 1]))) {
      end--;
      if (_qtySign.hasMatch(tokens[end])) {
        // "2 x 5,200": angka kecil sebelum tanda x adalah qty.
        if (end > 0 && RegExp(r'^\d{1,3}$').hasMatch(tokens[end - 1])) {
          end--;
          qtyHint = int.parse(tokens[end]);
        }
        continue;
      }
      numbers.insert(0, tokens[end]);
    }
    if (numbers.isEmpty) return null;
    if (end == 0) {
      // Baris qty/harga tanpa nama: pakai nama dari baris sebelumnya.
      if (nameFallback == null) return null;
      final price = Fmt.parseAmount(numbers.last);
      if (price == null || price < 100) return null;
      final qty = qtyHint ?? 1;
      double? unit = numbers.length >= 2
          ? Fmt.parseAmount(numbers[numbers.length - 2])
          : price / qty;
      var total = price;
      if (unit != null && qty > 1 && (unit - total).abs() < 1) {
        return ParsedItem(nameFallback, total, quantity: 1, unitPrice: unit);
      }
      if (unit != null &&
          (qty * unit - total).abs() >= 1 &&
          (qty * unit) % 100 == 0 &&
          total % 100 != 0 &&
          _confusionVariants(total).contains(qty * unit)) {
        // Harga total salah baca 1 digit.
        return ParsedItem(nameFallback, qty * unit,
            quantity: qty, unitPrice: unit, priceCorrected: true);
      }
      return ParsedItem(nameFallback, total, quantity: qty, unitPrice: unit);
    }

    // Buang penanda jumlah di akhir nama, mis. "Lotus Biscoff x1".
    var nameTokens = tokens.sublist(0, end);
    // Kolom Qty "1" yang salah baca OCR ("l", "il", "al") sebelum kolom harga.
    if (nameTokens.length > 1 &&
        numbers.length == 2 &&
        _misreadOne.contains(nameTokens.last.toLowerCase())) {
      nameTokens = nameTokens.sublist(0, nameTokens.length - 1);
      numbers.insert(0, '1');
    }
    while (nameTokens.length > 1 && _qtyToken.hasMatch(nameTokens.last)) {
      nameTokens = nameTokens.sublist(0, nameTokens.length - 1);
    }
    final name = nameTokens.join(' ').replaceAll(RegExp(r'[,:;]+$'), '').trim();
    if (!RegExp(r'[A-Za-z]{2,}').hasMatch(name)) return null;

    final price = Fmt.parseAmount(numbers.last);
    if (price == null || price < 100) return null;

    // "<qty> <harga satuan> <jumlah>": qty x satuan = jumlah.
    if (numbers.length >= 3) {
      final q = Fmt.parseAmount(numbers[numbers.length - 3]);
      final unit = Fmt.parseAmount(numbers[numbers.length - 2]);
      if (q != null &&
          unit != null &&
          q >= 1 &&
          q < 1000 &&
          q == q.roundToDouble() &&
          (q * unit - price).abs() < 1) {
        return ParsedItem(name, price, quantity: q.toInt(), unitPrice: unit);
      }
      if (q != null &&
          unit != null &&
          q >= 1 &&
          q < 1000 &&
          q == q.roundToDouble()) {
        if ((unit - price).abs() < 1) {
          // "4, 62.000 62.000": harga satuan = total -> qty 1 yang salah baca.
          return ParsedItem(name, price, quantity: 1, unitPrice: unit);
        }
        // Hanya bila jelas mana yang salah (harga rupiah lazim berakhiran "00").
        if ((q * unit) % 100 == 0 &&
            price % 100 != 0 &&
            _confusionVariants(price).contains(q * unit)) {
          // Harga total salah baca 1 digit (mis. 19.400 untuk 2 x 5.200).
          return ParsedItem(name, q * unit,
              quantity: q.toInt(), unitPrice: unit, priceCorrected: true);
        }
      }
    }
    if (qtyHint != null && qtyHint > 1) {
      final unit = numbers.length >= 2
          ? Fmt.parseAmount(numbers[numbers.length - 2])
          : price / qtyHint;
      return ParsedItem(name, price, quantity: qtyHint, unitPrice: unit);
    }
    return ParsedItem(name, price);
  }

  // ---------------------------------------------------------------- nomor urut
  static const Set<String> _misreadOne = {
    'l',
    'i',
    'il',
    'li',
    'll',
    'al',
    '|',
    '!'
  };
  static final RegExp _rowNumber = RegExp(
      r'^(\d{1,3}|al|il|l|i|\|)[.):]?\s+(?=\S*[A-Za-z]{2})',
      caseSensitive: false);
  static final RegExp _itemHeader = RegExp(
      r'^\s*(no\.?\s+)?(nama\s+barang|nama\s+item|item|barang|deskripsi)\b.*\b(qty|harga|jumlah|price|total)\b',
      caseSensitive: false);
  static final RegExp _numberedHeader =
      RegExp(r'^\s*no\.?\s', caseSensitive: false);

  static int? _rowNumberOf(String name) {
    final m = _rowNumber.firstMatch(name);
    if (m == null) return null;
    final token = m.group(1)!.toLowerCase();
    return _misreadOne.contains(token) ? 1 : int.tryParse(token);
  }

  /// Buang nomor urut baris ("2 USB...", "Al Headphone" = 1) bila struk jelas
  /// bernomor: ada kolom "No." di judul tabel atau nomornya berurutan 1, 2, 3.
  static List<ParsedItem> _stripRowNumbers(
      List<ParsedItem> items, bool numberedHeader) {
    final numbers = items.map((i) => _rowNumberOf(i.name)).toList();
    final present = numbers.whereType<int>().toList();
    var sequential = present.length >= 2 &&
        present.length >= items.length / 2 &&
        (present.first == 1 || (present.first == 2 && present.length >= 3));
    var jumps = 0;
    for (var k = 1; sequential && k < present.length; k++) {
      final step = present[k] - present[k - 1];
      if (step < 1 || step > 2) sequential = false;
      if (step == 2) jumps++;
    }
    if (jumps > 1) sequential = false;
    if (!numberedHeader && !sequential) return items;
    return [
      for (var k = 0; k < items.length; k++)
        if (numbers[k] != null &&
            RegExp(r'[A-Za-z]{2,}')
                .hasMatch(items[k].name.replaceFirst(_rowNumber, '')))
          ParsedItem(
              items[k].name.replaceFirst(_rowNumber, '').trim(), items[k].price,
              quantity: items[k].quantity,
              unitPrice: items[k].unitPrice,
              priceCorrected: items[k].priceCorrected)
        else
          items[k],
    ];
  }
}
