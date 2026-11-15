/// Jenis periode analisis.
enum PeriodMode { day, month, year }

/// Periode yang sedang dilihat: satu hari, satu bulan, atau satu tahun
/// (diadaptasi dari DashboardPeriod smart_receipt_v2).
class AnalysisPeriod {
  const AnalysisPeriod._(this.mode, this.anchor);

  factory AnalysisPeriod.day(DateTime date) => AnalysisPeriod._(
      PeriodMode.day, DateTime(date.year, date.month, date.day));

  factory AnalysisPeriod.month(int year, int month) =>
      AnalysisPeriod._(PeriodMode.month, DateTime(year, month));

  factory AnalysisPeriod.year(int year) =>
      AnalysisPeriod._(PeriodMode.year, DateTime(year));

  /// Periode berjenis [mode] yang memuat tanggal [date].
  factory AnalysisPeriod.containing(PeriodMode mode, DateTime date) {
    switch (mode) {
      case PeriodMode.day:
        return AnalysisPeriod.day(date);
      case PeriodMode.month:
        return AnalysisPeriod.month(date.year, date.month);
      case PeriodMode.year:
        return AnalysisPeriod.year(date.year);
    }
  }

  final PeriodMode mode;

  /// Hari: tanggal itu. Bulan: tanggal 1. Tahun: 1 Januari.
  final DateTime anchor;

  DateTime get start => anchor;

  /// Batas akhir (eksklusif).
  DateTime get endExclusive {
    switch (mode) {
      case PeriodMode.day:
        return DateTime(anchor.year, anchor.month, anchor.day + 1);
      case PeriodMode.month:
        return DateTime(anchor.year, anchor.month + 1);
      case PeriodMode.year:
        return DateTime(anchor.year + 1);
    }
  }

  AnalysisPeriod get previous {
    switch (mode) {
      case PeriodMode.day:
        return AnalysisPeriod.day(
            DateTime(anchor.year, anchor.month, anchor.day - 1));
      case PeriodMode.month:
        return AnalysisPeriod.month(anchor.year, anchor.month - 1);
      case PeriodMode.year:
        return AnalysisPeriod.year(anchor.year - 1);
    }
  }

  AnalysisPeriod get next {
    switch (mode) {
      case PeriodMode.day:
        return AnalysisPeriod.day(
            DateTime(anchor.year, anchor.month, anchor.day + 1));
      case PeriodMode.month:
        return AnalysisPeriod.month(anchor.year, anchor.month + 1);
      case PeriodMode.year:
        return AnalysisPeriod.year(anchor.year + 1);
    }
  }

  int get totalDays {
    final a = DateTime.utc(start.year, start.month, start.day);
    final b =
        DateTime.utc(endExclusive.year, endExclusive.month, endExclusive.day);
    return b.difference(a).inDays;
  }

  bool isCurrent(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(start) && today.isBefore(endExclusive);
  }

  /// Periode berikutnya hanya boleh dibuka bila sudah dimulai.
  bool canGoNext(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return !next.start.isAfter(today);
  }

  @override
  bool operator ==(Object other) =>
      other is AnalysisPeriod && other.mode == mode && other.anchor == anchor;

  @override
  int get hashCode => Object.hash(mode, anchor);
}
