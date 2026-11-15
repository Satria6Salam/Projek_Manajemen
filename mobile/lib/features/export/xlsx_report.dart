import 'package:excel/excel.dart';

import '../../core/utils/formatters.dart';
import '../../models/receipt_model.dart';

/// Laporan pengeluaran bulanan dalam format Excel (.xlsx) yang rapi:
/// sheet "Laporan" (satu baris per barang) dan "Ringkasan" (per kategori & toko).
class XlsxReport {
  const XlsxReport();

  static final ExcelColor _blue = ExcelColor.fromHexString('#FF2160DD');
  static final ExcelColor _navy = ExcelColor.fromHexString('#FF0F1F3D');
  static final ExcelColor _grey = ExcelColor.fromHexString('#FF6B7A90');
  static final ExcelColor _stripe = ExcelColor.fromHexString('#FFF4F8FF');
  static final ExcelColor _totalFill = ExcelColor.fromHexString('#FFEAF1FE');
  static final ExcelColor _line = ExcelColor.fromHexString('#FFD3E2FB');

  static const NumFormat _rupiah = CustomNumericNumFormat(formatCode: '"Rp"#,##0');
  static const NumFormat _percent = CustomNumericNumFormat(formatCode: '0.0%');

  Border get _thin => Border(borderStyle: BorderStyle.Thin, borderColorHex: _line);

