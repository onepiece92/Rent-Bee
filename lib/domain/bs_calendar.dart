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
  final bs = bsDate(date);
  return '${bs.day} ${BsCalendar.label(bs.month)} ${bs.year}';
}

// ---------------------------------------------------------------------------
// Gregorian → BS, as pure calendar arithmetic
// ---------------------------------------------------------------------------
//
// A [DateTime] in this app stands for a *calendar date* (its year/month/day),
// not an instant. `DateTime.toNepaliDateTime()` from nepali_utils must not be
// used for that: it converts the instant through "UTC + 5:45" and then
// truncates a local-time day count, so on a device east of Nepal, or in any
// daylight-saving zone, the first day of a BS month reads back as the last day
// of the previous one. That made the anniversary raise re-apply on every
// launch outside Nepal (buglog B01).
//
// The other direction — `NepaliDateTime(y, m, d).toDateTime()` — is plain
// arithmetic on the BS calendar tables and is right in every zone. So the
// Gregorian → BS conversion here is derived from it: find the BS month whose
// first day is the latest one on or before the date.

/// The range nepali_utils has calendar tables for.
const _minBsYear = 1970, _maxBsYear = 2250;

/// A zone-free day count for a Gregorian calendar date.
int _dayNumber(int y, int m, int d) =>
    DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

final Map<int, int> _monthStartDays = {};

/// Day number of the first day of BS ([year], [month]), memoised.
int _monthStartDay(int year, int month) =>
    _monthStartDays[year * 100 + month] ??= () {
      final d = NepaliDateTime(year, month, 1).toDateTime();
      return _dayNumber(d.year, d.month, d.day);
    }();

/// The Bikram Sambat date of the Gregorian calendar date [date] — the same
/// answer on every device, whatever its time zone. Dates outside the
/// supported BS range clamp to its first / last month rather than throwing,
/// so one bad stored date can't take the app down.
({int year, int month, int day}) bsDate(DateTime date) {
  final target = _dayNumber(date.year, date.month, date.day);
  if (target <= _monthStartDay(_minBsYear, 1)) {
    return (year: _minBsYear, month: 1, day: 1);
  }
  // BS new year falls in mid-April, so AD + 57 is the BS year from then on
  // (and one too many before it — the walk back below corrects that).
  var y = (date.year + 57).clamp(_minBsYear, _maxBsYear);
  var m = 1;
  while (_monthStartDay(y, m) > target) {
    if (m == 1) {
      y--;
      m = 12;
    } else {
      m--;
    }
  }
  while (true) {
    final ny = m == 12 ? y + 1 : y;
    final nm = m == 12 ? 1 : m + 1;
    if (ny > _maxBsYear || _monthStartDay(ny, nm) > target) break;
    y = ny;
    m = nm;
  }
  return (year: y, month: m, day: target - _monthStartDay(y, m) + 1);
}

/// The Bikram Sambat (year, month) a Gregorian [date] falls in. Used by the
/// annual lease escalation to anchor each unit's anniversary to its start month.
({int year, int month}) bsYearMonth(DateTime date) {
  final n = bsDate(date);
  return (year: n.year, month: n.month);
}

/// Gregorian DateTime for the first day of BS ([year], [month]).
DateTime adForBsMonthStart(int year, int month) =>
    NepaliDateTime(year, month, 1).toDateTime();

/// The date stamped on a unit as "last raised" for the anniversary in BS
/// ([year], [month]): the **15th at noon**, not the 1st at midnight. The
/// stamp is stored and synced as an instant, so a device in another time zone
/// can read it a day early or late; from mid-month that still lands in the
/// same BS month, which is all the stamp has to say.
DateTime raiseStampFor(int year, int month) {
  final d = NepaliDateTime(year, month, 15).toDateTime();
  return DateTime(d.year, d.month, d.day, 12);
}

/// The BS (year, month) a "last raised" [stamp] stands for. Tolerant of
/// stamps written the old way (the 1st at local midnight) and then read in a
/// zone where that instant is still the previous day: nudging two days
/// forward puts those back in their month and leaves mid-month stamps alone.
({int year, int month}) bsMonthOfRaiseStamp(DateTime stamp) =>
    bsYearMonth(stamp.add(const Duration(days: 2)));
