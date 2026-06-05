import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';

/// Covers the v3 feature: tracked security deposit on a unit, and variable
/// per-month electricity/water/service charges (their own ledger, separate
/// from rent).
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
}
