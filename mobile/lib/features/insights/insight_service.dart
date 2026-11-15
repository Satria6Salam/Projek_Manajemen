import 'dart:math' as math;

import '../../core/utils/formatters.dart';
import '../../models/dashboard_model.dart';
import '../../models/receipt_model.dart';
import 'analysis_period.dart';

enum InsightKind { warning, positive, info, tip }

/// Satu temuan / rekomendasi dari analisis pengeluaran.
class Insight {
  const Insight({
    required this.kind,
    required this.title,
    required this.message,
  });

  final InsightKind kind;
  final String title;
  final String message;
}

/// Tipe pengeluaran pengguna berdasarkan kategori dominan.
class SpendingPersona {
  const SpendingPersona({
    required this.title,
    required this.description,
    this.categoryName,
    this.sharePercent = 0,
  });

  final String title;
  final String description;
  final String? categoryName;
  final double sharePercent;
}

/// Rekomendasi untuk satu kategori (halaman Kategori).
class CategoryAdvice {
  const CategoryAdvice({
    required this.categoryName,
    required this.total,
    required this.sharePercent,
    required this.tip,
  });

  final String categoryName;
  final double total;
  final double sharePercent;
  final String tip;
}

class MerchantStat {
  const MerchantStat(
      {required this.name, required this.visits, required this.total});

  final String name;
  final int visits;
  final double total;
}

/// Hasil analisis satu bulan.
class SpendingAnalytics {
  const SpendingAnalytics({
    this.total = 0,
    this.transactionCount = 0,
    this.previousToDate = 0,
    this.previousTotal = 0,
    this.changePercent,
    this.averagePerDay = 0,
    this.projectedTotal = 0,
    this.daysElapsed = 0,
    this.totalDays = 30,
    this.isCurrentMonth = true,
    this.topMerchants = const <MerchantStat>[],
    this.persona,
    this.insights = const <Insight>[],
    this.categoryAdvice = const <CategoryAdvice>[],
    this.dailyTotals = const <double>[],
  });

  final double total;
  final int transactionCount;

  /// Total bulan lalu pada rentang tanggal yang sama (adil dibandingkan).
  final double previousToDate;
  final double previousTotal;

  /// Perubahan (%) dibanding bulan lalu; null bila tidak ada pembanding.
  final double? changePercent;
  final double averagePerDay;
  final double projectedTotal;
  final int daysElapsed;
  final int totalDays;
  final bool isCurrentMonth;
  final List<MerchantStat> topMerchants;
  final SpendingPersona? persona;
  final List<Insight> insights;
  final List<CategoryAdvice> categoryAdvice;

  /// Total per tanggal (hanya periode bulan; indeks 0 = tanggal 1).
  final List<double> dailyTotals;

  bool get hasData => transactionCount > 0;
}

/// Hasil analisis tren bulanan (dalam satu tahun) dan tahunan.
class TrendAnalytics {
  const TrendAnalytics({
    this.year = 0,
    this.monthlyTotals = const <double>[],
    this.yearlyTotals = const <int, double>{},
    this.monthlyAverage = 0,
    this.peakMonth,
    this.activeMonths = 0,
    this.yearOverYearPercent,
    this.insights = const <Insight>[],
  });

  final int year;

  /// 12 nilai, indeks 0 = Januari.
  final List<double> monthlyTotals;

  /// Tahun -> total, terurut naik.
  final Map<int, double> yearlyTotals;

  /// Rata-rata pada bulan yang punya pengeluaran.
  final double monthlyAverage;

  /// 1-12; null bila belum ada data.
  final int? peakMonth;
  final int activeMonths;

  /// Perubahan (%) dibanding tahun lalu pada rentang bulan yang sama.
  final double? yearOverYearPercent;
  final List<Insight> insights;

  bool get hasData =>
      monthlyTotals.any((v) => v > 0) || yearlyTotals.isNotEmpty;
}

/// Menganalisis kebiasaan pengeluaran dan memberi rekomendasi per kategori
/// (diadaptasi dari InsightService smart_receipt_v2, murni Dart, offline).
class InsightService {
  const InsightService();