  CellStyle _header() => CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: _blue,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: _thin,
        rightBorder: _thin,
        topBorder: _thin,
        bottomBorder: _thin,
      );

  CellStyle _body({bool stripe = false, NumFormat? format, bool center = false, bool bold = false}) =>
      CellStyle(
        backgroundColorHex: stripe ? _stripe : ExcelColor.none,
        numberFormat: format ?? NumFormat.standard_0,
        horizontalAlign: center ? HorizontalAlign.Center : HorizontalAlign.Left,
        verticalAlign: VerticalAlign.Center,
        bold: bold,
        fontColorHex: _navy,
        leftBorder: _thin,
        rightBorder: _thin,
        topBorder: _thin,
        bottomBorder: _thin,
      );

  void _put(Sheet s, int col, int row, CellValue value, CellStyle style) {
    s.updateCell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row), value,
        cellStyle: style);
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Bangun file .xlsx; mengembalikan bytes siap disimpan.
  List<int> build(List<ReceiptModel> receipts, DateTime month) {
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultName, 'Laporan');
    final sheet = excel['Laporan'];
    final total = receipts.fold<double>(0, (s, r) => s + r.totalAmount);

    // Judul.
    _put(sheet, 0, 0, TextCellValue('Laporan Pengeluaran STRUKKU - ${Fmt.monthYear(month)}'),
        CellStyle(bold: true, fontSize: 15, fontColorHex: _navy));
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('I1'));
    _put(
        sheet,
        0,
        1,
        TextCellValue('${receipts.length} struk  |  Total ${Fmt.rupiah(total.round())}  |  '
            'Dibuat ${Fmt.longDate(DateTime.now())}'),
        CellStyle(italic: true, fontColorHex: _grey));
    sheet.merge(CellIndex.indexByString('A2'), CellIndex.indexByString('I2'));

    // Tabel barang.
    const headers = ['No', 'Tanggal', 'Jam', 'Toko', 'Barang', 'Kategori', 'Jumlah', 'Harga', 'Dikoreksi'];
    const headerRow = 3;
    for (var c = 0; c < headers.length; c++) {
      _put(sheet, c, headerRow, TextCellValue(headers[c]), _header());
    }
    sheet.setRowHeight(headerRow, 22);

    var row = headerRow + 1;
    var no = 0;
    double itemsTotal = 0;
    final byCategory = <String, double>{};
    final byStore = <String, (int, double)>{};
    for (var r = 0; r < receipts.length; r++) {
      final rc = receipts[r];
      final stripe = r.isOdd; // warna selang-seling per struk
      final store = byStore[rc.merchantName] ?? (0, 0.0);
      byStore[rc.merchantName] = (store.$1 + 1, store.$2 + rc.totalAmount);
      final items = rc.items.isEmpty ? [null] : rc.items;
      for (final item in items) {
        no++;
        final d = rc.transactionDate;
        _put(sheet, 0, row, IntCellValue(no), _body(stripe: stripe, center: true));
        _put(sheet, 1, row, DateCellValue(year: d.year, month: d.month, day: d.day),
            _body(stripe: stripe, center: true, format: const CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy')));
        _put(sheet, 2, row, TextCellValue(_time(d)), _body(stripe: stripe, center: true));
        _put(sheet, 3, row, TextCellValue(rc.merchantName), _body(stripe: stripe));
        _put(sheet, 4, row, TextCellValue(item?.itemName ?? '(tanpa rincian barang)'), _body(stripe: stripe));
        _put(sheet, 5, row, TextCellValue(item?.categoryName ?? '-'), _body(stripe: stripe));
        _put(sheet, 6, row, IntCellValue(item?.quantity ?? 1), _body(stripe: stripe, center: true));
        final price = item?.itemPrice ?? rc.totalAmount;
        _put(sheet, 7, row, DoubleCellValue(price), _body(stripe: stripe, format: _rupiah));
        _put(sheet, 8, row, TextCellValue(item?.isUserCorrected == true ? 'Ya' : ''),
            _body(stripe: stripe, center: true));
        itemsTotal += price;
        if (item != null) {
          byCategory[item.categoryName] = (byCategory[item.categoryName] ?? 0) + item.itemPrice;
        }
        row++;
      }
    }
    // Baris total.
    final totalStyle = CellStyle(
      bold: true,
      backgroundColorHex: _totalFill,
      fontColorHex: _navy,
      numberFormat: _rupiah,
      topBorder: Border(borderStyle: BorderStyle.Medium, borderColorHex: _blue),
    );
    for (var c = 0; c < headers.length; c++) {
      _put(sheet, c, row, TextCellValue(''), totalStyle);
    }
    _put(sheet, 4, row, TextCellValue('TOTAL BARANG'), totalStyle);
    _put(sheet, 7, row, DoubleCellValue(itemsTotal), totalStyle);
    if ((itemsTotal - total).abs() > 0.5) {
      row++;
      _put(
          sheet,
          4,
          row,
          TextCellValue('Total struk ${Fmt.rupiah(total.round())} (selisih = pajak/diskon/biaya lain)'),
          CellStyle(italic: true, fontColorHex: _grey));
    }

    const widths = [6.0, 12.0, 8.0, 26.0, 34.0, 24.0, 9.0, 15.0, 11.0];
    for (var c = 0; c < widths.length; c++) {
      sheet.setColumnWidth(c, widths[c]);
    }

    // Sheet ringkasan.
    final sum = excel['Ringkasan'];
    _put(sum, 0, 0, TextCellValue('Ringkasan ${Fmt.monthYear(month)}'),
        CellStyle(bold: true, fontSize: 14, fontColorHex: _navy));
    _put(sum, 0, 2, TextCellValue('Kategori'), _header());
    _put(sum, 1, 2, TextCellValue('Total'), _header());
    _put(sum, 2, 2, TextCellValue('Persen'), _header());
    final cats = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final catSum = cats.fold<double>(0, (s, e) => s + e.value);
    var sr = 3;
    for (var i = 0; i < cats.length; i++, sr++) {
      _put(sum, 0, sr, TextCellValue(cats[i].key), _body(stripe: i.isOdd));
      _put(sum, 1, sr, DoubleCellValue(cats[i].value), _body(stripe: i.isOdd, format: _rupiah));
      _put(sum, 2, sr, DoubleCellValue(catSum > 0 ? cats[i].value / catSum : 0),
          _body(stripe: i.isOdd, format: _percent, center: true));
    }
    _put(sum, 0, sr, TextCellValue('Total'), totalStyle);
    _put(sum, 1, sr, DoubleCellValue(catSum), totalStyle);
    _put(sum, 2, sr, DoubleCellValue(catSum > 0 ? 1 : 0),
        totalStyle.copyWith(numberFormat: _percent));

    sr += 3;
    _put(sum, 0, sr, TextCellValue('Toko'), _header());
    _put(sum, 1, sr, TextCellValue('Total'), _header());
    _put(sum, 2, sr, TextCellValue('Jumlah struk'), _header());
    final stores = byStore.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    for (var i = 0; i < stores.length; i++) {
      sr++;
      _put(sum, 0, sr, TextCellValue(stores[i].key), _body(stripe: i.isOdd));
      _put(sum, 1, sr, DoubleCellValue(stores[i].value.$2), _body(stripe: i.isOdd, format: _rupiah));
      _put(sum, 2, sr, IntCellValue(stores[i].value.$1), _body(stripe: i.isOdd, center: true));
    }
    sum.setColumnWidth(0, 30);
    sum.setColumnWidth(1, 18);
    sum.setColumnWidth(2, 14);

    excel.setDefaultSheet('Laporan');
    return excel.encode()!;
  }
}
