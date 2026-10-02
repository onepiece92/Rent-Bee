import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/domain/models.dart';
import 'package:unit_ledger/state/ledger_provider.dart';

/// One rule prices a month everywhere — the Ledger row, the month summary,
/// the unit's history strip and Reports: the rent a recorded payment was made
/// against, else the rent in effect that month. And "pending" is what units
/// actually still owe. (buglog B05, B06.)
void main() {
  late AppDatabase db;
  late LedgerRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<Unit> add(String code, int rent,
      {DateTime? startedOn, DateTime? lastRaisedOn}) async {
    final id = await repo.createUnit(UnitsCompanion.insert(
      code: code,
      tenantName: 'Tenant $code',
      monthlyRent: rent,
      startedOn: Value(startedOn),
      lastRaisedOn: Value(lastRaisedOn),
    ));
    return (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();
  }

  Future<Unit> reload(Unit u) =>
      (db.select(db.units)..where((x) => x.id.equals(u.id))).getSingle();

  group('a paid month stays paid (B05)', () {
    test('after the rent is edited upward', () async {
      final u = await add('A-01', 10000);
      // The app records the payment against the rent the row showed.
      await repo.markPaid(u, 2082, 2, rent: 10000);
      await repo.updateUnit((await reload(u)).copyWith(monthlyRent: 12000));

      final row = (await repo.rowsForMonth(2082, 2)).single;
      expect(row.monthRent, 10000);
      expect(row.totalDue, 10000);
      expect(row.status, PayStatus.paid, reason: 'was "partial, 2,000 left"');

      final s = await repo.summary(2082, 2);
      expect(s.expected, 10000);
      expect(s.pending, 0);
      expect(s.paidCount, 1);

      final h = await repo.history(u.id, const BsMonth(2082, 2), months: 1);
      expect(h.single.isPaid, isTrue);

      // The year: that month owes nothing; the others are at the new rent.
      final y = await repo.periodSummary(2082, 1, 12);
      expect(y.outstanding.single.monthsUnpaid, 11);
      expect(y.outstanding.single.amountOwed, 11 * 12000);
      expect(y.expected, 10000 + 11 * 12000);
    });

    test('after the escalation rate changes', () async {
      // Started Ashadh 2080, raised 10% on each of two anniversaries.
      final u = await add('B-01', 12100,
          startedOn: adForBsMonthStart(2080, 3),
          lastRaisedOn: raiseStampFor(2082, 3));
      // Paid Baishakh 2082 (before that year's raise) at the rent then: 11,000.
      await repo.markPaid(u, 2082, 1, rent: 11000);

      // The owner now turns escalation off / changes it: reconstruction of
      // "the rent in effect then" changes, but the paid month must not.
      for (final rate in [0.0, 5.0, 10.0, 25.0]) {
        final h = await repo.history(u.id, const BsMonth(2082, 1),
            months: 1, percent: rate);
        expect(h.single.expected, 11000, reason: 'rate $rate');
        expect(h.single.isPaid, isTrue, reason: 'rate $rate');
        final row =
            (await repo.rowsForMonth(2082, 1, percent: rate)).single;
        expect(row.status, PayStatus.paid, reason: 'rate $rate');
      }
    });

    test('a payment with no recorded rent falls back to the reconstructed '
        'rent, as before', () async {
      final u = await add('C-01', 12100,
          startedOn: adForBsMonthStart(2080, 3),
          lastRaisedOn: raiseStampFor(2082, 3));
      await repo.markPaid(u, 2082, 1, amount: 11000); // no `rent:` given
      expect((await repo.allPayments()).single.rentAtPayment, isNull);
      final h = await repo.history(u.id, const BsMonth(2082, 1),
          months: 1, percent: 10);
      expect(h.single.expected, 11000);
      expect(h.single.isPaid, isTrue);
    });

    test('the recorded rent round-trips through a backup', () async {
      final u = await add('D-01', 10000);
      await repo.markPaid(u, 2082, 2, rent: 10000);
      final json = await repo.exportBackupJson();
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db2.close);
      final repo2 = LedgerRepository(db2);
      await repo2.importBackupJson(json);
      expect((await repo2.allPayments()).single.rentAtPayment, 10000);
    });
  });

  group('the Ledger prices a past month like Reports does', () {
    test('a month before a raise shows the rent in effect then', () async {
      await add('E-01', 11000,
          startedOn: adForBsMonthStart(2081, 3),
          lastRaisedOn: raiseStampFor(2082, 3));
      // Jestha 2082 is before the Ashadh 2082 raise → 10,000, not 11,000.
      final before = (await repo.rowsForMonth(2082, 2, percent: 10)).single;
      expect(before.totalDue, 10000);
      final after = (await repo.rowsForMonth(2082, 4, percent: 10)).single;
      expect(after.totalDue, 11000);
      // Row and summary agree.
      expect((await repo.summary(2082, 2, percent: 10)).expected, 10000);
    });

    test('a month before the tenant moved in owes nothing', () async {
      await add('F-01', 9000, startedOn: adForBsMonthStart(2082, 6));
      final row = (await repo.rowsForMonth(2082, 2)).single;
      expect(row.started, isFalse);
      expect(row.totalDue, 0);
      expect(row.status, PayStatus.pending); // nothing to collect, not "paid"
      expect((await repo.summary(2082, 2)).expected, 0);
    });

    test('the provider records the rent the row showed', () async {
      final u = await add('G-01', 11000,
          startedOn: adForBsMonthStart(2081, 3),
          lastRaisedOn: raiseStampFor(2082, 3));
      final ledger = LedgerProvider(repo,
          initialMonth: const BsMonth(2082, 2), raisePercent: () => 10);
      await ledger.refresh();
      expect(ledger.rowFor(u.id)!.totalDue, 10000);

      await ledger.markPaid(u); // "Collect" on a pre-raise month
      final p = (await repo.allPayments()).single;
      expect(p.amount, 10000);
      expect(p.rentAtPayment, 10000);
      expect(ledger.rowFor(u.id)!.status, PayStatus.paid);
    });
  });

  group('pending is what is actually still owed (B06)', () {
    test('a vacated unit that paid does not hide another unit\'s debt',
        () async {
      await add('H-01', 10000); // active, unpaid
      final b = await add('H-02', 10000);
      await repo.markPaid(b, 2082, 2, rent: 10000);
      await repo.updateUnit((await reload(b)).copyWith(isActive: false));

      final s = await repo.summary(2082, 2);
      expect(s.expected, 10000); // only the active unit
      expect(s.collected, 10000); // money really received
      expect(s.pending, 10000, reason: 'was 0: expected − collected');

      final p = await repo.periodSummary(2082, 2, 2);
      expect(p.pending, 10000);
      expect(p.months.single.pending, 10000);
    });

    test('an overpayment on one unit does not hide another unit\'s debt',
        () async {
      final a = await add('I-01', 10000);
      await add('I-02', 10000); // unpaid
      await repo.markPaid(a, 2082, 2, amount: 20000, rent: 10000);

      final s = await repo.summary(2082, 2);
      expect(s.expected, 20000);
      expect(s.collected, 20000);
      expect(s.pending, 10000);
    });

    test('fully collected reads as nothing pending', () async {
      final a = await add('J-01', 10000);
      await repo.markPaid(a, 2082, 2, rent: 10000);
      expect((await repo.summary(2082, 2)).pending, 0);
    });
  });

  group('acting on a debt from Reports (B07)', () {
    test('a period debt names the months that are unpaid', () async {
      final u = await add('K-01', 10000);
      await repo.markPaid(u, 2082, 1, rent: 10000);
      await repo.markPaid(u, 2082, 3, amount: 4000, rent: 10000); // partial
      final debt = (await repo.periodSummary(2082, 1, 4)).outstanding.single;
      expect(debt.unpaidMonths,
          const [BsMonth(2082, 2), BsMonth(2082, 3), BsMonth(2082, 4)]);
      expect(debt.monthsUnpaid, 3);
      expect(debt.amountOwed, 10000 + 6000 + 10000);
    });

    test('goToMonth loads that month, so Collect records it', () async {
      final u = await add('L-01', 10000);
      final ledger =
          LedgerProvider(repo, initialMonth: const BsMonth(2082, 6));
      await ledger.refresh();

      // Reports shows Bhadra (5) owing while the Ledger sits on Ashwin (6).
      await ledger.goToMonth(const BsMonth(2082, 5));
      expect(ledger.month, const BsMonth(2082, 5));
      expect(ledger.loading, isFalse);
      await ledger.markPaid(u);

      final p = (await repo.allPayments()).single;
      expect((p.year, p.month), (2082, 5),
          reason: 'used to record the Ledger\'s month instead');
    });
  });

  test('month summaries compare by value (S6)', () {
    const a = MonthSummary(
        expected: 100, collected: 40, paidCount: 1, activeCount: 2,
        outstanding: 60);
    const same = MonthSummary(
        expected: 100, collected: 40, paidCount: 1, activeCount: 2,
        outstanding: 60);
    const other = MonthSummary(
        expected: 100, collected: 40, paidCount: 1, activeCount: 2,
        outstanding: 50);
    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(other));
  });
}
