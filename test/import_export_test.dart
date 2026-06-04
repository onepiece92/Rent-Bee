import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';

/// Covers the CSV import/export feature end to end:
///   exportCsv / exportCsvRange  (lib/data/ledger_repository.dart)
///   importCsv                   (same)
void main() {
  // Round-trip tests open a second in-memory DB on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<Unit> seed(String code, String tenant, int rent) async {
    final id = await repo.createUnit(UnitsCompanion.insert(
      code: code,
      tenantName: tenant,
      monthlyRent: rent,
    ));
    return (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();
  }

  group('exportCsv (single month)', () {
    test('header and a paid row', () async {
      final u = await seed('A-01', 'Asha', 10000);
      await repo.markPaid(u, 2082, 2,
          amount: 10000, paidOn: DateTime(2025, 5, 20));

      final csv = await repo.exportCsv(2082, 2);
      final lines = csv.trim().split('\n');

      expect(lines.first, 'code,tenant,rent,status,paid_on,method,amount');
      expect(lines[1], 'A-01,Asha,10000,paid,2025-05-20,cash,10000');
    });

    test('pending unit exports with empty amount', () async {
      await seed('A-02', 'Bibek', 5000);
      final csv = await repo.exportCsv(2082, 2);
      final row = csv.trim().split('\n')[1];
      expect(row, 'A-02,Bibek,5000,pending,,,');
    });

    test('quotes fields containing a comma', () async {
      await seed('A-03', 'Sharma, Gita', 8000);
      final csv = await repo.exportCsv(2082, 2);
      expect(csv, contains('A-03,"Sharma, Gita",8000,'));
    });
  });

  group('exportCsvRange (year)', () {
    test('has a leading month column with BS month label', () async {
      final u = await seed('B-01', 'Cad', 12000);
      await repo.markPaid(u, 2082, 2,
          amount: 12000, paidOn: DateTime(2025, 5, 20));

      final csv = await repo.exportCsvRange(2082, 1, 12);
      final lines = csv.trim().split('\n');
      expect(lines.first,
          'month,code,tenant,rent,status,paid_on,method,amount');
      // 12 months x 1 unit = 12 data rows
      expect(lines.length, 13);
      expect(lines, contains('Jestha,B-01,Cad,12000,paid,2025-05-20,cash,12000'));
      expect(lines, contains('Baishakh,B-01,Cad,12000,pending,,,'));
    });
  });

  group('importCsv', () {
    test('round-trips units and payments via exportCsvRange', () async {
      final u1 = await seed('R-01', 'Tenant One', 10000);
      await seed('R-02', 'Tenant Two', 20000);
      await repo.markPaid(u1, 2082, 2,
          amount: 10000, paidOn: DateTime(2025, 5, 20));

      final csv = await repo.exportCsvRange(2082, 1, 12);

      // Import into a fresh database.
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      final repo2 = LedgerRepository(db2);
      addTearDown(db2.close);

      final res = await repo2.importCsv(csv, fallbackYear: 2082);
      expect(res.unitsAdded, 2);
      expect(res.unitsUpdated, 0);
      expect(res.payments, 1);

      final units = await repo2.allUnits();
      expect(units.map((u) => u.code).toSet(), {'R-01', 'R-02'});
      expect(units.firstWhere((u) => u.code == 'R-01').monthlyRent, 10000);

      final s = await repo2.summary(2082, 2);
      expect(s.collected, 10000);
    });

    test('single-month export round-trips units but not payments '
        '(no month column)', () async {
      final u = await seed('M-01', 'Mick', 7000);
      await repo.markPaid(u, 2082, 2, amount: 7000);

      final csv = await repo.exportCsv(2082, 2); // no month column
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      final repo2 = LedgerRepository(db2);
      addTearDown(db2.close);

      final res = await repo2.importCsv(csv, fallbackYear: 2082);
      expect(res.unitsAdded, 1);
      // Payment is skipped because there is no month to anchor it.
      expect(res.payments, 0);
    });

    test('is idempotent — re-importing adds nothing new', () async {
      final u = await seed('I-01', 'Ida', 9000);
      await repo.markPaid(u, 2082, 3, amount: 9000);
      final csv = await repo.exportCsvRange(2082, 1, 12);

      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      final repo2 = LedgerRepository(db2);
      addTearDown(db2.close);

      final first = await repo2.importCsv(csv, fallbackYear: 2082);
      expect(first.unitsAdded, 1);

      final second = await repo2.importCsv(csv, fallbackYear: 2082);
      expect(second.unitsAdded, 0);
      expect(second.unitsUpdated, 0);
      expect((await repo2.allUnits()).length, 1);
    });

    test('updates an existing unit\'s tenant and rent', () async {
      await seed('U-01', 'Old Name', 5000);
      const csv = 'code,tenant,rent\nU-01,New Name,6000\n';
      final res = await repo.importCsv(csv, fallbackYear: 2082);
      expect(res.unitsAdded, 0);
      expect(res.unitsUpdated, 1);
      final u = (await repo.allUnits()).single;
      expect(u.tenantName, 'New Name');
      expect(u.monthlyRent, 6000);
    });

    test('headers are case-insensitive and order-independent', () async {
      const csv =
          'Amount,Status,Month,CODE,Tenant,Rent\n10000,paid,Jestha,Z-01,Zed,10000\n';
      final res = await repo.importCsv(csv, fallbackYear: 2082);
      expect(res.unitsAdded, 1);
      expect(res.payments, 1);
      expect((await repo.summary(2082, 2)).collected, 10000);
    });

    test('accepts a numeric month as well as a name', () async {
      const csv = 'code,month,amount,status\nN-01,2,4000,paid\n';
      final res = await repo.importCsv(csv, fallbackYear: 2082);
      expect(res.payments, 1);
      expect((await repo.summary(2082, 2)).collected, 4000);
    });

    test('uses the year column when present over the fallback', () async {
      const csv = 'code,year,month,amount,status\nY-01,2083,2,5000,paid\n';
      await repo.importCsv(csv, fallbackYear: 2082);
      expect((await repo.summary(2082, 2)).collected, 0);
      expect((await repo.summary(2083, 2)).collected, 5000);
    });

    test('pending rows create no payment', () async {
      const csv = 'code,month,amount,status\nP-01,2,0,pending\n';
      final res = await repo.importCsv(csv, fallbackYear: 2082);
      expect(res.unitsAdded, 1);
      expect(res.payments, 0);
    });

    test('throws when the code column is missing', () async {
      const csv = 'tenant,rent\nNobody,1000\n';
      expect(
        () => repo.importCsv(csv, fallbackYear: 2082),
        throwsA(isA<FormatException>()),
      );
    });

    test('empty or header-only content is a no-op', () async {
      final res = await repo.importCsv('code,tenant,rent\n', fallbackYear: 2082);
      expect(res, (unitsAdded: 0, unitsUpdated: 0, payments: 0));
    });

    test('tolerates CRLF line endings', () async {
      const csv = 'code,month,amount,status\r\nC-01,2,3000,paid\r\n';
      final res = await repo.importCsv(csv, fallbackYear: 2082);
      expect(res.payments, 1);
    });
  });
}
