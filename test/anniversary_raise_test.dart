import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';

/// The automatic anniversary raise must apply exactly once per anniversary,
/// however many times the app launches and wherever the device is.
///
/// buglog B01: outside Nepal's time zone the "last raised" stamp read back as
/// the previous BS month, so every launch raised the rent again — four
/// launches took 10,000 to 12,155. To see it fail on the old code, run this
/// file under another zone: `TZ=Asia/Singapore flutter test <this file>`.
void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<Unit> unit() async => (await repo.allUnits()).single;

  Future<void> seed() => repo.createUnit(UnitsCompanion.insert(
      code: 'A-01',
      tenantName: 'T',
      monthlyRent: 10000,
      startedOn: Value(adForBsMonthStart(2082, 3))));

  // Two months after the unit's first anniversary (Ashadh 2083).
  final asOf = adForBsMonthStart(2083, 5);

  test('launching four times on the same day raises once', () async {
    await seed();
    final rents = <int>[];
    for (var launch = 0; launch < 4; launch++) {
      await repo.applyAnniversaryRaises(percent: 5, asOf: asOf);
      rents.add((await unit()).monthlyRent);
    }
    expect(rents, [10500, 10500, 10500, 10500]);
  });

  test('the stamp names the anniversary month, from mid-month', () async {
    await seed();
    await repo.applyAnniversaryRaises(percent: 5, asOf: asOf);
    final stamp = (await unit()).lastRaisedOn!;
    expect(bsDate(stamp), (year: 2083, month: 3, day: 15));
  });

  test('a stamp seen a day early or late (another time zone) does not '
      're-raise', () async {
    await seed();
    await repo.applyAnniversaryRaises(percent: 5, asOf: asOf);
    for (final shift in [-14, 14, -30, 30]) {
      final u = await unit();
      await repo.updateUnit(u.copyWith(
          lastRaisedOn: Value(u.lastRaisedOn!.add(Duration(hours: shift)))));
      expect(await repo.applyAnniversaryRaises(percent: 5, asOf: asOf), 0,
          reason: 'stamp shifted $shift h');
      expect((await unit()).monthlyRent, 10500);
      // put the stamp back for the next shift
      await repo.updateUnit((await unit()).copyWith(lastRaisedOn: Value(u.lastRaisedOn)));
    }
  });

  test('an old-style stamp (1st of the month at midnight), read a day early, '
      'does not re-raise', () async {
    await repo.createUnit(UnitsCompanion.insert(
        code: 'B-01',
        tenantName: 'T',
        monthlyRent: 10500,
        startedOn: Value(adForBsMonthStart(2082, 3)),
        lastRaisedOn: Value(adForBsMonthStart(2083, 3)
            .subtract(const Duration(hours: 14)))));
    expect(await repo.applyAnniversaryRaises(percent: 5, asOf: asOf), 0);
    expect((await unit()).monthlyRent, 10500);
  });

  test('the next anniversary still raises', () async {
    await seed();
    await repo.applyAnniversaryRaises(percent: 5, asOf: asOf);
    final nextYear = adForBsMonthStart(2084, 3);
    expect(await repo.applyAnniversaryRaises(percent: 5, asOf: nextYear), 1);
    expect((await unit()).monthlyRent, 11025);
  });
}
