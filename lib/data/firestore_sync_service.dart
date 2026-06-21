import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/sync_status.dart';
import 'database.dart';
import 'ledger_repository.dart';

/// Live mirror of the local drift ledger into Cloud Firestore, scoped per owner
/// at `users/{uid}/`. Drift stays the source of truth for the UI; this service
/// (a) **pushes** every local mutation up (fire-and-forget — see
/// [LedgerRepository]'s write-through calls) and (b) **applies** remote changes
/// back down into drift via the repository's drift-only `applyRemote*` methods.
///
/// Echo loops are impossible by construction: the apply path never pushes, and
/// listeners additionally skip this device's own un-acked writes
/// (`metadata.hasPendingWrites`). Identity is the unit's stable [Unit.cloudId]
/// (a UUID), since the local int `id` differs per device and `code` is editable.
///
/// "Online required is fine" (the chosen model): Firestore's own offline queue
/// provides durability; we do not engineer a separate offline-merge layer.
class FirestoreSyncService {
  final String uid;
  final LedgerRepository repo;
  final SharedPreferences prefs;
  final FirebaseFirestore _fs;

  /// Surfaced cloud-sync state for the UI (optional — null in tests).
  final SyncStatusController? status;

  FirestoreSyncService({
    required this.uid,
    required this.repo,
    required this.prefs,
    this.status,
    FirebaseFirestore? firestore,
  }) : _fs = firestore ?? FirebaseFirestore.instance;

  // Number of pushes currently in flight; while > 0 we report `syncing`.
  int _pending = 0;

  /// Applies owner settings (calendar mode + escalation rate) arriving on the
  /// owner's settings doc.
  void Function(String? calendarMode, num? rate)? onRemoteSettings;

  static const _kSyncedOnce = 'synced_once';
  static const _kOwnerUid = 'ledger_owner_uid';
  static const _maxBatch = 450; // < Firestore's 500-op ceiling, with headroom.

  DocumentReference<Map<String, dynamic>> get _root =>
      _fs.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _units =>
      _root.collection('units');
  CollectionReference<Map<String, dynamic>> get _payments =>
      _root.collection('payments');
  CollectionReference<Map<String, dynamic>> get _charges =>
      _root.collection('charges');

  String _childId(String unitCloudId, int year, int month) =>
      '${unitCloudId}_${year}_$month';

  final List<StreamSubscription<dynamic>> _subs = [];

  // Child docs (payments/charges) that arrived before their unit — buffered by
  // unit cloudId and drained once the unit lands locally (see [_drain]).
  final Map<String, List<_PendingChild>> _pendingChildren = {};

  // Coalesce the flurry of refresh()es a multi-doc snapshot (or a demo/import
  // storm) would otherwise trigger into a single trailing UI refresh.
  Timer? _refreshDebounce;
  VoidCallback? _onApply;

  // =========================================================================
  // Push (called from the repository after each local write; fire-and-forget)
  // =========================================================================

  void upsertUnit(Unit u) {
    final cloudId = u.cloudId;
    if (cloudId == null) return;
    _fire(() => _units.doc(cloudId).set(_unitToMap(u)));
  }

  void upsertUnits(List<Unit> us) {
    _fire(() => _commitChunked([
          for (final u in us)
            if (u.cloudId != null) _Op.set(_units.doc(u.cloudId), _unitToMap(u)),
        ]));
  }

  /// Firestore has no cascade — delete the unit's payment/charge docs too.
  void deleteUnit(String cloudId) {
    _fire(() async {
      final ops = <_Op>[_Op.delete(_units.doc(cloudId))];
      for (final col in [_payments, _charges]) {
        final kids =
            await col.where('unitCloudId', isEqualTo: cloudId).get();
        ops.addAll(kids.docs.map((d) => _Op.delete(d.reference)));
      }
      await _commitChunked(ops);
    });
  }

  void upsertPayment(Payment p, String unitCloudId) {
    _fire(() => _payments
        .doc(_childId(unitCloudId, p.year, p.month))
        .set(_paymentToMap(p, unitCloudId)));
  }

