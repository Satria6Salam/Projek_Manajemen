import 'dart:math' as math;

/// Perbaikan ejaan nama barang hasil OCR secara OFFLINE (tanpa server).
///
/// Versi ringkas dari `OcrTextRepairer.repair_display` di backend, memakai kosakata
/// `assets/data/vocabulary.txt` (diekspor dari backend). Hanya kata yang TIDAK
/// dikenal yang diubah, huruf besar/kecil dan ukuran ("600ML") dibiarkan:
/// 1. angka terselip di kata ("Keci1" -> "Kecil", "TE1UR" -> "TELUR");
/// 2. kata ulang berstrip ("Warna-warm" -> "Warna-warni");
/// 3. kata gabungan dipecah ("Kabelistrik" -> "Kabel Listrik"), termasuk satu huruf salah;
/// 4. kata terdekat (jarak edit 1, atau 2 untuk kata >= 8 huruf).
class NameRepairer {
  NameRepairer(Map<String, int> vocabulary, {Set<String> hyphenated = const {}})
      : _vocab = vocabulary,
        _hyphenated = hyphenated {
    for (final word in _vocab.keys) {
      if (word.length < minFuzzyLen) continue;
      for (final v in {word, ..._deletes1(word)}) {
        (_deletes[v] ??= <String>[]).add(word);
      }
    }
  }

  /// Dimuat sekali saat aplikasi mulai (lihat main.dart); null = belum/gagal dimuat.
  static NameRepairer? instance;

  static const int minFuzzyLen = 5;

  final Map<String, int> _vocab;
  final Set<String> _hyphenated;
  final Map<String, List<String>> _deletes = {};
  final Map<String, String?> _cache = {};

  static const Map<String, String> _confusable = {
    '0': 'o',
    '1': 'l',
    '2': 'z',
    '3': 'e',
    '4': 'a',
    '5': 's',
    '6': 'g',
    '7': 't',
    '8': 'b',
    '9': 'g',
  };
  static final RegExp _size = RegExp(
      r'^(\d+([.,]\d+)?(ml|l|lt|ltr|g|gr|kg|mg|s|pcs|pc|x|cm|mm|m|w|v|mah)?|x\d+|\d+x\d*)$');

