import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';

/// The production connection runs SQLite on a background isolate
/// (`NativeDatabase.createInBackground`, see `connection/native.dart`). Every
/// other test uses an in-memory database, so this is the one place the on-disk
/// + cross-isolate path is exercised: schema creation from empty, the
/// `beforeOpen` index statements, and a repository round trip.
void main() {
  test('on-disk database opens on a background isolate with its indexes',
      () async {
    final dir = await Directory.systemTemp.createTemp('rentbee_db_');
    final file = File('${dir.path}/ledger.sqlite');
    final db = AppDatabase(NativeDatabase.createInBackground(file));
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    final repo = LedgerRepository(db);

    final id = await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01', tenantName: 'Asha', monthlyRent: 10000));
    await repo.setDeduction(id, 2082, 2, amount: 500, note: 'tea');
    expect((await repo.summary(2082, 2)).expected, 9500);
    expect(file.existsSync(), isTrue);

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    expect(
      rows.map((r) => r.read<String>('name')).toSet(),
      containsAll([
        'idx_payments_year_month',
        'idx_charges_year_month',
        'idx_units_cloud_id',
      ]),
    );
  });
}
