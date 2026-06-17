import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';

/// Verifies the JSON backup is a LOSSLESS round-trip: export → restore into a
/// fresh database reproduces every unit/payment/charge field, preserves cloud
/// identity, and remaps the per-device int ids correctly.
void main() {
  // Restore builds a second in-memory DB on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<Unit> unitById(AppDatabase d, int id) =>
      (d.select(d.units)..where((u) => u.id.equals(id))).getSingle();

  test('full round-trip preserves units, payments, charges, and cloudId',
      () async {
    // A rich unit: deposit refunded on a date, notes, phone, inactive, lease
    // anchors set.
    final id = await repo.createUnit(UnitsCompanion.insert(
      code: 'A-01',
      tenantName: 'Asha, Ltd.', // comma to exercise JSON (not CSV) escaping
      monthlyRent: 12500,
      businessType: const Value('Grocery'),
      phone: const Value('+9779801234501'),
      notes: const Value('Pays late sometimes'),
      isActive: const Value(false),
      startedOn: Value(DateTime(2024, 6, 15)),
      lastRaisedOn: Value(DateTime(2025, 6, 15)),
    ));
    final original = await unitById(db, id);
    await repo.setDeposit(original, 25000);
    await repo.setDepositRefunded(
        await unitById(db, id), true, on: DateTime(2025, 5, 20));

    await repo.markPaid(await unitById(db, id), 2082, 2,
        amount: 12500, paidOn: DateTime(2025, 5, 20), method: PayMethod.bank,
        note: 'cleared');
    await repo.markPaid(await unitById(db, id), 2082, 3, amount: 6000); // partial
    await repo.setCharges(id, 2082, 2, electricity: 800, water: 300, service: 500);

    final before = await unitById(db, id);
    final json = await repo.exportBackupJson(exportedAt: DateTime(2026, 6, 10));

    // Restore into a brand-new database.
    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    final repo2 = LedgerRepository(db2);
    addTearDown(db2.close);

    final counts = await repo2.importBackupJson(json);
    expect(counts, (units: 1, payments: 2, charges: 1));

    // Unit fields survive (note: int id is reassigned, cloudId is preserved).
    final restored = (await repo2.allUnits()).single;
    expect(restored.cloudId, before.cloudId);
    expect(restored.code, 'A-01');
    expect(restored.tenantName, 'Asha, Ltd.');
    expect(restored.monthlyRent, 12500);
    expect(restored.businessType, 'Grocery');
    expect(restored.phone, '+9779801234501');
    expect(restored.notes, 'Pays late sometimes');
    expect(restored.isActive, false);
    expect(restored.startedOn, DateTime(2024, 6, 15));
    expect(restored.lastRaisedOn, DateTime(2025, 6, 15));
    expect(restored.depositAmount, 25000);
    expect(restored.depositRefunded, true);
    expect(restored.depositRefundedOn, DateTime(2025, 5, 20));

    // Payments survive with method/note/date, remapped to the new unit id.
    final payments = await repo2.allPayments();
    expect(payments.length, 2);
    final feb = payments.firstWhere((p) => p.month == 2);
    expect(feb.unitId, restored.id);
    expect(feb.amount, 12500);
    expect(feb.method, PayMethod.bank);
    expect(feb.note, 'cleared');
    expect(feb.paidOn, DateTime(2025, 5, 20));
    expect(payments.firstWhere((p) => p.month == 3).amount, 6000);

    // Charges survive, remapped to the new unit id.
    final charges = await repo2.allCharges();
    expect(charges.length, 1);
    expect(charges.single.unitId, restored.id);
    expect(charges.single.electricity, 800);
    expect(charges.single.water, 300);
    expect(charges.single.service, 500);
  });

  test('restore REPLACES existing data (and clears charges via cascade)',
      () async {
    // Seed db2 with some pre-existing data that restore must wipe.
    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    final repo2 = LedgerRepository(db2);
    addTearDown(db2.close);
    final oldId = await repo2.createUnit(
        UnitsCompanion.insert(code: 'OLD-99', tenantName: 'Gone', monthlyRent: 1));
    await repo2.setCharges(oldId, 2082, 1, electricity: 999);

    // Back up a single different unit from the first db and restore it into db2.
    await repo.createUnit(
        UnitsCompanion.insert(code: 'NEW-01', tenantName: 'Fresh', monthlyRent: 5));
    final json = await repo.exportBackupJson();
    await repo2.importBackupJson(json);

    final units = await repo2.allUnits();
    expect(units.map((u) => u.code).toList(), ['NEW-01']); // OLD-99 gone
    // The old unit's charge must be gone too (no orphan rows).
    expect(await repo2.allCharges(), isEmpty);
  });

  test('importBackupJson rejects a non-backup file', () async {
    expect(
      () => repo.importBackupJson('{"app":"something-else"}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => repo.importBackupJson('not json at all'),
      throwsA(anything),
    );
  });

  test('exported JSON carries format + schema version headers', () async {
    await repo.createUnit(
        UnitsCompanion.insert(code: 'A-01', tenantName: 'X', monthlyRent: 100));
    final json = await repo.exportBackupJson();
    expect(json, contains('"app": "rent-bee"'));
    expect(json, contains('"type": "backup"'));
    expect(json, contains('"formatVersion": ${LedgerRepository.backupFormatVersion}'));
  });
}
