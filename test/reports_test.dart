import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });

  tearDown(() => db.close());

  Future<Unit> makeUnit(String code, int rent,
      {bool active = true, DateTime? startedOn}) async {
    final id = await repo.createUnit(UnitsCompanion.insert(
      code: code,
      tenantName: code,
      monthlyRent: rent,
      isActive: Value(active),
      startedOn: startedOn == null ? const Value.absent() : Value(startedOn),
    ));
    return (db.select(db.units)..where((s) => s.id.equals(id))).getSingle();
  }

  group('periodSummary (quarter / year)', () {
    test('quarter totals: expected, collected, slots, per-month buckets',
        () async {
      final a = await makeUnit('A-01', 10000);
      final b = await makeUnit('A-02', 20000);
      // Month 1: both paid. Month 2: only A paid. Month 3: nobody.
      await repo.markPaid(a, 2082, 1);
      await repo.markPaid(b, 2082, 1);
      await repo.markPaid(a, 2082, 2);

      final p = await repo.periodSummary(2082, 1, 3);

      // expected = (10000 + 20000) monthly × 3 months
      expect(p.expected, 90000);
      // collected = 10000+20000 + 10000 + 0
      expect(p.collected, 40000);
      // settled (unit, month) slots: A·m1, B·m1, A·m2 = 3
      expect(p.paidSlots, 3);
      // total slots = 2 active units × 3 months
      expect(p.totalSlots, 6);

      expect(p.months.length, 3);
      expect(p.months[0].collected, 30000); // m1
      expect(p.months[1].collected, 10000); // m2
      expect(p.months[2].collected, 0); // m3
      expect(p.months[0].month, 1);
      expect(p.months[2].pending, 30000);
    });

    test('outstanding: full and partial shortfalls, sorted largest first',
        () async {
      final a = await makeUnit('A-01', 10000); // owes m2(partial)+m3
      final b = await makeUnit('A-02', 20000); // owes m3 only
      await repo.markPaid(a, 2082, 1);
      await repo.markPaid(a, 2082, 2, amount: 4000); // partial -> 6000 short
      await repo.markPaid(b, 2082, 1);
      await repo.markPaid(b, 2082, 2);

      final p = await repo.periodSummary(2082, 1, 3);

      expect(p.outstanding.length, 2);
      // B owes one full month (20000); A owes 6000 (m2 remainder) + 10000 (m3).
      final aDebt = p.outstanding.firstWhere((d) => d.unit.code == 'A-01');
      final bDebt = p.outstanding.firstWhere((d) => d.unit.code == 'A-02');
      expect(aDebt.amountOwed, 16000);
      expect(aDebt.monthsUnpaid, 2); // partial month counts as unpaid
      expect(bDebt.amountOwed, 20000);
      expect(bDebt.monthsUnpaid, 1);
      // Sorted by amountOwed desc: B (20000) before A (16000).
      expect(p.outstanding.first.unit.code, 'A-02');
    });

    test(
        'inactive units: excluded from expected/outstanding, but their '
        'payments still count in collected', () async {
      await makeUnit('A-01', 10000);
      final gone = await makeUnit('Z-09', 99999, active: false);
      // A payment recorded for a since-vacated unit is real income — it must
      // show in `collected`, while the unit owes nothing going forward.
      await repo.markPaid(gone, 2082, 1);

      final p = await repo.periodSummary(2082, 1, 3);
      expect(p.expected, 30000); // only the active unit's rent × 3
      expect(p.collected, 99999); // the vacated unit's payment is income
      expect(p.totalSlots, 3); // 1 active × 3
      expect(p.outstanding.every((d) => d.unit.code != 'Z-09'), isTrue);
    });

    test('full year spans months 1–12', () async {
      await makeUnit('A-01', 1000);
      final p = await repo.periodSummary(2082, 1, 12);
      expect(p.months.length, 12);
      expect(p.expected, 12000);
      expect(p.totalSlots, 12);
    });

    test('months before a unit\'s start date owe nothing (no phantom debt)',
        () async {
      // Moved in Poush (m9) 2082 — the year report must only expect m9–m12.
      await makeUnit('M-01', 10000,
          startedOn: adForBsMonthStart(2082, 9));

      final p = await repo.periodSummary(2082, 1, 12);
      expect(p.expected, 40000); // 4 months × 10000, not 12
      // m1–m8 owe nothing → count as settled slots; m9–m12 are unpaid.
      expect(p.paidSlots, 8);
      expect(p.outstanding.single.amountOwed, 40000);
      expect(p.outstanding.single.monthsUnpaid, 4);
      expect(p.months[0].expected, 0); // Baishakh, pre-start
      expect(p.months[8].expected, 10000); // Poush, first month due
    });

    test('month summary skips units that had not started by that month',
        () async {
      await makeUnit('M-01', 10000, startedOn: adForBsMonthStart(2082, 9));
      await makeUnit('N-01', 5000); // no start date → always counted

      final before = await repo.summary(2082, 5); // pre-start month
      expect(before.expected, 5000);
      expect(before.activeCount, 1);

      final after = await repo.summary(2082, 9);
      expect(after.expected, 15000);
      expect(after.activeCount, 2);
    });

    test('all settled: no outstanding, full progress', () async {
      final a = await makeUnit('A-01', 5000);
      for (var m = 1; m <= 3; m++) {
        await repo.markPaid(a, 2082, m);
      }
      final p = await repo.periodSummary(2082, 1, 3);
      expect(p.outstanding, isEmpty);
      expect(p.paidSlots, 3);
      expect(p.pending, 0);
      expect(p.percent, 100);
    });
  });

  group('history', () {
    test('recent months, newest first, with paid/partial flags and amounts',
        () async {
      final a = await makeUnit('A-01', 8000);
      // Pay Jestha (m2) in full and the prior Baishakh (m1) partially; leave
      // Chaitra (m12) unpaid.
      await repo.markPaid(a, 2082, 2);
      await repo.markPaid(a, 2082, 1, amount: 3000); // partial of 8000

      final h = await repo.history(a.id, const BsMonth(2082, 2), months: 3);

      expect(h.length, 3);
      // Newest first: m2 (full), then m1 (partial), then prior year m12 (empty).
      expect(h[0].month, 2);
      expect(h[0].isPaid, isTrue);
      expect(h[0].isPartial, isFalse);
      expect(h[0].amount, 8000);
      expect(h[1].month, 1);
      expect(h[1].isPaid, isFalse);
      expect(h[1].isPartial, isTrue);
      expect(h[1].amount, 3000); // history reports the recorded amount as-is
      // Walking back past Baishakh rolls into the previous BS year.
      expect(h[2].year, 2081);
      expect(h[2].month, 12);
      expect(h[2].isPaid, isFalse);
      expect(h[2].isPartial, isFalse);
      expect(h[2].amount, 0); // nothing collected reads as 0, not null
    });

    test('default window is 6 months', () async {
      final a = await makeUnit('A-01', 8000);
      final h = await repo.history(a.id, const BsMonth(2082, 6));
      expect(h.length, 6);
      expect(h.every((e) => !e.isPaid), isTrue);
    });
  });

  // A unit started Baishakh 2079 at 10000, raised 10%/yr for three
  // anniversaries → 10000 → 11000 → 12100 → 13310 (current, as of 2082).
  Future<Unit> ladderUnit() async {
    final id = await repo.createUnit(UnitsCompanion.insert(
      code: 'L-01',
      tenantName: 'Lakshmi',
      monthlyRent: 13310,
      startedOn: Value(adForBsMonthStart(2079, 1)),
      lastRaisedOn: Value(adForBsMonthStart(2082, 1)),
    ));
    return (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();
  }

  group('rentInEffect (historical rent)', () {
    test('unwinds escalation to the rent in effect each past year', () async {
      final u = await ladderUnit();
      expect(LedgerRepository.rentInEffect(u, 2079, 6, 10), 10000);
      expect(LedgerRepository.rentInEffect(u, 2080, 6, 10), 11000);
      expect(LedgerRepository.rentInEffect(u, 2081, 6, 10), 12100);
      expect(LedgerRepository.rentInEffect(u, 2082, 6, 10), 13310); // current
    });

    test('a mid-year anniversary changes the rent within the BS year', () async {
      // Started Jestha (month 2) 2079; raised once → 11000 as of 2080.
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: 'M-01',
        tenantName: 'Min',
        monthlyRent: 11000,
        startedOn: Value(adForBsMonthStart(2079, 2)),
        lastRaisedOn: Value(adForBsMonthStart(2080, 2)),
      ));
      final u = await (db.select(db.units)..where((x) => x.id.equals(id)))
          .getSingle();
      expect(LedgerRepository.rentInEffect(u, 2080, 1, 10), 10000); // pre-anniv
      expect(LedgerRepository.rentInEffect(u, 2080, 2, 10), 11000); // anniv on
    });

    test('falls back to current rent without a start date or with rate off',
        () async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: 'N-01', tenantName: 'Nita', monthlyRent: 9000)); // no startedOn
      final u = await (db.select(db.units)..where((x) => x.id.equals(id)))
          .getSingle();
      expect(LedgerRepository.rentInEffect(u, 2079, 6, 10), 9000);
      final laddered = await ladderUnit();
      expect(LedgerRepository.rentInEffect(laddered, 2079, 6, 0), 13310);
    });
  });

  group('periodSummary (no phantom debt after a raise)', () {
    test('a month paid in full at the old rate is not re-charged', () async {
      final u = await ladderUnit();
      // Fully paid Jestha 2080 at THAT year's rent (11000), not the current.
      await repo.markPaid(u, 2080, 2, amount: 11000);

      final s = await repo.periodSummary(2080, 1, 12, percent: 10);

      expect(s.expected, 12 * 11000); // not 12 × 13310 (current rent)
      final debt = s.outstanding.single;
      expect(debt.unit.code, 'L-01');
      expect(debt.monthsUnpaid, 11); // the paid month is settled
      expect(debt.amountOwed, 11 * 11000); // no 2310/mo phantom on the paid one
    });

    test('escalation off → flat current rent across the period', () async {
      final u = await ladderUnit();
      await repo.markPaid(u, 2080, 2, amount: 13310);
      final s = await repo.periodSummary(2080, 1, 12, percent: 0);
      expect(s.expected, 12 * 13310);
      expect(s.outstanding.single.amountOwed, 11 * 13310);
    });
  });
}
