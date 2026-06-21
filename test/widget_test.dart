import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/domain/models.dart';
import 'package:unit_ledger/domain/money.dart';

void main() {
  group('Money', () {
    test('formats with en-IN grouping and Rs prefix', () {
      expect(Money.format(180000), 'Rs 1,80,000');
      expect(Money.format(18000), 'Rs 18,000');
      expect(Money.format(0), 'Rs 0');
    });
    test('grouped omits the prefix but keeps en-IN grouping', () {
      expect(Money.grouped(180000), '1,80,000');
      expect(Money.grouped(0), '0');
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

    test('added 3 years ago at 10000 grows to 11576 at 5% (catch-up on add)',
        () async {
      // Mirrors the add flow: a unit entered with a start date 3 years back and
      // the rent it had then; the catch-up grows it to today across 3 years.
      await repo.createUnit(UnitsCompanion.insert(
        code: 'A-07',
        tenantName: 'T7',
        monthlyRent: 10000,
        startedOn: Value(DateTime(2023, 6, 15)),
      ));
      final n = await repo.applyAnniversaryRaises(
          percent: 5, asOf: DateTime(2026, 6, 15));
      expect(n, 1);
      // 10000 -> 10500 -> 11025 -> 11576 (rounded each year)
      expect((await repo.allUnits()).single.monthlyRent, 11576);
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

  group('Partial payments', () {
    late AppDatabase db;
    late LedgerRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LedgerRepository(db);
    });

    tearDown(() => db.close());

    Future<Unit> makeUnit(String code, int rent) async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: code,
        tenantName: code,
        monthlyRent: rent,
      ));
      return (db.select(db.units)..where((s) => s.id.equals(id))).getSingle();
    }

    test('a partial payment is partial, not paid; remaining is the shortfall',
        () async {
      final unit = await makeUnit('P-01', 10000);
      await repo.markPaid(unit, 2082, 2, amount: 4000);

      final row = (await repo.rowsForMonth(2082, 2)).single;
      expect(row.status, PayStatus.partial);
      expect(row.isPaid, isFalse);
      expect(row.isPartial, isTrue);
      expect(row.paidAmount, 4000);
      expect(row.remaining, 6000);

      final s = await repo.summary(2082, 2);
      expect(s.collected, 4000);
      expect(s.pending, 6000);
      expect(s.paidCount, 0); // a partial does not count as settled
      expect(s.partialCount, 1);
    });

    test('topping a partial up to full flips it to paid', () async {
      final unit = await makeUnit('P-02', 10000);
      await repo.markPaid(unit, 2082, 2, amount: 4000);
      // markPaid upserts on (unit, year, month): the second call replaces.
      await repo.markPaid(unit, 2082, 2, amount: 10000);

      final row = (await repo.rowsForMonth(2082, 2)).single;
      expect(row.status, PayStatus.paid);
      expect(row.remaining, 0);

      final s = await repo.summary(2082, 2);
      expect(s.paidCount, 1);
      expect(s.partialCount, 0);
      expect(s.collected, 10000);
      // No duplicate row was created by the second markPaid.
      expect((await repo.paymentsForMonth(2082, 2)).length, 1);
    });

    test('overpayment clamps pending to 0 and progress to 100%', () async {
      // Captured at 15000, then rent lowered to 10000 -> collected > expected.
      final unit = await makeUnit('P-03', 15000);
      await repo.markPaid(unit, 2082, 2); // amount defaults to 15000
      await repo.updateUnit(unit.copyWith(monthlyRent: 10000));

      final row = (await repo.rowsForMonth(2082, 2)).single;
      expect(row.status, PayStatus.paid);
      expect(row.remaining, 0); // floored, never negative

      final s = await repo.summary(2082, 2);
      expect(s.expected, 10000);
      expect(s.collected, 15000);
      expect(s.pending, 0); // floored, never negative
      expect(s.progress, 1.0); // clamped
      expect(s.percent, 100);
    });

    test('a zero-amount payment row reads as pending, not partial', () async {
      final unit = await makeUnit('P-04', 10000);
      await repo.markPaid(unit, 2082, 2, amount: 0);

      final row = (await repo.rowsForMonth(2082, 2)).single;
      expect(row.status, PayStatus.pending);

      final s = await repo.summary(2082, 2);
      expect(s.collected, 0);
      expect(s.paidCount, 0);
      expect(s.partialCount, 0);
    });

    test('empty / no active units: summary guards divide-by-zero', () async {
      final s = await repo.summary(2082, 2);
      expect(s.expected, 0);
      expect(s.progress, 0);
      expect(s.percent, 0);
      expect(s.pending, 0);
    });

    test('rowsForMonth orders pending before paid, then by code', () async {
      // Insert out of code order; pay one of them.
      final c = await makeUnit('C-01', 10000);
      await makeUnit('A-01', 10000);
      await makeUnit('B-01', 10000);
      await repo.markPaid(c, 2082, 2); // C is now paid -> sinks to the bottom

      final rows = await repo.rowsForMonth(2082, 2);
      // Pending (A, B by code) first, then the paid one (C) last.
      expect(rows.map((r) => r.unit.code).toList(), ['A-01', 'B-01', 'C-01']);
      expect(rows.last.isPaid, isTrue);
    });
  });

  group('BS <-> AD calendar helpers', () {
    test('bsYearMonth(adForBsMonthStart(y, m)) round-trips', () {
      for (final m in [1, 2, 6, 12]) {
        final ad = adForBsMonthStart(2082, m);
        final bs = bsYearMonth(ad);
        expect(bs.year, 2082);
        expect(bs.month, m);
      }
    });

    test('adForBsMonthStart is the first day of the BS month', () {
      // The Gregorian date labels as BS day 1 of that month.
      expect(dateLabel(adForBsMonthStart(2082, 2), CalendarMode.bs),
          startsWith('1 '));
    });

    test('monthNameIn(AD) maps Baishakh to April, Jestha to May', () {
      // The BS year opens in mid-April; Baishakh's first day is an April date.
      expect(const BsMonth(2082, 1).monthNameIn(CalendarMode.ad), 'April');
      expect(const BsMonth(2082, 2).monthNameIn(CalendarMode.ad), 'May');
      // BS mode keeps the Nepali name.
      expect(const BsMonth(2082, 2).monthNameIn(CalendarMode.bs), 'Jestha');
    });

    test('dateLabel formats per calendar mode', () {
      final d = DateTime(2025, 6, 15);
      expect(dateLabel(d, CalendarMode.ad), '15 Jun 2025');
      // First day of Jestha 2082 labels as "1 Jestha 2082" in BS.
      expect(dateLabel(adForBsMonthStart(2082, 2), CalendarMode.bs),
          '1 Jestha 2082');
    });

    test('labelIn renders month + year for each mode', () {
      expect(const BsMonth(2082, 2).labelIn(CalendarMode.bs), 'Jestha 2082');
      expect(const BsMonth(2082, 2).labelIn(CalendarMode.ad), 'May 2025');
    });
  });

  group('Deposit liability', () {
    late AppDatabase db;
    late LedgerRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LedgerRepository(db);
    });

    tearDown(() => db.close());

    Future<void> addUnit(String code,
        {required int deposit,
        bool active = true,
        bool refunded = false}) async {
      await repo.createUnit(UnitsCompanion.insert(
        code: code,
        tenantName: code,
        monthlyRent: 10000,
        isActive: Value(active),
        depositAmount: Value(deposit),
        depositRefunded: Value(refunded),
      ));
    }

    test('empty ledger has zero liability', () async {
      final l = await repo.depositLiability();
      expect(l.total, 0);
      expect(l.hasOverdue, isFalse);
    });

    test('active deposits are held; total is the sum', () async {
      await addUnit('A-01', deposit: 20000);
      await addUnit('A-02', deposit: 30000);

      final l = await repo.depositLiability();
      expect(l.held, 50000);
      expect(l.heldCount, 2);
      expect(l.dueBack, 0);
      expect(l.total, 50000);
      expect(l.hasOverdue, isFalse);
    });

    test('vacated-but-not-refunded deposit is due back (overdue)', () async {
      await addUnit('A-01', deposit: 20000); // active, held
      await addUnit('Z-09', deposit: 15000, active: false); // moved out, owed

      final l = await repo.depositLiability();
      expect(l.held, 20000);
      expect(l.dueBack, 15000);
      expect(l.dueBackCount, 1);
      expect(l.total, 35000); // both still owed back
      expect(l.hasOverdue, isTrue);
    });

    test('refunded deposits and zero-deposit units are excluded', () async {
      await addUnit('A-01', deposit: 20000); // counts
      await addUnit('B-02', deposit: 25000, refunded: true); // settled
      await addUnit('C-03',
          deposit: 18000, active: false, refunded: true); // settled
      await addUnit('D-04', deposit: 0); // no deposit

      final l = await repo.depositLiability();
      expect(l.held, 20000);
      expect(l.heldCount, 1);
      expect(l.dueBack, 0);
      expect(l.total, 20000);
    });
  });

  group('Cascade & reset', () {
    late AppDatabase db;
    late LedgerRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LedgerRepository(db);
    });

    tearDown(() => db.close());

    Future<Unit> makeUnit(String code) async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: code,
        tenantName: code,
        monthlyRent: 10000,
      ));
      return (db.select(db.units)..where((s) => s.id.equals(id))).getSingle();
    }

    test('deleting a unit cascades its payments', () async {
      final a = await makeUnit('A-01');
      final b = await makeUnit('A-02');
      await repo.markPaid(a, 2082, 2);
      await repo.markPaid(b, 2082, 2);

      await repo.deleteUnit(a.id);

      final remaining = await db.select(db.payments).get();
      expect(remaining.length, 1);
      expect(remaining.single.unitId, b.id); // only B's payment survives
      expect((await repo.allUnits()).single.id, b.id);
    });

    test('eraseAll clears units, payments, and charges', () async {
      final a = await makeUnit('A-01');
      await repo.markPaid(a, 2082, 2);
      await repo.setCharges(a.id, 2082, 2, electricity: 500, water: 200);

      await repo.eraseAll();

      expect(await repo.allUnits(), isEmpty);
      expect(await db.select(db.payments).get(), isEmpty);
      expect(await db.select(db.charges).get(), isEmpty); // FK cascade
    });
  });
}
