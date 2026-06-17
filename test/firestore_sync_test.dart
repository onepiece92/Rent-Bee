import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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
}