  static const double _smallSpendLimit = 25000;
  static const int _minTransactions = 3;

  static const List<String> _weekdayNames = <String>[
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  /// Analisis satu bulan (pembungkus [analyzePeriod]).
  SpendingAnalytics analyzeMonth({
    required DateTime month,
    required DateTime now,
    required List<ReceiptModel> receipts,
    required List<ReceiptModel> previousReceipts,
    required List<CategoryTotal> categories,
  }) =>
      analyzePeriod(
        period: AnalysisPeriod.month(month.year, month.month),
        now: now,
        receipts: receipts,
        previousReceipts: previousReceipts,
        categories: categories,
      );

  /// Analisis satu periode: hari, bulan, atau tahun.
  SpendingAnalytics analyzePeriod({
    required AnalysisPeriod period,
    required DateTime now,
    required List<ReceiptModel> receipts,
    required List<ReceiptModel> previousReceipts,
    required List<CategoryTotal> categories,
  }) {
    final DateTime start = period.start;
    final int totalDays = period.totalDays;
    final bool isCurrent = period.isCurrent(now);
    final bool isDay = period.mode == PeriodMode.day;
    final DateTime today = DateTime.utc(now.year, now.month, now.day);
    final int daysElapsed = isCurrent
        ? math.min(
            today
                    .difference(
                        DateTime.utc(start.year, start.month, start.day))
                    .inDays +
                1,
            totalDays)
        : totalDays;
    final int count = receipts.length;
    final double total = receipts.fold<double>(0, (s, r) => s + r.totalAmount);

    // Periode sebelumnya pada rentang yang sama (adil dibandingkan).
    final AnalysisPeriod prev = period.previous;
    final DateTime previousCut = isCurrent
        ? DateTime(
            prev.start.year, prev.start.month, prev.start.day + daysElapsed)
        : prev.endExclusive;
    double previousToDate = 0;
    double previousTotal = 0;
    for (final ReceiptModel r in previousReceipts) {
      previousTotal += r.totalAmount;
      if (r.transactionDate.isBefore(previousCut)) {
        previousToDate += r.totalAmount;
      }
    }
    final double? changePercent = previousToDate > 0
        ? (total - previousToDate) / previousToDate * 100
        : null;
    final double avgPerDay = daysElapsed > 0 ? total / daysElapsed : 0;
    final double projected =
        (isCurrent && !isDay) ? avgPerDay * totalDays : total;

    // Total harian (untuk grafik periode bulan).
    final List<double> dailyTotals = period.mode == PeriodMode.month
        ? List<double>.filled(totalDays, 0)
        : const <double>[];
    if (period.mode == PeriodMode.month) {
      for (final ReceiptModel r in receipts) {
        final int d = r.transactionDate.day;
        if (d >= 1 && d <= totalDays) dailyTotals[d - 1] += r.totalAmount;
      }
    }

    // Toko.
    final Map<String, _MerchantAcc> merchants = <String, _MerchantAcc>{};
    for (final ReceiptModel r in receipts) {
      final String key = r.merchantName.trim().toLowerCase();
      if (key.isEmpty) continue;
      final _MerchantAcc acc =
          merchants.putIfAbsent(key, () => _MerchantAcc(r.merchantName.trim()));
      acc.visits++;
      acc.total += r.totalAmount;
    }
    final List<MerchantStat> topMerchants = merchants.values
        .map(
            (a) => MerchantStat(name: a.name, visits: a.visits, total: a.total))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    // Transaksi terbesar & hari dalam seminggu.
    ReceiptModel? biggest;
    final List<double> weekdayTotals = List<double>.filled(7, 0);
    for (final ReceiptModel r in receipts) {
      if (biggest == null || r.totalAmount > biggest.totalAmount) biggest = r;
      weekdayTotals[r.transactionDate.weekday - 1] += r.totalAmount;
    }
    int weekendDays = 0;
    int weekdayDays = 0;
    for (int d = 0; d < daysElapsed; d++) {
      final int wd = DateTime(start.year, start.month, start.day + d).weekday;
      if (wd >= 6) {
        weekendDays++;
      } else {
        weekdayDays++;
      }
    }
    final double weekendTotal = weekdayTotals[5] + weekdayTotals[6];
    final double weekendAvg = weekendDays > 0 ? weekendTotal / weekendDays : 0;
    final double weekdayAvg =
        weekdayDays > 0 ? (total - weekendTotal) / weekdayDays : 0;

    // Kategori.
    final List<CategoryTotal> cats = categories
        .where((c) => c.total > 0)
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final double categorySum = cats.fold<double>(0, (s, c) => s + c.total);
    final CategoryTotal? top = cats.isEmpty ? null : cats.first;
    final double topShare =
        (top != null && categorySum > 0) ? top.total / categorySum : 0;

    final List<Insight> insights = <Insight>[];
    final String periodText;
    final String compareText;
    final String periodNoun;
    switch (period.mode) {
      case PeriodMode.day:
        periodText = isCurrent ? 'Hari ini' : 'Pada hari itu';
        compareText = 'hari sebelumnya';
        periodNoun = 'hari ini';
      case PeriodMode.month:
        periodText =
            isCurrent ? 'Hingga tanggal $daysElapsed' : 'Sepanjang bulan';
        compareText =
            isCurrent ? 'periode yang sama bulan lalu' : 'bulan sebelumnya';
        periodNoun = 'bulan ini';
      case PeriodMode.year:
        periodText = isCurrent ? 'Sejak awal tahun' : 'Sepanjang tahun';
        compareText =
            isCurrent ? 'periode yang sama tahun lalu' : 'tahun sebelumnya';
        periodNoun = 'tahun ini';
    }
    final int minTransactions = isDay ? 1 : _minTransactions;

    if (count < minTransactions) {
      insights.add(const Insight(
        kind: InsightKind.info,
        title: 'Data masih sedikit',
        message:
            'Catat minimal 3 struk agar analisis kebiasaan belanja Anda lebih akurat.',
      ));
    } else {
      // 1. Tren dibanding bulan lalu.
      final double? change = changePercent;
      if (change != null) {
        final int pct = change.abs().round();
        if (change >= 15) {
          insights.add(Insight(
            kind: InsightKind.warning,
            title: 'Pengeluaran naik $pct%',
            message:
                '$periodText pengeluaran Anda ${Fmt.rupiah(total)}, lebih tinggi $pct% dari $compareText (${Fmt.rupiah(previousToDate)}).',
          ));
        } else if (change <= -10) {
          insights.add(Insight(
            kind: InsightKind.positive,
            title: 'Pengeluaran turun $pct%',
            message:
                'Bagus! $periodText pengeluaran Anda ${Fmt.rupiah(total)}, lebih hemat $pct% dari $compareText (${Fmt.rupiah(previousToDate)}).',
          ));
        } else {
          insights.add(Insight(
            kind: InsightKind.info,
            title: 'Pengeluaran stabil',
            message:
                'Pengeluaran Anda relatif sama dengan $compareText (${Fmt.rupiah(previousToDate)}).',
          ));
        }
      }

      // 2. Proyeksi akhir periode.
      final int minDays = period.mode == PeriodMode.year ? 30 : 3;
      if (isCurrent && !isDay && daysElapsed >= minDays && total > 0) {
        final bool overPrev =
            previousTotal > 0 && projected > previousTotal * 1.2;
        insights.add(Insight(
          kind: overPrev ? InsightKind.warning : InsightKind.info,
          title: period.mode == PeriodMode.year
              ? 'Proyeksi akhir tahun'
              : 'Proyeksi akhir bulan',
          message:
              'Dengan pola saat ini (${Fmt.rupiah(avgPerDay.round())} per hari), total $periodNoun diperkirakan ${Fmt.rupiah(projected.round())}'
              '${overPrev ? ', melebihi total periode sebelumnya (${Fmt.rupiah(previousTotal)}).' : '.'}',
        ));
      }

      // 3. Kategori dominan.
      if (top != null && topShare >= 0.5) {
        insights.add(Insight(
          kind: InsightKind.warning,
          title: '${top.categoryName} mendominasi',
          message:
              '${(topShare * 100).round()}% pengeluaran Anda (${Fmt.rupiah(top.total)}) untuk kategori ${top.categoryName}.',
        ));
      }

      // 4. Akhir pekan vs hari kerja.
      if (!isDay &&
          totalDays >= 7 &&
          count >= 5 &&
          weekendDays > 0 &&
          weekdayDays > 0) {
        if (weekdayAvg > 0 && weekendAvg > weekdayAvg * 1.5) {
          insights.add(Insight(
            kind: InsightKind.warning,
            title: 'Lebih boros di akhir pekan',
            message:
                'Rata-rata ${Fmt.rupiah(weekendAvg)} per hari di Sabtu-Minggu, dibanding ${Fmt.rupiah(weekdayAvg)} di hari kerja.',
          ));
        }
        int busiest = 0;
        for (int i = 1; i < 7; i++) {
          if (weekdayTotals[i] > weekdayTotals[busiest]) busiest = i;
        }
        if (weekdayTotals[busiest] > 0) {
          insights.add(Insight(
            kind: InsightKind.info,
            title: 'Hari paling boros: ${_weekdayNames[busiest]}',
            message:
                'Total belanja setiap hari ${_weekdayNames[busiest]} pada periode ini mencapai ${Fmt.rupiah(weekdayTotals[busiest])}.',
          ));
        }
      }

      // 5. Toko langganan.
      MerchantStat? frequent;
      for (final MerchantStat m in topMerchants) {
        if (frequent == null || m.visits > frequent.visits) frequent = m;
      }
      if (frequent != null && frequent.visits >= 3) {
        insights.add(Insight(
          kind: InsightKind.info,
          title: 'Langganan: ${frequent.name}',
          message:
              'Anda berbelanja ${frequent.visits} kali di ${frequent.name} dengan total ${Fmt.rupiah(frequent.total)}. '
              'Cek program member atau promo toko ini.',
        ));
      }

      // 6. Transaksi terbesar.
      if (biggest != null && total > 0) {
        final double share = biggest.totalAmount / total;
        if (share >= 0.3) {
          final DateTime d = biggest.transactionDate;
          insights.add(Insight(
            kind: InsightKind.warning,
            title: 'Satu struk mendominasi',
            message:
                '${Fmt.rupiah(biggest.totalAmount)} di ${biggest.merchantName} (${d.day}/${d.month}/${d.year}), setara ${(share * 100).round()}% dari total periode ini.',
          ));
        }
      }

      // 7. Belanja kecil yang menumpuk.
      final List<ReceiptModel> small =
          receipts.where((r) => r.totalAmount < _smallSpendLimit).toList();
      if (small.length >= 5 && small.length / count >= 0.4) {
        final double smallTotal =
            small.fold<double>(0, (s, r) => s + r.totalAmount);
        insights.add(Insight(
          kind: InsightKind.tip,
          title: 'Belanja kecil menumpuk',
          message:
              '${small.length} struk di bawah ${Fmt.rupiah(_smallSpendLimit)} menghabiskan ${Fmt.rupiah(smallTotal)}. Pembelian kecil yang sering mudah terlewat.',
        ));
      }

      // 8. Saran untuk kategori dominan.
      if (top != null && topShare >= 0.35) {
        final String? tip = tipFor(top.categoryName);
        if (tip != null) {
          insights.add(Insight(
            kind: InsightKind.tip,
            title: 'Saran untuk ${top.categoryName}',
            message: tip,
          ));
        }
      }
    }

    // Rekomendasi per kategori (selalu ada selama ada pengeluaran).
    final List<CategoryAdvice> advice = <CategoryAdvice>[
      for (final CategoryTotal c in cats)
        CategoryAdvice(
          categoryName: c.categoryName,
          total: c.total,
          sharePercent: categorySum > 0 ? c.total / categorySum * 100 : 0,
          tip: tipFor(c.categoryName) ?? _tips['Lainnya']!,
        ),
    ];

    return SpendingAnalytics(
      total: total,
      transactionCount: count,
      previousToDate: previousToDate,
      previousTotal: previousTotal,
      changePercent: changePercent,
      averagePerDay: avgPerDay,
      projectedTotal: projected,
      daysElapsed: daysElapsed,
      totalDays: totalDays,
      isCurrentMonth: isCurrent,
      topMerchants: topMerchants.take(5).toList(),
      dailyTotals: dailyTotals,
      persona: count >= _minTransactions ? _persona(top, topShare) : null,
      insights: _ordered(insights, 6),
      categoryAdvice: advice,
    );
  }

  static const List<String> monthNames = <String>[
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  /// Analisis tren: total per bulan dalam [year], dan total per tahun.
  TrendAnalytics analyzeTrends({
    required int year,
    required DateTime now,
    required List<double> monthlyTotals,
    required List<double> previousYearMonthlyTotals,
    required Map<int, double> yearlyTotals,
  }) {
    List<double> twelve(List<double> v) =>
        <double>[for (int i = 0; i < 12; i++) i < v.length ? v[i] : 0.0];
    final List<double> months = twelve(monthlyTotals);
    final List<double> prevMonths = twelve(previousYearMonthlyTotals);

    // Tahun berjalan dibandingkan hanya sampai bulan ini.
    final int cutoff =
        year == now.year ? now.month : (year > now.year ? 0 : 12);

    double sum = 0;
    int active = 0;
    int? peak;
    double peakValue = 0;
    for (int i = 0; i < 12; i++) {
      final double v = months[i];
      if (v > 0) {
        sum += v;
        active++;
        if (v > peakValue) {
          peakValue = v;
          peak = i + 1;
        }
      }
    }
    final double average = active > 0 ? sum / active : 0;

    double ytdCurrent = 0;
    double ytdPrevious = 0;
    for (int i = 0; i < cutoff; i++) {
      ytdCurrent += months[i];
      ytdPrevious += prevMonths[i];
    }
    final double? yoy =
        ytdPrevious > 0 ? (ytdCurrent - ytdPrevious) / ytdPrevious * 100 : null;

    final Map<int, double> yearly = Map<int, double>.fromEntries(
        yearlyTotals.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

    final List<Insight> insights = <Insight>[];
    if (active == 0 && yearly.isEmpty) {
      insights.add(const Insight(
        kind: InsightKind.info,
        title: 'Belum ada data tren',
        message:
            'Catat struk pada beberapa bulan agar tren bulanan dan tahunan dapat dianalisis.',
      ));
    } else if (active > 0) {
      final int pm = peak ?? 1;
      insights.add(Insight(
        kind: InsightKind.info,
        title: 'Bulan terboros: ${monthNames[pm - 1]}',
        message:
            'Pengeluaran tertinggi tahun $year terjadi pada ${monthNames[pm - 1]} sebesar ${Fmt.rupiah(peakValue)}. '
            'Rata-rata bulanan ${Fmt.rupiah(average.round())} (dari $active bulan tercatat).',
      ));

      final List<int> idx = <int>[
        for (int i = 0; i < 12; i++)
          if (months[i] > 0 && (cutoff == 0 || i < cutoff)) i,
      ];
      if (idx.length >= 3) {
        final int c = idx[idx.length - 1];
        final int b = idx[idx.length - 2];
        final int a = idx[idx.length - 3];
        if (c - b == 1 && b - a == 1) {
          if (months[a] < months[b] && months[b] < months[c]) {
            insights.add(Insight(
              kind: InsightKind.warning,
              title: 'Naik 3 bulan berturut-turut',
              message:
                  'Pengeluaran terus naik dari ${monthNames[a]} (${Fmt.rupiah(months[a])}) hingga ${monthNames[c]} (${Fmt.rupiah(months[c])}).',
            ));
          } else if (months[a] > months[b] && months[b] > months[c]) {
            insights.add(Insight(
              kind: InsightKind.positive,
              title: 'Turun 3 bulan berturut-turut',
              message:
                  'Pengeluaran terus turun dari ${monthNames[a]} (${Fmt.rupiah(months[a])}) hingga ${monthNames[c]} (${Fmt.rupiah(months[c])}). Pertahankan!',
            ));
          }
        }
      }
      if (idx.length >= 2) {
        final int last = idx[idx.length - 1];
        final int before = idx[idx.length - 2];
        if (last - before == 1 && months[before] > 0) {
          final double change =
              (months[last] - months[before]) / months[before] * 100;
          if (change.abs() >= 20) {
            final int pct = change.abs().round();
            insights.add(Insight(
              kind: change > 0 ? InsightKind.warning : InsightKind.positive,
              title: change > 0
                  ? '${monthNames[last]} naik $pct%'
                  : '${monthNames[last]} turun $pct%',
              message:
                  '${monthNames[last]} (${Fmt.rupiah(months[last])}) ${change > 0 ? 'lebih tinggi' : 'lebih rendah'} $pct% '
                  'dibanding ${monthNames[before]} (${Fmt.rupiah(months[before])}).',
            ));
          }
        }
      }
    }

    final double? y = yoy;
    if (y != null) {
      final int pct = y.abs().round();
      final String span = cutoff >= 12 || cutoff == 0
          ? 'Sepanjang tahun $year'
          : 'Januari hingga ${monthNames[cutoff - 1]} $year';
      if (y >= 15) {
        insights.add(Insight(
          kind: InsightKind.warning,
          title: 'Lebih boros $pct% dari tahun lalu',
          message:
              '$span pengeluaran ${Fmt.rupiah(ytdCurrent)}, naik $pct% dibanding rentang yang sama tahun ${year - 1} (${Fmt.rupiah(ytdPrevious)}).',
        ));
      } else if (y <= -10) {
        insights.add(Insight(
          kind: InsightKind.positive,
          title: 'Lebih hemat $pct% dari tahun lalu',
          message:
              '$span pengeluaran ${Fmt.rupiah(ytdCurrent)}, turun $pct% dibanding rentang yang sama tahun ${year - 1} (${Fmt.rupiah(ytdPrevious)}).',
        ));
      } else {
        insights.add(Insight(
          kind: InsightKind.info,
          title: 'Setara dengan tahun lalu',
          message:
              '$span pengeluaran ${Fmt.rupiah(ytdCurrent)}, relatif sama dengan tahun ${year - 1} (${Fmt.rupiah(ytdPrevious)}).',
        ));
      }
    }

    return TrendAnalytics(
      year: year,
      monthlyTotals: months,
      yearlyTotals: yearly,
      monthlyAverage: average,
      peakMonth: peak,
      activeMonths: active,
      yearOverYearPercent: yoy,
      insights: _ordered(insights, 5),
    );
  }

  /// Saran untuk satu kategori, juga dipakai di halaman validasi struk.
  static String? tipFor(String category) => _tips[_canonical(category)];

  /// Nama kategori backend ("Kebutuhan_Rumah_Tangga") dan tampilan disamakan.
  static String _canonical(String category) =>
      category.trim().replaceAll('_', ' ');

  /// Urutkan: peringatan, kabar baik, info, saran (urutan awal dipertahankan).
  List<Insight> _ordered(List<Insight> insights, int limit) {
    final List<MapEntry<int, Insight>> indexed = <MapEntry<int, Insight>>[
      for (int i = 0; i < insights.length; i++)
        MapEntry<int, Insight>(i, insights[i]),
    ]..sort((a, b) {
        final int byKind = a.value.kind.index.compareTo(b.value.kind.index);
        return byKind != 0 ? byKind : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).take(limit).toList();
  }

  static const Map<String, String> _tips = <String, String>{
    'Makanan':
        'Buat menu mingguan dan daftar belanja, masak sendiri 2-3 kali seminggu, dan beli bahan pokok di pasar atau grosir.',
    'Minuman':
        'Bawa botol minum dan seduh kopi/teh sendiri; minuman kemasan dan kopi kekinian yang dibeli rutin cepat menumpuk.',
    'Kebutuhan Rumah Tangga':
        'Beli sabun cuci, deterjen, dan tisu dalam kemasan besar atau isi ulang saat promo untuk menekan biaya per pemakaian.',
    'Perawatan Diri':
        'Pilih produk yang benar-benar dipakai dan manfaatkan kemasan isi ulang; hindari menimbun stok skincare.',
    'Kesehatan':
        'Pastikan perlindungan seperti BPJS atau asuransi aktif, beli obat generik bila setara, dan jaga pola hidup sehat.',
    'F&B':
        'Coba bawa bekal atau masak sendiri 2-3 kali seminggu untuk menekan biaya makan dan minum di luar.',
    'Transportasi':
        'Pertimbangkan transportasi umum atau berbagi tumpangan untuk perjalanan rutin.',
    'Belanja':
        'Buat daftar belanja dan tunda pembelian non-esensial 24 jam untuk menghindari belanja impulsif.',
    'Lainnya':
        'Periksa kembali barang di kategori Lainnya dan pindahkan ke kategori yang tepat agar rekap lebih akurat.',
  };

  static const Map<String, List<String>> _personas = <String, List<String>>{
    'Makanan': <String>[
      'Pencinta Kuliner',
      'Sebagian besar uang Anda untuk makanan. Menikmati makanan itu penting, pantau agar tetap terkendali.',
    ],
    'Minuman': <String>[
      'Penikmat Minuman',
      'Kopi, teh, dan minuman kemasan menjadi pos terbesar Anda. Seduh sendiri di rumah bisa jauh lebih hemat.',
    ],
    'Kebutuhan Rumah Tangga': <String>[
      'Penjaga Rumah',
      'Kebutuhan rumah menjadi prioritas Anda. Belanja dalam kemasan besar membantu menekan biaya.',
    ],
    'Perawatan Diri': <String>[
      'Pencinta Perawatan Diri',
      'Anda rajin merawat diri. Sabun, skincare, dan kosmetik mendominasi pengeluaran Anda.',
    ],
    'Kesehatan': <String>[
      'Peduli Kesehatan',
      'Anda memprioritaskan kesehatan. Pastikan perlindungan seperti BPJS atau asuransi sudah memadai.',
    ],
    'F&B': <String>[
      'Pencinta Kuliner',
      'Sebagian besar uang Anda mengalir ke makanan dan minuman. Pantau agar tetap terkendali.',
    ],
    'Transportasi': <String>[
      'Si Mobilitas Tinggi',
      'Anda banyak bergerak! Biaya perjalanan menjadi pos terbesar bulan ini.',
    ],
    'Belanja': <String>[
      'Pemburu Belanja',
      'Belanja umum mendominasi pengeluaran Anda. Daftar belanja membantu menghindari pembelian impulsif.',
    ],
    'Lainnya': <String>[
      'Pengeluar Beragam',
      'Banyak pengeluaran Anda belum terkategori khusus. Periksa kembali agar rekap lebih akurat.',
    ],
  };

  SpendingPersona _persona(CategoryTotal? top, double share) {
    if (top == null || share < 0.35) {
      return const SpendingPersona(
        title: 'Pengeluar Seimbang',
        description:
            'Pengeluaran Anda tersebar merata di berbagai kategori, pola yang sehat untuk keuangan jangka panjang.',
      );
    }
    final List<String>? entry = _personas[_canonical(top.categoryName)];
    return SpendingPersona(
      title: entry == null ? 'Pengeluar Beragam' : entry[0],
      description: entry == null
          ? 'Pengeluaran Anda didominasi satu kategori. Pantau agar tetap terkendali.'
          : entry[1],
      categoryName: top.categoryName,
      sharePercent: share * 100,
    );
  }
}

class _MerchantAcc {
  _MerchantAcc(this.name);

  final String name;
  int visits = 0;
  double total = 0;
}
