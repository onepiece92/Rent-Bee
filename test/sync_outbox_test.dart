import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/firestore_sync_service.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/data/sync_types.dart';

/// Sync must never lose what was done on this device, never wipe the local
/// ledger through its own echoes, and never do work for nothing.
///
/// The mechanism under test is the local outbox (`PendingPushes`): every
/// local change records its key there, and the key is cleared only when the
/// cloud acknowledges it. Sync start pushes the outbox first; no pull or
/// listener touches a pending row. (buglog B03, B04, B12, B24, S1, S2.)
class _Device {
  final LedgerRepository repo;
  final FirestoreSyncService sync;
  final SharedPreferences prefs;
  _Device(this.repo, this.sync, this.prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const uid = 'owner';

  Future<_Device> device(FakeFirebaseFirestore fake, {String who = uid}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(db);
    final sync =
        FirestoreSyncService(uid: who, repo: repo, prefs: prefs, firestore: fake);
    repo.sync = sync;
    return _Device(repo, sync, prefs);
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  CollectionReference<Map<String, dynamic>> col(
          FakeFirebaseFirestore f, String name) =>
      f.collection('users').doc(uid).collection(name);

  /// A device that has completed its first sync with one unit, A-01.
  Future<(_Device, Unit)> synced(FakeFirebaseFirestore fake) async {
    final d = await device(fake);
    await d.repo.createUnit(UnitsCompanion.insert(
        code: 'A-01', tenantName: 'Asha', monthlyRent: 10000));
    await d.sync.reconcile();
    await settle();
    expect(await d.repo.pendingPushes(), isEmpty,
        reason: 'acknowledged pushes leave the outbox');
    return (d, (await d.repo.allUnits()).single);
  }

  group('changes made while sync is not attached (B03)', () {
    // The window in question: after unlock, before Firebase has restored the
    // session — or a whole session in which sync could not start.
    test('a payment is pushed at the next sync start, not deleted', () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);

      d.repo.sync = null; // sync not attached yet
      await d.repo.markPaid(unit, 2082, 2, amount: 10000);
      expect((await col(fake, 'payments').get()).docs, isEmpty);
      expect(await d.repo.pendingPushes(), hasLength(1));

      d.repo.sync = d.sync;
      await d.sync.reconcile();
      await settle();

      expect((await d.repo.allPayments()).single.amount, 10000,
          reason: 'the old reconcile deleted this as "removed elsewhere"');
      expect((await col(fake, 'payments').get()).docs.single.data()['amount'],
          10000);
      expect(await d.repo.pendingPushes(), isEmpty);
    });

    test('a new unit is pushed, not deleted', () async {
      final fake = FakeFirebaseFirestore();
      final (d, _) = await synced(fake);

      d.repo.sync = null;
      await d.repo.createUnit(UnitsCompanion.insert(
          code: 'B-01', tenantName: 'Bina', monthlyRent: 7000));
      d.repo.sync = d.sync;
      await d.sync.reconcile();
      await settle();

      expect((await d.repo.allUnits()).map((u) => u.code).toSet(),
          {'A-01', 'B-01'});
      expect(
          (await col(fake, 'units').get())
              .docs
              .map((x) => x.data()['code'])
              .toSet(),
          {'A-01', 'B-01'});
    });

    test('an edit is pushed, not overwritten by the cloud copy', () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);

      d.repo.sync = null;
      await d.repo.updateUnit(unit.copyWith(monthlyRent: 12500));
      d.repo.sync = d.sync;
      await d.sync.reconcile();
      await settle();

      expect((await d.repo.allUnits()).single.monthlyRent, 12500);
      expect(
          (await col(fake, 'units').get()).docs.single.data()['monthlyRent'],
          12500);
    });

    test('an undo is pushed, so the payment does not come back', () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);
      await d.repo.markPaid(unit, 2082, 2, amount: 10000);
      await settle();
      expect((await col(fake, 'payments').get()).docs, hasLength(1));

      d.repo.sync = null;
      await d.repo.undo(unit.id, 2082, 2);
      d.repo.sync = d.sync;
      await d.sync.reconcile();
      await settle();