  /// Muat dari isi file kosakata: `kata<TAB>frekuensi` per baris, `#` = komentar.
  factory NameRepairer.fromText(String text) {
    final vocab = <String, int>{};
    final hyphen = <String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('\t');
      final word = parts.first.toLowerCase();
      final count = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
      if (word.contains('-')) {
        hyphen.add(word);
      } else {
        vocab[word] = count;
      }
    }
    return NameRepairer(vocab, hyphenated: hyphen);
  }

  bool known(String word) => _vocab.containsKey(word);

  static Set<String> _deletes1(String w) => {
        for (var i = 0; i < w.length; i++)
          w.substring(0, i) + w.substring(i + 1)
      };

  static int _levenshtein(String a, String b, int limit) {
    if ((a.length - b.length).abs() > limit) return limit + 1;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = <int>[i];
      var best = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final v =
            math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
        cur.add(v);
        best = math.min(best, v);
      }
      if (best > limit) return limit + 1;
      prev = cur;
    }
    return prev.last;
  }

  /// Kata dikenal terdekat beserta jaraknya, atau null.
  (String, int)? _nearestWithDistance(String token) {
    if (token.length < minFuzzyLen) return null;
    final limit = token.length < 8 ? 1 : 2;
    final candidates = <String>{};
    for (final v in {token, ..._deletes1(token)}) {
      candidates.addAll(_deletes[v] ?? const []);
    }
    (String, int)? best;
    for (final w in candidates) {
      final d = _levenshtein(token, w, limit);
      if (d > limit) continue;
      if (best == null ||
          d < best.$2 ||
          (d == best.$2 && (_vocab[w] ?? 0) > (_vocab[best.$1] ?? 0))) {
        best = (w, d);
      }
    }
    return best;
  }

  String? nearest(String token) =>
      _cache.putIfAbsent(token, () => _nearestWithDistance(token)?.$1);

  /// Pecah kata gabungan menjadi kata-kata dikenal (paling sedikit potongan).
  List<String>? segment(String token) {
    if (token.length < 8) return null;
    final n = token.length;
    final best = List<List<String>?>.filled(n + 1, null);
    best[0] = const [];
    for (var end = 3; end <= n; end++) {
      for (var start = 0; start <= end - 3; start++) {
        final prefix = best[start];
        if (prefix == null) continue;
        final piece = token.substring(start, end);
        if (!known(piece)) continue;
        final cand = [...prefix, piece];
        if (best[end] == null || cand.length < best[end]!.length) {
          best[end] = cand;
        }
      }
    }
    final parts = best[n];
    return parts != null && parts.length >= 2 ? parts : null;
  }

  /// Awalan kata dikenal + sisa yang berjarak 1 dari kata dikenal ("kabeliistrik").
  List<String>? segmentFuzzy(String token) {
    if (token.length < 9) return null;
    List<String>? best;
    var bestLen = 0;
    for (var cut = 3; cut < token.length - 4; cut++) {
      final left = token.substring(0, cut);
      final right = token.substring(cut);
      if (!known(left) || right.length < minFuzzyLen) continue;
      final near = _nearestWithDistance(right);
      if (near != null && near.$2 == 1 && cut > bestLen) {
        best = [left, near.$1];
        bestLen = cut;
      }
    }
    return best;
  }

  String? _fixDigits(String low) {
    if (_size.hasMatch(low) || !RegExp(r'[a-z]').hasMatch(low)) return null;
    final primary = low.split('').map((c) => _confusable[c] ?? c).join();
    if (known(primary)) return primary;
    if (low.contains('1')) {
      final alt = low
          .split('')
          .map((c) => c == '1' ? 'i' : (_confusable[c] ?? c))
          .join();
      if (known(alt)) return alt;
    }
    return null;
  }

  static String _recase(String tok, String fix) {
    final letters = tok.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.length > 1 && letters == letters.toUpperCase()) {
      return fix.toUpperCase();
    }
    if (tok.isNotEmpty &&
        tok[0] == tok[0].toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(tok[0])) {
      return fix
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');
    }
    return fix;
  }

  /// Nama barang yang sudah diperbaiki untuk ditampilkan.
  String repair(String name) {
    final out = <String>[];
    for (final tok in name.split(' ')) {
      final low = tok.toLowerCase();
      if (tok.isEmpty) {
        out.add(tok);
        continue;
      }
      if (low.contains('-') &&
          _hyphenated.isNotEmpty &&
          !_hyphenated.contains(low)) {
        final limit = low.length < 10 ? 1 : 2;
        final close = [
          for (final h in _hyphenated)
            if (_levenshtein(low, h, limit) <= limit) h
        ];
        if (close.length == 1) {
          out.add(_recase(tok, close.first));
          continue;
        }
      }
      final isAlpha = RegExp(r'^[a-z]+$').hasMatch(low);
      if (!isAlpha) {
        final fixed = RegExp(r'\d').hasMatch(low) ? _fixDigits(low) : null;
        out.add(fixed == null ? tok : _recase(tok, fixed));
        continue;
      }
      if (low.length < 2 || known(low)) {
        out.add(tok);
        continue;
      }
      String? fix;
      if (low.length >= 8) {
        final parts = segment(low) ?? segmentFuzzy(low);
        if (parts != null) fix = parts.join(' ');
      }
      fix ??= nearest(low);
      out.add(fix == null ? tok : _recase(tok, fix));
    }
    return out.join(' ');
  }

  /// Kata yang perlu dicek pengguna: hasil koreksi (tidak ada di teks asli), atau kata
  /// yang tetap tidak dikenal / huruf bercampur angka.
  List<String> uncertainWords(String fixed, String original) {
    final joined = original.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final out = <String>[];
    for (final word in fixed.split(RegExp(r'\s+'))) {
      final low =
          word.toLowerCase().replaceAll(RegExp(r'^[.,:;()]+|[.,:;()]+$'), '');
      if (low.isEmpty) continue;
      final changed = !joined.contains(low);
      bool unknown;
      if (RegExp(r'^[a-z]+$').hasMatch(low)) {
        unknown = low.length >= 3 && !known(low);
      } else if (low.contains('-')) {
        unknown = !_hyphenated.contains(low);
      } else {
        final letters = low.replaceAll(RegExp(r'[^a-z]'), '').length;
        unknown =
            letters >= 2 && !RegExp(r'^[\d.,/x@%-]+[a-z]{0,4}$').hasMatch(low);
      }
      if ((changed || unknown) && !out.contains(word)) out.add(word);
    }
    return out;
  }
}
