import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';

/// Covers the lossless JSON backup/restore feature:
///   exportBackupJson / importBackupJson  (lib/data/ledger_repository.dart)
///
/// Unlike the CSV export (a rent-only collection sheet), a backup must
/// round-trip EVERY persisted field — deposits, utility charges, occupancy,
/// lease-escalation anchors, payment methods/notes — and survive a restore onto
/// a fresh device (a new database with different local ids).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<Unit> unitById(LedgerRepository r, int id) =>
      (r.db.select(r.db.units)..where((u) => u.id.equals(id))).getSingle();

  test('round-trips every unit/payment/charge field onto a fresh database',
      () async {
    // A deliberately "full" unit: vacant, deposit refunded, lease anchors set,
    // contact metadata, and notes — all the fields CSV drops.
    final id = await repo.createUnit(UnitsCompanion.insert(
      code: 'A-01',
      tenantName: 'Asha',
      monthlyRent: 12000,
      businessType: const Value('Grocery'),
      phone: const Value('9801234501'),
      notes: const Value('corner shop, pays early'),
      isActive: const Value(false), // vacant
      startedOn: Value(DateTime(2023, 4, 14)),
      lastRaisedOn: Value(DateTime(2024, 4, 14)),
      depositAmount: const Value(24000),
      depositRefunded: const Value(true),
      depositRefundedOn: Value(DateTime(2025, 1, 10)),
    ));
    final unit = await unitById(repo, id);
    await repo.markPaid(unit, 2082, 2,
        amount: 12000,
        paidOn: DateTime(2025, 5, 20),
        method: PayMethod.bank,
        note: 'partial then topped up');
    await repo.setCharges(id, 2082, 2,
        electricity: 1500, water: 300, service: 400);

    final json = await repo.exportBackupJson();

    // Restore onto a brand-new database (simulating a new device / reinstall).
    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    final repo2 = LedgerRepository(db2);
    addTearDown(() => db2.close());
    final res = await repo2.importBackupJson(json);
    expect(res, (units: 1, payments: 1, charges: 1));

    final u = (await repo2.allUnits()).single;
    expect(u.code, 'A-01');
    expect(u.tenantName, 'Asha');
    expect(u.businessType, 'Grocery');
    expect(u.monthlyRent, 12000);
    expect(u.phone, '9801234501');
    expect(u.notes, 'corner shop, pays early');
    expect(u.isActive, false);
    expect(u.startedOn, DateTime(2023, 4, 14));
    expect(u.lastRaisedOn, DateTime(2024, 4, 14));
    expect(u.depositAmount, 24000);
    expect(u.depositRefunded, true);
    expect(u.depositRefundedOn, DateTime(2025, 1, 10));
    // Cross-device identity is preserved.
    expect(u.cloudId, unit.cloudId);

    final p = (await repo2.allPayments()).single;
    expect(p.unitId, u.id); // remapped to the new local id
    expect(p.year, 2082);
    expect(p.month, 2);
    expect(p.amount, 12000);
    expect(p.paidOn, DateTime(2025, 5, 20));
    expect(p.method, PayMethod.bank);
    expect(p.note, 'partial then topped up');

    final c = (await repo2.allCharges()).single;
    expect(c.unitId, u.id);
    expect(c.year, 2082);
    expect(c.month, 2);
    expect(c.electricity, 1500);
    expect(c.water, 300);
    expect(c.service, 400);
  });

  test('restore reassigns local ids and keeps payment/charge links correct',
      () async {
    final a = await repo.createUnit(
        UnitsCompanion.insert(code: 'A-01', tenantName: 'Asha', monthlyRent: 12000));
    final b = await repo.createUnit(
        UnitsCompanion.insert(code: 'B-01', tenantName: 'Bibek', monthlyRent: 5000));
    await repo.markPaid(await unitById(repo, a), 2082, 2, amount: 12000);
    await repo.markPaid(await unitById(repo, b), 2082, 2, amount: 5000);
    await repo.setCharges(b, 2082, 2, electricity: 999);

    final json = await repo.exportBackupJson();

    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    final repo2 = LedgerRepository(db2);
    addTearDown(() => db2.close());
    // Bump db2's autoincrement so restored ids cannot coincide with backup ids.
    for (var i = 0; i < 5; i++) {
      await repo2.createUnit(UnitsCompanion.insert(
          code: 'TMP-$i', tenantName: 't', monthlyRent: 1));
    }

    await repo2.importBackupJson(json); // erases the temps, inserts at high ids

    final units = await repo2.allUnits();
    expect(units.length, 2);
    final byCode = {for (final u in units) u.code: u};
    // Backup ids were small (1,2); restored ids are past the bumped counter.
    expect(byCode['A-01']!.id, greaterThan(5));

    final payments = await repo2.allPayments();
    final unitIds = units.map((u) => u.id).toSet();
    expect(payments.every((p) => unitIds.contains(p.unitId)), isTrue);
    // Linkage is correct by code, not just "points at some unit".
    final aPay = payments.firstWhere((p) => p.unitId == byCode['A-01']!.id);
    final bPay = payments.firstWhere((p) => p.unitId == byCode['B-01']!.id);
    expect(aPay.amount, 12000);
    expect(bPay.amount, 5000);

    final charge = (await repo2.allCharges()).single;
    expect(charge.unitId, byCode['B-01']!.id);
    expect(charge.electricity, 999);
  });

  test('rejects a non-backup JSON file and leaves existing data intact',
      () async {
    await repo.createUnit(
        UnitsCompanion.insert(code: 'KEEP-01', tenantName: 'Keep', monthlyRent: 9999));

    await expectLater(
      repo.importBackupJson('{"app":"something-else","type":"backup"}'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      repo.importBackupJson('not even json'),
      throwsA(isA<FormatException>()),
    );

    final units = await repo.allUnits();
    expect(units.length, 1);
    expect(units.single.code, 'KEEP-01');
  });

  test('a malformed row aborts the restore atomically (no half-erased ledger)',
      () async {
    await repo.createUnit(
        UnitsCompanion.insert(code: 'KEEP-01', tenantName: 'Keep', monthlyRent: 9999));

    // Valid unit, but a payment row missing its required `year` — the cast
    // throws mid-transaction, which must roll back the erase too.
    const bad = '{"app":"rent-bee","type":"backup",'
        '"units":[{"id":1,"code":"X","tenantName":"t","monthlyRent":1}],'
        '"payments":[{"unitId":1,"month":2,"amount":5}],'
        '"charges":[]}';
    await expectLater(repo.importBackupJson(bad), throwsA(anything));

    final units = await repo.allUnits();
    expect(units.length, 1, reason: 'erase must roll back on failure');
    expect(units.single.code, 'KEEP-01');
  });

  test('CSV export stays rent-only — proving the two formats are distinct',
      () async {
    final id = await repo.createUnit(UnitsCompanion.insert(
      code: 'A-01',
      tenantName: 'Asha',
      monthlyRent: 12000,
      depositAmount: const Value(24000),
    ));
    await repo.setCharges(id, 2082, 2, electricity: 1500);

    final csv = await repo.exportCsvRange(2082, 2, 2);
    expect(csv, isNot(contains('1500')), reason: 'charges are not in the CSV');
    expect(csv, isNot(contains('24000')), reason: 'deposits are not in the CSV');

    // …but the JSON backup carries both.
    final json = await repo.exportBackupJson();
    expect(json, contains('1500'));
    expect(json, contains('24000'));
  });
}
