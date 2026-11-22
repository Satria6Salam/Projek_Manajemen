import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strukku/core/utils/name_repairer.dart';
import 'package:strukku/core/utils/receipt_parser.dart';

void main() {
  final repairer = NameRepairer.fromText(
      File('assets/data/vocabulary.txt').readAsStringSync());

  test('memperbaiki salah eja nama barang secara offline', () {
    expect(repairer.repair('PEPSODNT 190G'), 'PEPSODENT 190G');
    expect(repairer.repair('TE1UR AYAM'), 'TELUR AYAM');
    expect(repairer.repair('Kabeliistrik Keci1 Warna-warm'),
        'Kabel Listrik Kecil Warna-warni');
    expect(repairer.repair('Timah Soluer Paragon 10 Metei'),
        'Timah Solder Paragon 10 Meter');
    // Kata dikenal & ukuran tidak diubah.
    expect(repairer.repair('AQUA 600ML'), 'AQUA 600ML');
  });

  test('kata ragu ditandai, kata hasil pecahan kata gabungan tidak', () {
    final fixed = repairer.repair('TimahSolder Paragon Gifuct');
    expect(repairer.uncertainWords(fixed, 'TimahSolder Paragon Gifuct'),
        ['Paragon', 'Gifuct']);
  });

  test('parser offline memakai perbaikan ejaan bila kosakata dimuat', () {
    NameRepairer.instance = repairer;
    addTearDown(() => NameRepairer.instance = null);
    final r =
        ReceiptParser.parse('TOKO ABC\nPEPSODNT 190G 12.000\nTOTAL 12.000');
    expect(r.items.single.name, 'PEPSODENT 190G');
    expect(r.items.single.nameCorrected, isTrue);
    expect(r.items.single.uncertainWords, ['PEPSODENT']);
  });
}
