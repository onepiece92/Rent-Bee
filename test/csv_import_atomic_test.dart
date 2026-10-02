import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/firestore_sync_service.dart';
import 'package:unit_ledger/data/ledger_repository.dart';

/// A CSV import is all or nothing: a file that fails part-way must leave the
/// ledger, the outbox and the cloud copy exactly as they were. (buglog B17.)
/// And a file that is not UTF-8 is refused rather than imported with damaged
/// names. (buglog B35.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  const header = 'year,month,code,tenant,rent,status,paid_on,method,amount,'
      'deduction,electricity,water,service';
  const good = '$header\n'
      '2082,2,A-01,Asha,10000,paid,2025-05-20,cash,10000,,500,,\n'
      '2082,2,A-02,Bina,9000,pending,,,,,,,\n'
      '2082,3,A-01,Asha,10000,paid,2025-06-20,cash,10000,,,,\n';

  /// Makes the database refuse one specific payment, so an import fails on a
  /// late row after earlier rows were already written.
  Future<void> rejectAmount(int amount) async {
    await repo.allUnits(); // open + migrate first
    await db.customStatement('CREATE TRIGGER reject_amount '
        'BEFORE INSERT ON payments WHEN NEW.amount = $amount '
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END");
  }

  test('a good file imports fully and queues every change', () async {
    final res = await repo.importCsv(good, fallbackYear: 2082);
    expect(res.unitsAdded, 2);
    expect(res.payments, 2);
    expect((await repo.allUnits()).length, 2);
    expect((await repo.paymentsForMonth(2082, 2)).length, 1);
    expect((await repo.paymentsForMonth(2082, 3)).length, 1);

    // 2 units + 2 payments + 1 charges row, each recorded once, in one go.
    final pending = await repo.pendingPushes();
    expect(pending.length, 5);
    expect({for (final p in pending) p.seq}.length, 1,
        reason: 'one import is one outbox entry set');
  });

  test('a failure on a late row rolls back the whole file', () async {
    await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01', tenantName: 'Original', monthlyRent: 8000));
    await repo.clearAllPending(1 << 62);
    await rejectAmount(666);

    const bad = '$header\n'
        '2082,2,A-01,Renamed,12000,paid,2025-05-20,cash,12000,,500,,\n'
        '2082,2,B-01,New unit,9000,paid,2025-05-21,cash,9000,,,,\n'
        '2082,3,A-01,Renamed,12000,paid,2025-06-20,cash,666,,,,\n';
    await expectLater(
        repo.importCsv(bad, fallbackYear: 2082), throwsA(anything));

    final units = await repo.allUnits();
    expect(units.length, 1, reason: 'B-01 must not be left behind');
    expect(units.single.tenantName, 'Original');
    expect(units.single.monthlyRent, 8000);
    expect(await repo.paymentsForMonth(2082, 2), isEmpty);
    expect(await repo.chargesForMonth(2082, 2), isEmpty);
    expect(await repo.pendingPushes(), isEmpty,
        reason: 'nothing to push: nothing happened');
  });

  test('with sync on, a failed import sends nothing to the cloud; a good one '
      'sends everything', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fake = FakeFirebaseFirestore();
    final sync = FirestoreSyncService(
        uid: 'owner', repo: repo, prefs: prefs, firestore: fake);
    repo.sync = sync;
    await sync.reconcile();
    await rejectAmount(666);
    Future<int> cloud(String name) async =>
        (await fake.collection('users').doc('owner').collection(name).get())
            .docs
            .length;
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 80));

    const bad = '$header\n'
        '2082,2,A-01,Asha,10000,paid,2025-05-20,cash,10000,,,,\n'
        '2082,3,A-01,Asha,10000,paid,2025-06-20,cash,666,,,,\n';
    await expectLater(
        repo.importCsv(bad, fallbackYear: 2082), throwsA(anything));
    await settle();
    expect(await cloud('units'), 0);
    expect(await cloud('payments'), 0);

    await repo.importCsv(good, fallbackYear: 2082);
    await settle();
    expect(await cloud('units'), 2);
    expect(await cloud('payments'), 2);
    expect(await cloud('charges'), 1);
    expect(await repo.pendingPushes(), isEmpty,
        reason: 'acknowledged by the cloud');
  });

  group('file encoding (B35)', () {
    test('UTF-8 text, with or without a byte-order mark, is read as is', () {
      final text = '$header\n2082,2,A-01,सीता श्रेष्ठ,10000,pending,,,,,,,\n';
      expect(LedgerRepository.decodeCsv(utf8.encode(text)), text);
      expect(
          LedgerRepository.decodeCsv([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]),
          text);
    });

    test('a Windows-1252 / Latin-1 file is refused, not mangled', () {
      final bytes = latin1.encode('$header\n2082,2,A-01,José,10000,,,,,,,,\n');
      expect(
          () => LedgerRepository.decodeCsv(bytes),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('CSV UTF-8'))));
    });

    test('a UTF-16 file (Excel "Unicode Text") is refused', () {
      expect(() => LedgerRepository.decodeCsv([0xFF, 0xFE, 0x63, 0x00]),
          throwsFormatException);
    });
  });
}
