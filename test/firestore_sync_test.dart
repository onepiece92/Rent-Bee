import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/firestore_sync_service.dart';
import 'package:unit_ledger/data/ledger_repository.dart';

/// Builds an isolated "device": fresh in-memory drift + repo wired to a sync
/// service over the shared [fake] Firestore for owner [uid].
Future<({LedgerRepository repo, FirestoreSyncService sync})> _device(
    FakeFirebaseFirestore fake, String uid) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final repo = LedgerRepository(db);
  final sync =
      FirestoreSyncService(uid: uid, repo: repo, prefs: prefs, firestore: fake);
  repo.sync = sync;
  return (repo: repo, sync: sync);
}

CollectionReference<Map<String, dynamic>> _units(
        FakeFirebaseFirestore f, String uid) =>
    f.collection('users').doc(uid).collection('units');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Each test spins up several in-memory "devices"; that's intentional.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('local createUnit + markPaid push to Firestore', () async {
    final fake = FakeFirebaseFirestore();
    final d = await _device(fake, 'u1');

    final id = await d.repo.createUnit(UnitsCompanion.insert(
      code: 'A-01',
      tenantName: 'Rajesh',
      monthlyRent: 18000,
    ));
    final unit = (await d.repo.allUnits()).single;
    await d.repo.markPaid(unit, 2082, 2, amount: 18000);

    // Pushes are fire-and-forget — let them settle against the in-memory fake.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final unitDocs = await _units(fake, 'u1').get();
    expect(unitDocs.docs, hasLength(1));
    expect(unitDocs.docs.single.data()['code'], 'A-01');
    expect(unitDocs.docs.single.id, unit.cloudId); // doc id == cloudId

    final payDocs = await fake
        .collection('users')
        .doc('u1')
        .collection('payments')
        .get();
    expect(payDocs.docs, hasLength(1));
    expect(payDocs.docs.single.data()['amount'], 18000);
    expect(payDocs.docs.single.data()['unitCloudId'], unit.cloudId);
    expect(id, unit.id);
  });

  test('reconcile pulls cloud units + payments into a fresh device', () async {
    final fake = FakeFirebaseFirestore();
    const uid = 'u2';
    const cloudId = 'unit-cloud-1';

    // Seed the cloud directly (as if another device had pushed).
    await _units(fake, uid).doc(cloudId).set({
      'cloudId': cloudId,
      'code': 'B-02',
      'tenantName': 'Maya',
      'businessType': 'Grocery',
      'monthlyRent': 25000,
      'isActive': true,
      'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
    });
    await fake.collection('users').doc(uid).collection('payments').doc(
        '${cloudId}_2082_3').set({
      'unitCloudId': cloudId,
      'year': 2082,
      'month': 3,
      'amount': 25000,
      'method': 'cash',
      'createdAt': Timestamp.fromDate(DateTime(2025, 6, 1)),
    });

    final d = await _device(fake, uid);
    await d.sync.reconcile();

    final units = await d.repo.allUnits();
    expect(units, hasLength(1));
    expect(units.single.code, 'B-02');
    expect(units.single.cloudId, cloudId);

    final payments = await d.repo.allPayments();
    expect(payments, hasLength(1));
    expect(payments.single.amount, 25000);
    // Child resolved cloudId -> the freshly-inserted local unit id.
    expect(payments.single.unitId, units.single.id);
  });

  test(
      'new-device login restores the full account (units, deposits, payments, '
      'charges) from the cloud', () async {
    final fake = FakeFirebaseFirestore();
    const uid = 'owner-1';

    // ---- Device 1: the owner builds a real account; every write mirrors up
    // through the actual push + serialization path (not hand-written maps).
    final d1 = await _device(fake, uid);

    final aId = await d1.repo.createUnit(UnitsCompanion.insert(
      code: 'A-01',
      tenantName: 'Rajesh',
      monthlyRent: 18000,
      phone: const Value('9800000001'),
      depositAmount: const Value(36000), // 2 months held
      startedOn: Value(DateTime(2024, 6, 15)),
    ));
    final a = (await d1.repo.allUnits()).firstWhere((u) => u.id == aId);
    await d1.repo.markPaid(a, 2082, 2); // full
    await d1.repo.markPaid(a, 2082, 3, amount: 8000); // partial
    await d1.repo.setCharges(aId, 2082, 2, electricity: 1200, water: 300);

    // A second unit that has moved out with the deposit returned — the
    // "due back is settled" case must restore exactly (active=false, refunded).
    final bId = await d1.repo.createUnit(UnitsCompanion.insert(
      code: 'B-02',
      tenantName: 'Maya',
      monthlyRent: 25000,
      depositAmount: const Value(50000),
      isActive: const Value(false),
    ));
    final b = (await d1.repo.allUnits()).firstWhere((u) => u.id == bId);
    await d1.repo.setDepositRefunded(b, true);

    // Let the fire-and-forget pushes settle against the in-memory cloud.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // ---- Device 2: a brand-new device. Empty drift, empty prefs, same uid.
    final d2 = await _device(fake, uid);
    expect(await d2.repo.allUnits(), isEmpty); // nothing local yet
    await d2.sync.reconcile();

    // Units restored, keyed by stable cloudId, with deposit + lifecycle intact.
    final units = await d2.repo.allUnits();
    expect(units.map((u) => u.code).toSet(), {'A-01', 'B-02'});
    final ra = units.firstWhere((u) => u.code == 'A-01');
    final rb = units.firstWhere((u) => u.code == 'B-02');
    expect(ra.cloudId, a.cloudId);
    expect(ra.monthlyRent, 18000);
    expect(ra.phone, '9800000001');
    expect(ra.depositAmount, 36000);
    expect(ra.depositRefunded, isFalse);
    expect(ra.startedOn, DateTime(2024, 6, 15));
    expect(rb.isActive, isFalse);
    expect(rb.depositRefunded, isTrue);

    // Payments restored, including the partial, re-keyed to the new local ids.
    final pays = await d2.repo.allPayments();
    expect(pays, hasLength(2));
    final full = pays.firstWhere((p) => p.month == 2);
    final partial = pays.firstWhere((p) => p.month == 3);
    expect(full.amount, 18000);
    expect(full.unitId, ra.id); // child resolved to the restored unit
    expect(partial.amount, 8000);

    // Charges restored.
    final ch = await d2.repo.chargesFor(ra.id, 2082, 2);
    expect(ch, isNotNull);
    expect(ch!.electricity, 1200);
    expect(ch.water, 300);

    // The derived liability matches: A-01's 36000 held; B-02 refunded → 0 owed.
    final liab = await d2.repo.depositLiability();
    expect(liab.held, 36000);
    expect(liab.dueBack, 0);
    expect(liab.total, 36000);

    // Restore is non-destructive to the cloud: still exactly the 2 units.
    expect((await _units(fake, uid).get()).docs, hasLength(2));
  });

  test(
      'owner switch on a shared device wipes local and restores the new owner '
      "without bleeding data into either account's cloud", () async {
    final fake = FakeFirebaseFirestore();
    // One physical device = one drift db + one prefs, shared across logins.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = LedgerRepository(db);

    // ---- Owner A signs in, creates a unit, syncs (stamps owner = A).
    final syncA = FirestoreSyncService(
        uid: 'A', repo: repo, prefs: prefs, firestore: fake);
    repo.sync = syncA;
    await repo.createUnit(UnitsCompanion.insert(
      code: 'A-01',
      tenantName: 'Anil',
      monthlyRent: 10000,
    ));
    await syncA.reconcile();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(prefs.getString('ledger_owner_uid'), 'A');

    // Owner B already has data in the cloud (from some other device).
    await _units(fake, 'B').doc('b-cloud').set({
      'cloudId': 'b-cloud',
      'code': 'B-02',
      'tenantName': 'Bishnu',
      'monthlyRent': 22000,
      'isActive': true,
      'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
    });

    // ---- Owner B signs in on the SAME device (same repo/prefs/db).
    final syncB = FirestoreSyncService(
        uid: 'B', repo: repo, prefs: prefs, firestore: fake);
    repo.sync = syncB;
    await syncB.reconcile();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // Local now shows ONLY B's data; A's unit was wiped, not merged.
    final localCodes = (await repo.allUnits()).map((u) => u.code).toSet();
    expect(localCodes, {'B-02'});
    expect(prefs.getString('ledger_owner_uid'), 'B');

    // A's cloud is untouched — owner-change wipe is drift-only.
    expect((await _units(fake, 'A').get()).docs.map((d) => d.data()['code']),
        ['A-01']);
    // Data-bleed guard: A's local unit was NEVER pushed into B's cloud.
    final bCloud =
        (await _units(fake, 'B').get()).docs.map((d) => d.data()['code']).toSet();
    expect(bCloud, {'B-02'});
  });

  test('reconcile pushes a local-only unit up on first sync', () async {
    final fake = FakeFirebaseFirestore();
    const uid = 'u3';
    final d = await _device(fake, uid);

    // Local row exists, cloud is empty, never synced -> Case A pushes it up.
    await d.repo.createUnit(UnitsCompanion.insert(
      code: 'C-01',
      tenantName: 'Ramesh',
      monthlyRent: 30000,
    ));
    await d.sync.reconcile();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final unitDocs = await _units(fake, uid).get();
    expect(unitDocs.docs, hasLength(1));
    expect(unitDocs.docs.single.data()['code'], 'C-01');
  });

  test('owner settings (calendar + rate) round-trip across devices', () async {
    final fake = FakeFirebaseFirestore();
    const uid = 'settings-owner';
    final d1 = await _device(fake, uid);

    // Device 1 mirrors its preferences up.
    d1.sync.pushSettings('ad', 7.5);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // A fresh device pulls them at sign-in via fetchSettings.
    final d2 = await _device(fake, uid);
    final fetched = await d2.sync.fetchSettings();
    expect(fetched?['calendarMode'], 'ad');
    expect((fetched?['annualRaisePercent'] as num).toDouble(), 7.5);

    // Its live listener applies a later change made on device 1.
    String? gotMode;
    num? gotRate;
    d2.sync.onRemoteSettings = (m, r) {
      gotMode = m;
      gotRate = r;
    };
    d2.sync.attachListeners(() {}); // subscribes the root settings doc too
    await Future<void>.delayed(const Duration(milliseconds: 50));

    d1.sync.pushSettings('bs', 10);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(gotMode, 'bs');
    expect(gotRate?.toDouble(), 10);

    await d2.sync.detach();
  });
}