      expect(await d.repo.allPayments(), isEmpty,
          reason: 'the cloud copy must not resurrect it');
      expect((await col(fake, 'payments').get()).docs, isEmpty);
    });

    test('a deleted unit stays deleted, along with its cloud children',
        () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);
      await d.repo.markPaid(unit, 2082, 2, amount: 10000);
      await d.repo.setCharges(unit.id, 2082, 2, electricity: 500);
      await settle();

      d.repo.sync = null;
      await d.repo.deleteUnit(unit.id);
      d.repo.sync = d.sync;
      await d.sync.reconcile();
      await settle();

      expect(await d.repo.allUnits(), isEmpty);
      expect((await col(fake, 'units').get()).docs, isEmpty);
      expect((await col(fake, 'payments').get()).docs, isEmpty);
      expect((await col(fake, 'charges').get()).docs, isEmpty);
    });

    test('a restore done offline replaces the cloud, and is not undone',
        () async {
      final fake = FakeFirebaseFirestore();
      final (d, _) = await synced(fake);
      // A backup of a different ledger.
      final other = await device(FakeFirebaseFirestore());
      other.repo.sync = null;
      await other.repo.createUnit(UnitsCompanion.insert(
          code: 'Z-09', tenantName: 'Zed', monthlyRent: 5000));
      final backup = await other.repo.exportBackupJson();

      d.repo.sync = null;
      await d.repo.importBackupJson(backup);
      d.repo.sync = d.sync;
      await d.sync.reconcile();
      await settle();

      expect((await d.repo.allUnits()).single.code, 'Z-09',
          reason: 'the pull must not put the pre-restore ledger back');
      expect((await col(fake, 'units').get()).docs.single.data()['code'], 'Z-09');
      expect(await d.repo.pendingPushes(), isEmpty);
    });
  });

  group('"Back up to cloud now" and other whole-ledger replaces (B04)', () {
    test('re-sync keeps the local ledger intact while listeners are live',
        () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);
      await d.repo.markPaid(unit, 2082, 2, amount: 10000);
      await settle();
      d.sync.attachListeners(() {});
      await settle();

      await d.repo.resyncAllToCloud();
      await settle();
      await settle();

      // Same rows, same local ids — nothing was deleted and re-created.
      final after = (await d.repo.allUnits()).single;
      expect(after.id, unit.id);
      expect((await d.repo.allPayments()).single.amount, 10000);
      expect((await col(fake, 'units').get()).docs, hasLength(1));
      expect((await col(fake, 'payments').get()).docs, hasLength(1));
      await d.sync.detach();
    });

    test('re-sync removes cloud documents that no longer exist locally',
        () async {
      final fake = FakeFirebaseFirestore();
      final (d, _) = await synced(fake);
      await col(fake, 'units').doc('stale').set({
        'cloudId': 'stale',
        'code': 'OLD-1',
        'tenantName': 'Gone',
        'monthlyRent': 1,
      });

      await d.repo.resyncAllToCloud();
      await settle();

      expect(
          (await col(fake, 'units').get()).docs.map((x) => x.data()['code']),
          ['A-01']);
    });

    test('erase all empties the cloud too', () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);
      await d.repo.markPaid(unit, 2082, 2, amount: 10000);
      await settle();

      await d.repo.eraseAll();
      await settle();

      expect(await d.repo.allUnits(), isEmpty);
      expect((await col(fake, 'units').get()).docs, isEmpty);
      expect((await col(fake, 'payments').get()).docs, isEmpty);
    });
  });

  group('two devices (B12, cross-device convergence)', () {
    test('a change on one device reaches the other through its listener',
        () async {
      final fake = FakeFirebaseFirestore();
      final (a, unit) = await synced(fake);
      final b = await device(fake);
      await b.sync.reconcile();
      b.sync.attachListeners(() {});
      await settle();
      expect((await b.repo.allUnits()).single.code, 'A-01');

      await a.repo.markPaid(unit, 2082, 3, amount: 9000);
      await settle();
      await settle();

      expect((await b.repo.allPayments()).single.amount, 9000);
      await b.sync.detach();
    });

    test('the same unit code created on two devices keeps both units',
        () async {
      final fake = FakeFirebaseFirestore();
      final (a, _) = await synced(fake);
      // Device B adds its own "A-01" before it has ever synced.
      final b = await device(fake);
      await b.repo.createUnit(UnitsCompanion.insert(
          code: 'A-01', tenantName: 'Bina', monthlyRent: 7000));
      await b.sync.reconcile();
      await settle();
      await a.sync.reconcile();
      await settle();
      await b.sync.reconcile();
      await settle();

      // Both tenants exist on both devices, under distinct codes — the old
      // code silently skipped the other device's unit and showed "synced".
      for (final d in [a, b]) {
        final units = await d.repo.allUnits();
        expect(units.map((u) => u.tenantName).toSet(), {'Asha', 'Bina'});
        expect(units.map((u) => u.code).toSet(), {'A-01', 'A-01-2'});
      }
      // …and they agree on which one was renamed.
      final codeOfBina = (await a.repo.allUnits())
          .firstWhere((u) => u.tenantName == 'Bina')
          .code;
      expect(
          (await b.repo.allUnits())
              .firstWhere((u) => u.tenantName == 'Bina')
              .code,
          codeOfBina);
    });
  });

  group('robustness and wasted work (B24, S1, S2)', () {
    test('one malformed cloud document does not stop the rest', () async {
      final fake = FakeFirebaseFirestore();
      await col(fake, 'units').doc('bad').set({'tenantName': 'No code'});
      await col(fake, 'units').doc('good').set({
        'cloudId': 'good',
        'code': 'G-01',
        'tenantName': 'Gita',
        'monthlyRent': 4000,
      });
      await col(fake, 'payments').doc('junk').set({'amount': 'not a number'});

      final d = await device(fake);
      await d.sync.reconcile();

      expect((await d.repo.allUnits()).single.code, 'G-01');
    });

    test('applying state the device already has writes and reports nothing',
        () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);
      final same = RemoteUnit(
        cloudId: unit.cloudId!,
        code: unit.code,
        tenantName: unit.tenantName,
        businessType: unit.businessType,
        monthlyRent: unit.monthlyRent,
        phone: unit.phone,
        notes: unit.notes,
        isActive: unit.isActive,
        createdAt: unit.createdAt,
        startedOn: unit.startedOn,
        lastRaisedOn: unit.lastRaisedOn,
        depositAmount: unit.depositAmount,
        depositRefunded: unit.depositRefunded,
        depositRefundedOn: unit.depositRefundedOn,
      );
      final again = await d.repo
          .applyRemote(units: [same], fullSnapshot: true, deleteMissing: true);
      expect(again.changed, isFalse);

      final different =
          await d.repo.applyRemote(units: [same.withCode('A-99')]);
      expect(different.changed, isTrue);
    });

    test('a local change does not refresh the UI again through its own echo',
        () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);
      var refreshes = 0;
      d.sync.attachListeners(() => refreshes++);
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      refreshes = 0; // ignore the initial listener snapshots

      await d.repo.markPaid(unit, 2082, 4, amount: 10000);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(refreshes, 0,
          reason: 'the write came back identical to the local row');
      await d.sync.detach();
    });

    test('a pending row is never overwritten or deleted by remote state',
        () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);
      d.repo.sync = null;
      await d.repo.markPaid(unit, 2082, 5, amount: 4321); // pending

      // The cloud (a stale view) says this payment is 1, then says it's gone.
      await d.repo.applyRemote(payments: [
        RemotePayment(
            unitCloudId: unit.cloudId!,
            year: 2082,
            month: 5,
            amount: 1,
            paidOn: null,
            method: PayMethod.cash,
            note: null),
      ]);
      await d.repo.applyRemote(
          removedChildren: [SyncKey.payment(unit.cloudId!, 2082, 5)]);
      await d.repo.applyRemote(fullSnapshot: true, deleteMissing: true, units: [
        RemoteUnit(
            cloudId: unit.cloudId!,
            code: unit.code,
            tenantName: unit.tenantName,
            businessType: unit.businessType,
            monthlyRent: unit.monthlyRent,
            phone: null,
            notes: null,
            isActive: true,
            createdAt: unit.createdAt,
            startedOn: null,
            lastRaisedOn: null,
            depositAmount: 0,
            depositRefunded: false,
            depositRefundedOn: null),
      ]);

      expect((await d.repo.allPayments()).single.amount, 4321);
    });

    test('signing out mid-start: a detached service attaches nothing',
        () async {
      final fake = FakeFirebaseFirestore();
      final (d, unit) = await synced(fake);
      await d.sync.detach();
      var applied = 0;
      d.sync.attachListeners(() => applied++);

      // Another device changes the cloud; the dead service must not react.
      await col(fake, 'units').doc(unit.cloudId).update({'monthlyRent': 1});
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(applied, 0);
      expect((await d.repo.allUnits()).single.monthlyRent, 10000);
    });
  });

  group('schema upgrade', () {
    test('a v2 database (before charges existed) upgrades cleanly (B28)',
        () async {
      // The v3 step creates the charges table with today's columns; the v5
      // step then tried to add `deduction` again and the app never opened.
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
        raw.execute('''
          CREATE TABLE units (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL UNIQUE,
            tenant_name TEXT NOT NULL,
            business_type TEXT NOT NULL DEFAULT '',
            monthly_rent INTEGER NOT NULL,
            phone TEXT, notes TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            started_on INTEGER, last_raised_on INTEGER)''');
        raw.execute('''
          CREATE TABLE payments (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            unit_id INTEGER NOT NULL REFERENCES units (id) ON DELETE CASCADE,
            year INTEGER NOT NULL, month INTEGER NOT NULL,
            amount INTEGER NOT NULL, paid_on INTEGER,
            method TEXT NOT NULL DEFAULT 'cash', note TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            UNIQUE (unit_id, year, month))''');
        raw.execute(
            "INSERT INTO units (code, tenant_name, monthly_rent) VALUES ('A-01', 'Old', 9000)");
        raw.execute('PRAGMA user_version = 2');
      }));
      addTearDown(db.close);
      final repo = LedgerRepository(db);

      final unit = (await repo.allUnits()).single; // triggers the migration
      expect(unit.code, 'A-01');
      expect(unit.cloudId, isNotNull); // v4 backfill ran
      await repo.setDeduction(unit.id, 2082, 2, amount: 500); // v5 columns
      expect((await repo.chargesFor(unit.id, 2082, 2))!.deduction, 500);
      expect(await repo.pendingPushes(), isNotEmpty); // v6 outbox table
    });
  });
}
