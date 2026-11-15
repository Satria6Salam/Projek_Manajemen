import 'formatters.dart';

/// Satu baris barang hasil parsing teks OCR.
class ParsedItem {
  const ParsedItem(this.name, this.price, {this.quantity = 1, this.unitPrice});

  final String name;

  /// Harga total baris (qty x harga satuan).
  final double price;
  final int quantity;
  final double? unitPrice;
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
    r'order|bill|invoice|collected|table|meja|notes?|admin|saldo|poin|point|voucher)\b'
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

  static ParsedReceipt parse(String rawText) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final merchant = _findMerchant(lines);
    final items = <ParsedItem>[];
    var previousWasItem = false;
    var numberedHeader = false;
    for (final line in lines) {
      if (line == merchant) {
        previousWasItem = false;
        continue;
      }
      if (_itemHeader.hasMatch(line)) {
        // Judul kolom tabel barang, mis. "No. Nama Barang Qty Harga Jumlah".
        numberedHeader = numberedHeader || _numberedHeader.hasMatch(line);
        previousWasItem = false;
        continue;
      }
      final item = _parseItemLine(line);
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
            quantity: last.quantity, unitPrice: last.unitPrice));
      }
      previousWasItem = false;
    }

    return ParsedReceipt(
      merchantName: merchant == null ? null : _cleanMerchant(merchant),
      merchantAddress: _findAddress(lines),
      transactionDate: _findDate(lines),
      totalAmount: _findTotal(lines),
      items: _stripRowNumbers(items, numberedHeader),
    );
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
      cleaned = cleaned.replaceFirst(RegExp(r'^(?:[A-Z]{1,2}|[a-z])\s+(?=[A-Z][a-z])'), '');
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

  /// Baris barang: "<nama> [qty] [harga satuan] <harga>". Angka terakhir = harga.
  static ParsedItem? _parseItemLine(String line) {
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
    while (end > 0 && _numberToken.hasMatch(tokens[end - 1])) {
      end--;
      numbers.insert(0, tokens[end]);
    }
    if (numbers.isEmpty || end == 0) return null;

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
              quantity: items[k].quantity, unitPrice: items[k].unitPrice)
        else
          items[k],
    ];
  }
}
