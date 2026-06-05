import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/domain/money.dart';

void main() {
  group('Money', () {
    test('formats with en-IN grouping and Rs prefix', () {
      expect(Money.format(180000), 'Rs 1,80,000');
      expect(Money.format(18000), 'Rs 18,000');
      expect(Money.format(0), 'Rs 0');
    });
  });

  group('BsMonth navigation wraps year boundaries', () {
    test('previous below Baishakh decrements year', () {
      expect(const BsMonth(2082, 1).previous(), const BsMonth(2081, 12));
    });
    test('next above Chaitra increments year', () {
      expect(const BsMonth(2082, 12).next(), const BsMonth(2083, 1));
    });
    test('labels', () {
      expect(const BsMonth(2082, 2).label, 'Jestha 2082');
    });
  });

  group('LedgerRepository', () {
    late AppDatabase db;
    late LedgerRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LedgerRepository(db);
    });

    tearDown(() => db.close());

    test('mark paid then summary reflects collected/pending', () async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01',
        tenantName: 'Test',
        monthlyRent: 10000,
      ));
      final unit =
          await (db.select(db.units)..where((s) => s.id.equals(id)))
              .getSingle();

      var s = await repo.summary(2082, 2);
      expect(s.expected, 10000);
      expect(s.collected, 0);
      expect(s.pending, 10000);

      await repo.markPaid(unit, 2082, 2);
      s = await repo.summary(2082, 2);
      expect(s.collected, 10000);
      expect(s.pending, 0);
      expect(s.paidCount, 1);

      // undo reverts
      await repo.undo(id, 2082, 2);
      s = await repo.summary(2082, 2);
      expect(s.collected, 0);
    });

    test('editing rent does not change past recorded amounts', () async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: 'A-02',
        tenantName: 'Test2',
        monthlyRent: 10000,
      ));
      final unit =
          await (db.select(db.units)..where((s) => s.id.equals(id)))
              .getSingle();
      await repo.markPaid(unit, 2082, 2);

      // raise rent
      await repo.updateUnit(unit.copyWith(monthlyRent: 15000));

      final payments = await repo.paymentsForMonth(2082, 2);
      expect(payments.single.amount, 10000); // captured at mark time
    });

    test('months are independent', () async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: 'A-03',
        tenantName: 'Test3',
        monthlyRent: 5000,
      ));
      final unit =
          await (db.select(db.units)..where((s) => s.id.equals(id)))
              .getSingle();
      await repo.markPaid(unit, 2082, 2);

      expect((await repo.summary(2082, 2)).collected, 5000);
      expect((await repo.summary(2082, 3)).collected, 0);
    });

    // Anniversary dates use mid-June (well inside one BS year) so the AD→BS
    // mapping is stable: same AD month+day N years apart = same BS month, BS
    // year + N.
    test('anniversary raise: one year -> one raise, rounded; history intact',
        () async {
      final aId = await repo.createUnit(UnitsCompanion.insert(
        code: 'A-04',
        tenantName: 'T4',
        monthlyRent: 18333, // *1.05 = 19249.65 -> 19250
        startedOn: Value(DateTime(2025, 6, 15)),
      ));
      final a = await (db.select(db.units)..where((s) => s.id.equals(aId)))
          .getSingle();
      await repo.markPaid(a, 2082, 2); // recorded at the old rent

      final n = await repo.applyAnniversaryRaises(
          percent: 5, asOf: DateTime(2026, 6, 15));
      expect(n, 1);
      expect((await repo.allUnits()).single.monthlyRent, 19250);
      // Past payment captured at the old rent is unchanged.
      expect((await repo.paymentsForMonth(2082, 2)).single.amount, 18333);
    });

    test('anniversary raise: two missed years compound; then idempotent',
        () async {
      await repo.createUnit(UnitsCompanion.insert(
        code: 'A-05',
        tenantName: 'T5',
        monthlyRent: 10000,
        startedOn: Value(DateTime(2024, 6, 15)),
      ));
      final asOf = DateTime(2026, 6, 15);

      final n1 = await repo.applyAnniversaryRaises(percent: 10, asOf: asOf);
      expect(n1, 1);
      // 10000 -> 11000 -> 12100 (two anniversaries, compounding)
      expect((await repo.allUnits()).single.monthlyRent, 12100);

      // Re-running the same day raises nothing.
      final n2 = await repo.applyAnniversaryRaises(percent: 10, asOf: asOf);
      expect(n2, 0);
      expect((await repo.allUnits()).single.monthlyRent, 12100);
    });

    test('anniversary raise: skips new tenants, inactive, no-date, and 0%',
        () async {
      final asOf = DateTime(2026, 6, 15);
      // Started 2 weeks ago -> no anniversary yet.
      await repo.createUnit(UnitsCompanion.insert(
        code: 'B-01',
        tenantName: 'New',
        monthlyRent: 20000,
        startedOn: Value(DateTime(2026, 6, 1)),
      ));
      // Due by date but inactive -> skipped.
      await repo.createUnit(UnitsCompanion.insert(
        code: 'B-02',
        tenantName: 'Inactive',
        monthlyRent: 30000,
        isActive: const Value(false),
        startedOn: Value(DateTime(2020, 6, 15)),
      ));
      // No start date -> skipped.
      await repo.createUnit(UnitsCompanion.insert(
        code: 'B-03',
        tenantName: 'NoDate',
        monthlyRent: 40000,
      ));

      expect(await repo.applyAnniversaryRaises(percent: 5, asOf: asOf), 0);

      // 0% never raises, even an old active unit.
      await repo.createUnit(UnitsCompanion.insert(
        code: 'B-04',
        tenantName: 'Old',
        monthlyRent: 50000,
        startedOn: Value(DateTime(2020, 6, 15)),
      ));
      expect(await repo.applyAnniversaryRaises(percent: 0, asOf: asOf), 0);

      final rents = {
        for (final u in await repo.allUnits()) u.code: u.monthlyRent
      };
      expect(rents['B-01'], 20000);
      expect(rents['B-02'], 30000);
      expect(rents['B-03'], 40000);
      expect(rents['B-04'], 50000);
    });

    test('demo data: 3 years of history with rent that grows each year',
        () async {
      const anchor = BsMonth(2082, 6);
      await repo.generateDemoData(anchor, annualRaisePercent: 10, years: 3);

      final units = await repo.allUnits();
      expect(units.length, 10);

      // A-01 (i=0): start month = anchor.month = 6, base 18000, 3 anniversaries.
      final a01 = units.firstWhere((u) => u.code == 'A-01');
      expect(a01.monthlyRent, 23958); // 18000 ·1.1·1.1·1.1 -> 19800,21780,23958

      // A-01 falls on the ~70% "paid" cadence at both ends of the window.
      Future<int> amt(int year, int month) async =>
          (await repo.paymentsForMonth(year, month))
              .firstWhere((p) => p.unitId == a01.id)
              .amount;
      expect(await amt(2079, 7), 18000); // oldest month, base rent
      expect(await amt(2082, 6), 23958); // newest month, grown rent

      // The launch auto-raise is a no-op (lastRaisedOn already stamped).
      final asOf = adForBsMonthStart(2082, 6);
      expect(await repo.applyAnniversaryRaises(percent: 10, asOf: asOf), 0);

      // Spans 3 BS years of payments.
      final allPayments = await db.select(db.payments).get();
      final years = {for (final p in allPayments) p.year};
      expect(years.containsAll({2079, 2080, 2081, 2082}), isTrue);

      // Deposit is populated (~2 months of the starting rent) and held.
      expect(a01.depositAmount, 36000); // 18000 × 2
      expect(a01.depositRefunded, isFalse);

      // Utility charges exist for the current month.
      final ch = await repo.chargesFor(a01.id, 2082, 6);
      expect(ch, isNotNull);
      expect(ch!.electricity + ch.water + ch.service, greaterThan(0));

      // The last unit demonstrates a completed tenancy: vacant, deposit
      // refunded, and no payments/charges after move-out.
      final c02 = units.firstWhere((u) => u.code == 'C-02');
      expect(c02.isActive, isFalse);
      expect(c02.depositRefunded, isTrue);
      expect(c02.depositRefundedOn, isNotNull);
      expect(
          (await repo.paymentsForMonth(2082, 6)).any((p) => p.unitId == c02.id),
          isFalse);
      expect(await repo.chargesFor(c02.id, 2082, 6), isNull);
    });
  });
}
