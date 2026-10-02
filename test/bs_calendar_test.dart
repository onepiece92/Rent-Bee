import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';

/// Gregorian ↔ Bikram Sambat conversion must be pure calendar arithmetic —
/// the same on every device. (buglog B01: the library's own conversion goes
/// through "UTC + 5:45" and broke outside Nepal's time zone.)
///
/// These assertions hold in ANY time zone; to see the old failure, run:
///   TZ=Asia/Singapore flutter test test/bs_calendar_test.dart
void main() {
  test('known anchors', () {
    expect(bsDate(DateTime(2025, 4, 14)), (year: 2082, month: 1, day: 1));
    expect(bsDate(DateTime(2026, 6, 15)), (year: 2083, month: 3, day: 1));
    expect(bsDate(DateTime(2026, 6, 14)).month, 2); // last day of Jestha 2083
    expect(bsDate(DateTime(2024, 6, 15)), (year: 2081, month: 3, day: 1));
  });

  test('the first day of every BS month reads back as that month', () {
    for (var y = 2070; y <= 2095; y++) {
      for (var m = 1; m <= 12; m++) {
        final first = adForBsMonthStart(y, m);
        expect(bsDate(first), (year: y, month: m, day: 1),
            reason: 'BS $y/$m starts $first');
        // …and the day before it is still the previous month.
        final prev = BsMonth(y, m).previous();
        final eve = DateTime(first.year, first.month, first.day - 1);
        expect(bsYearMonth(eve), (year: prev.year, month: prev.month),
            reason: 'day before BS $y/$m');
      }
    }
  });

  test('the time of day never changes the date', () {
    for (final h in [0, 1, 5, 6, 12, 18, 23]) {
      expect(bsYearMonth(DateTime(2026, 6, 15, h, 59)), (year: 2083, month: 3));
    }
  });

  test('dates outside the supported range clamp instead of throwing', () {
    expect(bsDate(DateTime(1800, 1, 1)), (year: 1970, month: 1, day: 1));
    expect(bsDate(DateTime(3000, 1, 1)).year, 2250);
  });

  test('BS dates label correctly', () {
    expect(dateLabel(DateTime(2026, 6, 15), CalendarMode.bs), '1 Ashadh 2083');
    expect(dateLabel(DateTime(2026, 6, 15), CalendarMode.ad), '15 Jun 2026');
  });

  group('raise stamp', () {
    test('round-trips to its BS month', () {
      for (var m = 1; m <= 12; m++) {
        expect(bsMonthOfRaiseStamp(raiseStampFor(2083, m)),
            (year: 2083, month: m));
      }
    });

    test('survives being read a day early or late (another time zone)', () {
      final stamp = raiseStampFor(2083, 3);
      for (final shift in [-36, -24, -13, 13, 24, 36]) {
        expect(bsMonthOfRaiseStamp(stamp.add(Duration(hours: shift))),
            (year: 2083, month: 3),
            reason: 'shifted $shift h');
      }
    });

    test('an old-style stamp (the 1st at midnight) read a day early still '
        'resolves to its month', () {
      final old = adForBsMonthStart(2083, 3); // 1 Ashadh, local midnight
      expect(bsMonthOfRaiseStamp(old), (year: 2083, month: 3));
      expect(bsMonthOfRaiseStamp(old.subtract(const Duration(hours: 14))),
          (year: 2083, month: 3));
    });
  });
}
