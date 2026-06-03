import 'package:intl/intl.dart';
import 'package:nepali_utils/nepali_utils.dart';

/// Bikram Sambat (BS) month helpers.
/// month is an integer 1–12 (Baishakh = 1 … Chaitra = 12).
class BsCalendar {
  static const List<String> monthLabels = [
    'Baishakh', // 1
    'Jestha', // 2
    'Ashadh', // 3
    'Shrawan', // 4
    'Bhadra', // 5
    'Ashwin', // 6
    'Kartik', // 7
    'Mangsir', // 8
    'Poush', // 9
    'Magh', // 10
    'Falgun', // 11
    'Chaitra', // 12
  ];

  static String label(int month) {
    assert(month >= 1 && month <= 12);
    return monthLabels[month - 1];
  }

  static String labelWithYear(int year, int month) => '${label(month)} $year';
}

/// An immutable (year, month) BS pointer with wrapping navigation.
class BsMonth {
  final int year;
  final int month; // 1–12

  const BsMonth(this.year, this.month);

  /// Rolling below Baishakh decrements the year; above Chaitra increments it.
  BsMonth previous() {
    if (month == 1) return BsMonth(year - 1, 12);
    return BsMonth(year, month - 1);
  }

  BsMonth next() {
    if (month == 12) return BsMonth(year + 1, 1);
    return BsMonth(year, month + 1);
  }

  String get label => BsCalendar.labelWithYear(year, month);

  /// Just the month name, e.g. "Jestha".
  String get monthName => BsCalendar.label(month);

  @override
  bool operator ==(Object other) =>
      other is BsMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => 'BsMonth($year, $month)';
}

/// Which calendar the UI labels dates in. Data is always stored in BS; AD is a
/// display-only relabeling (a BS month maps to the Gregorian month its first
/// day falls in).
enum CalendarMode { bs, ad }

extension BsMonthCalendar on BsMonth {
  /// Gregorian DateTime for the first day of this BS month.
  DateTime get _adStart => NepaliDateTime(year, month, 1).toDateTime();

  /// Full month name in [mode]: "Jestha" (BS) or "May" (AD).
  String monthNameIn(CalendarMode mode) =>
      mode == CalendarMode.ad ? DateFormat('MMMM').format(_adStart) : monthName;

  /// 3-letter month name for compact chips.
  String shortMonthNameIn(CalendarMode mode) => mode == CalendarMode.ad
      ? DateFormat('MMM').format(_adStart)
      : monthName.substring(0, 3);

  /// Year shown in [mode]: the BS year, or the Gregorian year of the start day.
  int yearIn(CalendarMode mode) =>
      mode == CalendarMode.ad ? _adStart.year : year;

  /// One-line label: "Jestha 2082" (BS) or "May 2025" (AD).
  String labelIn(CalendarMode mode) => mode == CalendarMode.ad
      ? DateFormat('MMMM yyyy').format(_adStart)
      : label;
}

/// Today's date formatted for [mode]: "12 May 2025" (AD) or "12 Jestha 2082"
/// (BS).
String todayLabel(CalendarMode mode) => dateLabel(DateTime.now(), mode);

/// A specific [date] formatted for [mode]: "12 May 2025" (AD) or
/// "12 Jestha 2082" (BS).
String dateLabel(DateTime date, CalendarMode mode) {
  if (mode == CalendarMode.ad) {
    return DateFormat('d MMM yyyy').format(date);
  }
  final bs = date.toNepaliDateTime();
  return '${bs.day} ${BsCalendar.label(bs.month)} ${bs.year}';
}

/// The Bikram Sambat (year, month) a Gregorian [date] falls in. Used by the
/// annual rent increase to anchor each unit's anniversary to its start month.
({int year, int month}) bsYearMonth(DateTime date) {
  final n = date.toNepaliDateTime();
  return (year: n.year, month: n.month);
}

/// Gregorian DateTime for the first day of BS ([year], [month]).
DateTime adForBsMonthStart(int year, int month) =>
    NepaliDateTime(year, month, 1).toDateTime();