  void deletePayment(String unitCloudId, int year, int month) {
    _fire(() => _payments.doc(_childId(unitCloudId, year, month)).delete());
  }

  void upsertCharge(Charge c, String unitCloudId) {
    _fire(() => _charges
        .doc(_childId(unitCloudId, c.year, c.month))
        .set(_chargeToMap(c, unitCloudId)));
  }

  void deleteCharge(String unitCloudId, int year, int month) {
    _fire(() => _charges.doc(_childId(unitCloudId, year, month)).delete());
  }

  /// Sequenced erase-then-write for demo-data/import: clears the cloud copy,
  /// THEN writes the new dataset, so the erase can't race ahead and delete the
  /// freshly-written docs.
  void replaceAllCloud({
    required List<Unit> units,
    required List<Payment> payments,
    required List<Charge> charges,
    required Map<int, String> cloudIdByUnitId,
  }) {
    _fire(() async {
      await _eraseAll();
      await _commitChunked(_bulkOps(units, payments, charges, cloudIdByUnitId));
    });
  }

  /// Delete every unit/payment/charge doc for this owner (mirrors eraseAll).
  void eraseAllCloud() => _fire(_eraseAll);

  // ---- Owner settings (root user doc, alongside the ledger subcollections) --

  /// Mirrors the owner's calendar mode ('bs'/'ad') and annual escalation rate so
  /// they follow the login to other devices. The PIN stays device-local.
  void pushSettings(String calendarMode, double rate) {
    _fire(() => _root.set(
          {
            'calendarMode': calendarMode,
            'annualRaisePercent': rate,
            'settingsUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ));
  }

  /// One-shot read of the owner settings doc (null if never written).
  Future<Map<String, dynamic>?> fetchSettings() async {
    final snap = await _root.get();
    return snap.data();
  }

  List<_Op> _bulkOps(List<Unit> units, List<Payment> payments,
      List<Charge> charges, Map<int, String> cloudIdByUnitId) {
    return [
      for (final u in units)
        if (u.cloudId != null) _Op.set(_units.doc(u.cloudId), _unitToMap(u)),
      for (final p in payments)
        if (cloudIdByUnitId[p.unitId] != null)
          _Op.set(
              _payments.doc(_childId(cloudIdByUnitId[p.unitId]!, p.year, p.month)),
              _paymentToMap(p, cloudIdByUnitId[p.unitId]!)),
      for (final c in charges)
        if (cloudIdByUnitId[c.unitId] != null)
          _Op.set(
              _charges.doc(_childId(cloudIdByUnitId[c.unitId]!, c.year, c.month)),
              _chargeToMap(c, cloudIdByUnitId[c.unitId]!)),
    ];
  }

  Future<void> _eraseAll() async {
    for (final col in [_units, _payments, _charges]) {
      final snap = await col.get();
      await _commitChunked(
          snap.docs.map((d) => _Op.delete(d.reference)).toList());
    }
  }

  // =========================================================================
  // Reconcile (one-shot at sign-in) — see plan's Case A / Case B rules.
  // =========================================================================

  Future<void> reconcile() async {
    status?.setSyncing();
    try {
      await _reconcile();
      // Pending pushes queued by _reconcile (first-sync uploads) settle via
      // _fire; if none were queued, mark synced now.
      if (_pending == 0) status?.setSynced();
    } catch (e) {
      debugPrint('Sync: reconcile failed: $e');
      status?.setError('$e');
    }
  }

  Future<void> _reconcile() async {
    final owner = prefs.getString(_kOwnerUid);
    if (owner != null && owner != uid) {
      // A different owner signed in on this device. The local ledger is the
      // previous owner's — never push it into this uid's cloud (data-bleed
      // guard). Treat as a fresh device: wipe local, pull this owner's cloud.
      debugPrint('Sync: owner changed ($owner → $uid); wiping local cache.');
      await repo.eraseAllLocal();
      await _pullAll();
      await prefs.setString(_kOwnerUid, uid);
      await prefs.setBool('$_kSyncedOnce::$uid', true);
      return;
    }

    final syncedOnce = prefs.getBool('$_kSyncedOnce::$uid') ?? false;
    final cloudUnitIds = await _pullAll(); // pull cloud → drift first

    // Local rows absent from cloud: push them (first sync) or delete them
    // (already synced once → they were removed on another device).
    final localUnits = await repo.allUnits();
    final localPayments = await repo.allPayments();
    final localCharges = await repo.allCharges();
    final cloudIdByUnitId = {
      for (final u in localUnits)
        if (u.cloudId != null) u.id: u.cloudId!,
    };

    final cloudPayIds = (await _payments.get()).docs.map((d) => d.id).toSet();
    final cloudChargeIds = (await _charges.get()).docs.map((d) => d.id).toSet();

    for (final u in localUnits) {
      final cid = u.cloudId;
      if (cid == null) continue;
      if (cloudUnitIds.contains(cid)) continue;
      if (syncedOnce) {
        await repo.deleteLocalUnitByCloudId(cid); // deleted elsewhere
      } else {
        upsertUnit(u); // first sync: push local-only up
      }
    }
    for (final p in localPayments) {
      final cid = cloudIdByUnitId[p.unitId];
      if (cid == null) continue;
      final id = _childId(cid, p.year, p.month);
      if (cloudPayIds.contains(id)) continue;
      if (syncedOnce) {
        await repo.deleteLocalPayment(p.unitId, p.year, p.month);
      } else {
        upsertPayment(p, cid);
      }
    }
    for (final c in localCharges) {
      final cid = cloudIdByUnitId[c.unitId];
      if (cid == null) continue;
      final id = _childId(cid, c.year, c.month);
      if (cloudChargeIds.contains(id)) continue;
      if (syncedOnce) {
        await repo.deleteLocalCharge(c.unitId, c.year, c.month);
      } else {
        upsertCharge(c, cid);
      }
    }

    await prefs.setString(_kOwnerUid, uid);
    await prefs.setBool('$_kSyncedOnce::$uid', true);
  }

  /// Pulls all cloud docs into drift (units before children so FK lookups
  /// resolve). Returns the set of cloud unit ids seen.
  Future<Set<String>> _pullAll() async {
    final unitDocs = await _units.get();
    for (final d in unitDocs.docs) {
      await repo.applyRemoteUnit(_unitFromDoc(d.id, d.data()));
    }
    final payDocs = await _payments.get();
    for (final d in payDocs.docs) {
      await _applyPaymentDoc(d.data());
    }
    final chargeDocs = await _charges.get();
    for (final d in chargeDocs.docs) {
      await _applyChargeDoc(d.data());
    }
    return unitDocs.docs.map((d) => d.id).toSet();
  }

  // =========================================================================
  // Listen (steady state) — apply remote changes into drift, never push.
  // =========================================================================

  void attachListeners(VoidCallback onApply) {
    _onApply = onApply;
    _subs.add(_units.snapshots().listen((s) => _onUnitsSnapshot(s)));
    _subs.add(_payments.snapshots().listen((s) => _onChildSnapshot(s, isPayment: true)));
    _subs.add(_charges.snapshots().listen((s) => _onChildSnapshot(s, isPayment: false)));
    _subs.add(_root.snapshots().listen(_onRootSnapshot));
  }

  /// Owner settings doc changed elsewhere — apply calendar mode + rate locally.
  void _onRootSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (snap.metadata.hasPendingWrites) return; // our own echo
    final d = snap.data();
    if (d == null) return;
    onRemoteSettings?.call(
      d['calendarMode'] as String?,
      d['annualRaisePercent'] as num?,
    );
  }

  Future<void> _onUnitsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    for (final change in snap.docChanges) {
      if (change.doc.metadata.hasPendingWrites) continue; // our own echo
      final cloudId = change.doc.id;
      if (change.type == DocumentChangeType.removed) {
        await repo.deleteLocalUnitByCloudId(cloudId);
      } else {
        await repo.applyRemoteUnit(_unitFromDoc(cloudId, change.doc.data()!));
        await _drain(cloudId); // children that arrived early can now resolve
      }
    }
    _scheduleRefresh();
  }

  Future<void> _onChildSnapshot(QuerySnapshot<Map<String, dynamic>> snap,
      {required bool isPayment}) async {
    for (final change in snap.docChanges) {
      if (change.doc.metadata.hasPendingWrites) continue;
      final data = change.doc.data()!;
      final unitCloudId = data['unitCloudId'] as String?;
      final year = (data['year'] as num?)?.toInt();
      final month = (data['month'] as num?)?.toInt();
      if (unitCloudId == null || year == null || month == null) continue;

      if (change.type == DocumentChangeType.removed) {
        final unitId = await repo.localUnitIdForCloudId(unitCloudId);
        if (unitId == null) continue;
        if (isPayment) {
          await repo.deleteLocalPayment(unitId, year, month);
        } else {
          await repo.deleteLocalCharge(unitId, year, month);
        }
      } else {
        final applied =
            isPayment ? await _applyPaymentDoc(data) : await _applyChargeDoc(data);
        if (!applied) {
          // Unit not local yet — buffer until its unit doc arrives.
          (_pendingChildren[unitCloudId] ??= []).add(_PendingChild(isPayment, data));
        }
      }
    }
    _scheduleRefresh();
  }

  /// Applies any buffered children for [unitCloudId] now that its unit exists.
  Future<void> _drain(String unitCloudId) async {
    final pending = _pendingChildren.remove(unitCloudId);
    if (pending == null) return;
    for (final c in pending) {
      if (c.isPayment) {
        await _applyPaymentDoc(c.data);
      } else {
        await _applyChargeDoc(c.data);
      }
    }
  }

  /// Returns false when the referenced unit isn't local yet (caller buffers).
  Future<bool> _applyPaymentDoc(Map<String, dynamic> data) async {
    final unitId = await repo.localUnitIdForCloudId(data['unitCloudId'] as String);
    if (unitId == null) return false;
    await repo.applyRemotePayment(PaymentsCompanion.insert(
      unitId: unitId,
      year: (data['year'] as num).toInt(),
      month: (data['month'] as num).toInt(),
      amount: (data['amount'] as num).toInt(),
      paidOn: Value(_toDate(data['paidOn'])),
      method: Value(_method(data['method'] as String?)),
      note: Value(data['note'] as String?),
    ));
    return true;
  }

  Future<bool> _applyChargeDoc(Map<String, dynamic> data) async {
    final unitId = await repo.localUnitIdForCloudId(data['unitCloudId'] as String);
    if (unitId == null) return false;
    await repo.applyRemoteCharge(ChargesCompanion.insert(
      unitId: unitId,
      year: (data['year'] as num).toInt(),
      month: (data['month'] as num).toInt(),
      electricity: Value((data['electricity'] as num?)?.toInt() ?? 0),
      water: Value((data['water'] as num?)?.toInt() ?? 0),
      service: Value((data['service'] as num?)?.toInt() ?? 0),
    ));
    return true;
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce =
        Timer(const Duration(milliseconds: 250), () => _onApply?.call());
  }

  Future<void> detach() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _refreshDebounce?.cancel();
    _pendingChildren.clear();
    _onApply = null;
  }

