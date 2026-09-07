import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/domain/models.dart';

/// Covers the v3 feature: tracked security deposit on a unit, and variable
/// per-month electricity/water/service charges (their own ledger, separate
/// from rent) — plus the v5 rent deduction that shares the charges row but,
/// unlike the charges, lowers the month's rent due.
void main() {
  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<Unit> seed(String code, {int rent = 10000}) async {
    final id = await repo.createUnit(UnitsCompanion.insert(
      code: code,
      tenantName: 'Tenant $code',
      monthlyRent: rent,
    ));
    return (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();
  }

  Future<Unit> reload(int id) =>
      (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();

  group('deposit', () {
    test('new units default to no deposit, held', () async {
      final u = await seed('A-01');
      expect(u.depositAmount, 0);
      expect(u.depositRefunded, false);
      expect(u.depositRefundedOn, isNull);
    });

    test('setDeposit stores the amount and floors negatives', () async {
      final u = await seed('A-02');
      await repo.setDeposit(u, 20000);
      expect((await reload(u.id)).depositAmount, 20000);

      await repo.setDeposit(await reload(u.id), -5);
      expect((await reload(u.id)).depositAmount, 0);
    });

    test('refunding stamps a date; marking held clears it', () async {
      final u = await seed('A-03');
      await repo.setDeposit(u, 15000);

      await repo.setDepositRefunded(
          await reload(u.id), true, on: DateTime(2025, 5, 20));
      var r = await reload(u.id);
      expect(r.depositRefunded, true);
      expect(r.depositRefundedOn, DateTime(2025, 5, 20));

      await repo.setDepositRefunded(r, false);
      r = await reload(u.id);
      expect(r.depositRefunded, false);
      expect(r.depositRefundedOn, isNull);
    });
  });

  group('charges', () {
    test('absent month returns null', () async {
      final u = await seed('B-01');
      expect(await repo.chargesFor(u.id, 2082, 2), isNull);
    });

    test('setCharges upserts the three amounts for a unit-month', () async {
      final u = await seed('B-02');
      await repo.setCharges(u.id, 2082, 2,
          electricity: 800, water: 300, service: 500);

      final c = await repo.chargesFor(u.id, 2082, 2);
      expect(c, isNotNull);
      expect(c!.electricity, 800);
      expect(c.water, 300);
      expect(c.service, 500);
    });

    test('re-setting the same month updates in place (no duplicate)', () async {
      final u = await seed('B-03');
      await repo.setCharges(u.id, 2082, 2, electricity: 800);
      await repo.setCharges(u.id, 2082, 2, electricity: 950, water: 200);

      final c = await repo.chargesFor(u.id, 2082, 2);
      expect(c!.electricity, 950);
      expect(c.water, 200);
      final rows = await db.select(db.charges).get();
      expect(rows.length, 1);
    });

    test('setting all-zero clears the row', () async {
      final u = await seed('B-04');
      await repo.setCharges(u.id, 2082, 2, electricity: 800);
      await repo.setCharges(u.id, 2082, 2,
          electricity: 0, water: 0, service: 0);
      expect(await repo.chargesFor(u.id, 2082, 2), isNull);
    });

    test('negatives floor to 0', () async {
      final u = await seed('B-05');
      await repo.setCharges(u.id, 2082, 2,
          electricity: -10, water: 300, service: -1);
      final c = await repo.chargesFor(u.id, 2082, 2);
      expect(c!.electricity, 0);
      expect(c.water, 300);
      expect(c.service, 0);
    });

    test('charges are per-month and per-unit', () async {
      final a = await seed('B-06');
      final b = await seed('B-07');
      await repo.setCharges(a.id, 2082, 2, electricity: 800);
      await repo.setCharges(a.id, 2082, 3, electricity: 900);
      await repo.setCharges(b.id, 2082, 2, electricity: 100);

      expect((await repo.chargesFor(a.id, 2082, 2))!.electricity, 800);
      expect((await repo.chargesFor(a.id, 2082, 3))!.electricity, 900);
      expect((await repo.chargesFor(b.id, 2082, 2))!.electricity, 100);
    });

    test('deleting a unit cascades its charges', () async {
      final u = await seed('B-08');
      await repo.setCharges(u.id, 2082, 2, electricity: 800);
      await repo.deleteUnit(u.id);
      expect(await db.select(db.charges).get(), isEmpty);
    });

    test('charges do not affect the rent summary', () async {
      final u = await seed('B-09', rent: 10000);
      await repo.setCharges(u.id, 2082, 2,
          electricity: 800, water: 300, service: 500);
      final s = await repo.summary(2082, 2);
      expect(s.expected, 10000); // rent only — charges excluded
      expect(s.collected, 0);
    });
  });

  group('deduction', () {
    test('setDeduction stores the amount and trimmed note on the month row',
        () async {
      final u = await seed('D-01');
      await repo.setDeduction(u.id, 2082, 2,
          amount: 500, note: ' 2 sacks rice ');
      final c = await repo.chargesFor(u.id, 2082, 2);
      expect(c, isNotNull);
      expect(c!.deduction, 500);
      expect(c.deductionNote, '2 sacks rice');
      expect(c.electricity, 0);
    });

    test('deduction and utility charges on the same month keep each other',
        () async {
      final u = await seed('D-02');
      await repo.setCharges(u.id, 2082, 2, electricity: 800, water: 300);
      await repo.setDeduction(u.id, 2082, 2, amount: 500, note: 'tea');
      var c = await repo.chargesFor(u.id, 2082, 2);
      expect(c!.electricity, 800);
      expect(c.water, 300);
      expect(c.deduction, 500);

      // Re-setting the charges must not wipe the deduction (or vice versa).
      await repo.setCharges(u.id, 2082, 2, electricity: 900);
      c = await repo.chargesFor(u.id, 2082, 2);
      expect(c!.electricity, 900);
      expect(c.water, 0);
      expect(c.deduction, 500);
      expect(c.deductionNote, 'tea');
      expect((await db.select(db.charges).get()).length, 1);
    });

    test('clearing the deduction drops its note; an all-zero row is deleted',
        () async {
      final u = await seed('D-03');
      await repo.setCharges(u.id, 2082, 2, electricity: 800);
      await repo.setDeduction(u.id, 2082, 2, amount: 500, note: 'tea');
      await repo.setDeduction(u.id, 2082, 2, amount: 0, note: 'stale');
      final c = await repo.chargesFor(u.id, 2082, 2);
      expect(c!.electricity, 800);
      expect(c.deduction, 0);
      expect(c.deductionNote, isNull);

      await repo.setCharges(u.id, 2082, 2); // zero the utilities too
      expect(await repo.chargesFor(u.id, 2082, 2), isNull);
    });

    test('negative amounts floor to 0', () async {
      final u = await seed('D-04');
      await repo.setDeduction(u.id, 2082, 2, amount: -50);
      expect(await repo.chargesFor(u.id, 2082, 2), isNull);
    });

    test('the deduction comes off that month\'s expected rent only', () async {
      final u = await seed('D-05', rent: 10000);
      await repo.setDeduction(u.id, 2082, 2, amount: 1500);
      final s = await repo.summary(2082, 2);
      expect(s.expected, 8500);
      expect(s.pending, 8500);
      expect((await repo.summary(2082, 3)).expected, 10000);
    });

    test('paying the net amount settles the month in full', () async {
      final u = await seed('D-06', rent: 10000);
      await repo.setDeduction(u.id, 2082, 2, amount: 1500);
      await repo.markPaid(u, 2082, 2, amount: 8500);
      final view = await repo.monthView(2082, 2);
      final row = view.rows.single;
      expect(row.rentDue, 8500);
      expect(row.status, PayStatus.paid);
      expect(row.remaining, 0);
      expect(view.summary.paidCount, 1);
      expect(view.summary.partialCount, 0);
    });

    test('markPaid with no amount records the net due, not the headline rent',
        () async {
      final u = await seed('D-07', rent: 10000);
      await repo.setDeduction(u.id, 2082, 2, amount: 1500);
      await repo.markPaid(u, 2082, 2);
      await repo.markPaid(u, 2082, 3); // no deduction → full rent
      final pays = await repo.allPayments();
      expect(pays.firstWhere((p) => p.month == 2).amount, 8500);
      expect(pays.firstWhere((p) => p.month == 3).amount, 10000);
    });

    test('a deduction covering the whole rent settles the month with no cash',
        () async {
      final u = await seed('D-08', rent: 10000);
      await repo.setDeduction(u.id, 2082, 2, amount: 12000);
      final view = await repo.monthView(2082, 2);
      final row = view.rows.single;
      expect(row.rentDue, 0);
      expect(row.status, PayStatus.paid);
      expect(view.summary.expected, 0);
      expect(view.summary.paidCount, 1);
      // History agrees, and a plain unpaid month still reads as unpaid.
      final h = await repo.history(u.id, BsMonth(2082, 2), months: 2);
      expect(h.first.isPaid, isTrue);
      expect(h.last.isPaid, isFalse);
    });

    test('history and period reports price months net of the deduction',
        () async {
      final u = await seed('D-09', rent: 10000);
      await repo.setDeduction(u.id, 2082, 2, amount: 1500);
      await repo.markPaid(u, 2082, 2, amount: 8500);

      final h = await repo.history(u.id, BsMonth(2082, 2), months: 1);
      expect(h.single.expected, 8500);
      expect(h.single.deduction, 1500);
      expect(h.single.isPaid, isTrue);

      final q = await repo.periodSummary(2082, 1, 3);
      expect(q.expected, 28500); // 10000 + 8500 + 10000
      expect(q.collected, 8500);
      expect(q.paidSlots, 1);
      expect(q.outstanding.single.amountOwed, 20000);
      expect(q.outstanding.single.monthsUnpaid, 2);
    });

    test('netDue and settles: the one rule behind status, history, summary',
        () {
      expect(netDue(10000, 1500), 8500);
      expect(netDue(10000, 12000), 0);
      expect(netDue(10000, -5), 10000);
      expect(netDue(-500, 100), 0); // a negative rent must not throw
      expect(settles(paid: 8500, due: 8500, deduction: 1500), isTrue);
      expect(settles(paid: 0, due: 0, deduction: 12000), isTrue);
      expect(settles(paid: 0, due: 0, deduction: 0), isFalse); // nothing at all
      expect(settles(paid: 100, due: 0, deduction: 0), isTrue);
      expect(settles(paid: 8000, due: 8500, deduction: 1500), isFalse);
    });

    test('a negative rent (unfloored restore) still renders a month view',
        () async {
      final u = await seed('D-10', rent: 10000);
      await repo.setDeduction(u.id, 2082, 2, amount: 300);
      await repo.updateUnit(u.copyWith(monthlyRent: -500));
      final view = await repo.monthView(2082, 2);
      expect(view.rows.single.rentDue, 0);
      expect(view.summary.expected, 0);
    });

    test('a deduction on a month before the tenant started is not "paid"',
        () async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: 'D-11',
        tenantName: 'Late starter',
        monthlyRent: 10000,
        startedOn: Value(adForBsMonthStart(2082, 4)),
      ));
      await repo.setDeduction(id, 2082, 2, amount: 500); // pre-start month
      final h = await repo.history(id, BsMonth(2082, 4), months: 3);
      final preStart = h.firstWhere((e) => e.month == 2);
      expect(preStart.expected, 0);
      expect(preStart.deduction, 0);
      expect(preStart.isPaid, isFalse);
    });

    test('markPaid records nothing when nothing is due', () async {
      final u = await seed('D-12', rent: 0);
      await repo.markPaid(u, 2082, 2);
      expect(await repo.allPayments(), isEmpty);

      final v = await seed('D-13', rent: 10000);
      await repo.markPaid(v, 2082, 2, amount: 4000);
      await repo.markPaid(v, 2082, 2, amount: 0); // blank = undo
      expect(await repo.allPayments(), isEmpty);
    });

    test('a cloud charge doc from a pre-deduction build keeps the local deduction',
        () async {
      final u = await seed('D-14');
      await repo.setDeduction(u.id, 2082, 2, amount: 700, note: 'flour');
      // What _applyChargeDoc builds for a doc carrying no deduction keys.
      await repo.applyRemoteCharge(ChargesCompanion.insert(
        unitId: u.id,
        year: 2082,
        month: 2,
        electricity: const Value(900),
      ));
      final c = await repo.chargesFor(u.id, 2082, 2);
      expect(c!.electricity, 900);
      expect(c.deduction, 700);
      expect(c.deductionNote, 'flour');
    });

    test('escalation off never converts lastRaisedOn', () async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: 'D-15',
        tenantName: 'Odd anchor',
        monthlyRent: 10000,
        startedOn: Value(DateTime(2024, 6, 15)),
        lastRaisedOn: Value(DateTime(1800, 1, 1)), // outside nepali_utils' range
      ));
      final u = (await repo.allUnits()).firstWhere((x) => x.id == id);
      expect(RentSchedule(u, 0).rentFor(2082, 2), 10000);
      expect((await repo.periodSummary(2082, 1, 3)).expected, 30000);
    });

    test('CSV export/import round-trips a deduction-settled month', () async {
      final u = await seed('D-16', rent: 10000);
      await repo.setDeduction(u.id, 2082, 2, amount: 1500, note: 'tea');
      await repo.markPaid(u, 2082, 2); // 8500 net
      final csv = await repo.exportCsvRange(2082, 2, 2);
      expect(csv.trim().split('\n').last, endsWith(',8500,1500'));

      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      final repo2 = LedgerRepository(db2);
      addTearDown(db2.close);
      await repo2.importCsv(csv, fallbackYear: 2082);
      final row = (await repo2.rowsForMonth(2082, 2)).single;
      expect(row.deduction, 1500);
      expect(row.status, PayStatus.paid);
      expect((await repo2.summary(2082, 2)).expected, 8500);
    });
  });
}