  // =========================================================================
  // Serialization
  // =========================================================================

  Map<String, dynamic> _unitToMap(Unit u) => {
        'cloudId': u.cloudId,
        'code': u.code,
        'tenantName': u.tenantName,
        'businessType': u.businessType,
        'monthlyRent': u.monthlyRent,
        'phone': u.phone,
        'notes': u.notes,
        'isActive': u.isActive,
        'createdAt': Timestamp.fromDate(u.createdAt),
        'startedOn': _ts(u.startedOn),
        'lastRaisedOn': _ts(u.lastRaisedOn),
        'depositAmount': u.depositAmount,
        'depositRefunded': u.depositRefunded,
        'depositRefundedOn': _ts(u.depositRefundedOn),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  UnitsCompanion _unitFromDoc(String cloudId, Map<String, dynamic> d) =>
      UnitsCompanion.insert(
        cloudId: Value(cloudId),
        code: d['code'] as String,
        tenantName: d['tenantName'] as String? ?? '',
        monthlyRent: (d['monthlyRent'] as num?)?.toInt() ?? 0,
        businessType: Value(d['businessType'] as String? ?? ''),
        phone: Value(d['phone'] as String?),
        notes: Value(d['notes'] as String?),
        isActive: Value(d['isActive'] as bool? ?? true),
        createdAt: Value(_toDate(d['createdAt']) ?? DateTime.now()),
        startedOn: Value(_toDate(d['startedOn'])),
        lastRaisedOn: Value(_toDate(d['lastRaisedOn'])),
        depositAmount: Value((d['depositAmount'] as num?)?.toInt() ?? 0),
        depositRefunded: Value(d['depositRefunded'] as bool? ?? false),
        depositRefundedOn: Value(_toDate(d['depositRefundedOn'])),
      );

  Map<String, dynamic> _paymentToMap(Payment p, String unitCloudId) => {
        'unitCloudId': unitCloudId,
        'year': p.year,
        'month': p.month,
        'amount': p.amount,
        'paidOn': _ts(p.paidOn),
        'method': p.method.name,
        'note': p.note,
        'createdAt': Timestamp.fromDate(p.createdAt),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> _chargeToMap(Charge c, String unitCloudId) => {
        'unitCloudId': unitCloudId,
        'year': c.year,
        'month': c.month,
        'electricity': c.electricity,
        'water': c.water,
        'service': c.service,
        'createdAt': Timestamp.fromDate(c.createdAt),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Timestamp? _ts(DateTime? d) => d == null ? null : Timestamp.fromDate(d);
  static DateTime? _toDate(Object? v) =>
      v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
  static PayMethod _method(String? s) {
    for (final m in PayMethod.values) {
      if (m.name == s) return m;
    }
    return PayMethod.cash;
  }

  // =========================================================================
  // Plumbing
  // =========================================================================

  /// Runs a push best-effort: never awaited by callers, errors only logged, so
  /// a Firestore hiccup can't break a local drift write. Drives the UI sync
  /// indicator: `syncing` while any push is in flight, then `synced` once the
  /// last one acks, or `error` if it fails (e.g. offline).
  void _fire(Future<void> Function() op) {
    _pending++;
    status?.setSyncing();
    op().then((_) {
      _pending = _pending > 0 ? _pending - 1 : 0;
      if (_pending == 0) status?.setSynced();
    }).catchError((Object e, StackTrace st) {
      _pending = _pending > 0 ? _pending - 1 : 0;
      debugPrint('Sync push failed: $e');
      status?.setError('$e');
    });
  }

  /// Commits ops in ≤[_maxBatch] chunks (Firestore caps batches at 500).
  Future<void> _commitChunked(List<_Op> ops) async {
    for (var i = 0; i < ops.length; i += _maxBatch) {
      final batch = _fs.batch();
      for (final op in ops.skip(i).take(_maxBatch)) {
        if (op.data == null) {
          batch.delete(op.ref);
        } else {
          batch.set(op.ref, op.data!);
        }
      }
      await batch.commit();
    }
  }
}

/// A buffered payment/charge doc awaiting its unit (see [_pendingChildren]).
class _PendingChild {
  final bool isPayment;
  final Map<String, dynamic> data;
  _PendingChild(this.isPayment, this.data);
}

/// A pending batch operation: [data] == null means delete, else set.
class _Op {
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic>? data;
  _Op.set(this.ref, Map<String, dynamic> this.data);
  _Op.delete(this.ref) : data = null;
}
