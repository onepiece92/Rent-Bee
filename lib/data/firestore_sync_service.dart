import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/sync_status.dart';
import 'database.dart';
import 'ledger_repository.dart';
import 'sync_types.dart';

/// Live mirror of the local drift ledger into Cloud Firestore, scoped per owner
/// at `users/{uid}/`. Drift stays the source of truth for the UI; this service
/// (a) **pushes** every local change up and (b) **applies** remote changes
/// back down into drift through [LedgerRepository.applyRemote].
///
/// **Nothing done on this device is lost to sync.** Every local change is
/// recorded in a local outbox (`PendingPushes`) before its push is fired, and
/// cleared only when the cloud acknowledges it. At sync start the outbox is
/// pushed first, and no pull or listener ever overwrites or deletes a row
/// whose key is still pending. A push sends the *current* local row for a
/// key, so pushes are idempotent and safe to repeat.
///
/// **Echo loops are impossible by construction**: the apply path never pushes,
/// listeners skip this device's own un-acked writes
/// (`metadata.hasPendingWrites`), and applying a row that already matches is
/// a no-op that doesn't even refresh the UI. Identity is the unit's stable
/// [Unit.cloudId] (a UUID), since the local int `id` differs per device and
/// `code` is editable.
///
/// Firestore's own offline queue provides durability for a push that was
/// fired while offline; the outbox covers everything it can't see — changes
/// made while this service wasn't attached at all.
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
  void Function(String? calendarMode, num? rate, String? currency)?
      onRemoteSettings;

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
  bool _detached = false;

  // Listener snapshots are applied strictly one after another. Each handler is
  // async (it awaits the database), and two of them interleaving could apply
  // a stale change after a newer one.
  Future<void> _serial = Future<void>.value();

  // Child docs (payments/charges) that arrived before their unit — buffered by
  // unit cloudId and applied once the unit lands locally (see [_drain]).
  final Map<String, List<RemotePayment>> _waitingPayments = {};
  final Map<String, List<RemoteCharge>> _waitingCharges = {};

  // Coalesce the flurry of refresh()es a multi-doc snapshot would otherwise
  // trigger into a single trailing UI refresh.
  Timer? _refreshDebounce;
  VoidCallback? _onApply;

  // =========================================================================
  // Push — called by the repository after each local change (fire-and-forget)
  // =========================================================================

  /// Pushes the current local state of [keys] and, once the cloud acknowledges
  /// it, clears their outbox rows (those no newer than [seq]).
  void push(List<SyncKey> keys, int seq) {
    if (_detached || keys.isEmpty) return;
    _fire(() => _push(keys, seq));
  }

  Future<void> _push(List<SyncKey> keys, int seq) async {
    if (keys.any((k) => k.isAll)) {
      await _replaceAll();
      await repo.clearAllPending(seq);
      return;
    }
    final ops = <_Op>[];
    for (final k in keys) {
      ops.addAll(await _opsFor(k));
    }
    await _commitChunked(ops);
    await repo.clearPending(keys, seq);
  }

  /// The write(s) that bring the cloud in line with the local state of [k]:
  /// a `set` if the row exists locally, a `delete` if it doesn't.
  Future<List<_Op>> _opsFor(SyncKey k) async {
    switch (k.kind) {
      case SyncKey.kUnit:
        final u = await repo.unitByCloudId(k.cloudId);
        if (u != null) return [_Op.set(_units.doc(k.cloudId), _unitToMap(u))];
        // Gone locally. Firestore has no cascade — delete its children too.
        final ops = <_Op>[_Op.delete(_units.doc(k.cloudId))];
        for (final col in [_payments, _charges]) {
          final kids =
              await col.where('unitCloudId', isEqualTo: k.cloudId).get();
          ops.addAll(kids.docs.map((d) => _Op.delete(d.reference)));
        }
        return ops;
      case SyncKey.kPayment:
        final ref = _payments.doc(_childId(k.cloudId, k.year, k.month));
        final p = await repo.paymentByKey(k);
        return [
          p != null ? _Op.set(ref, _paymentToMap(p, k.cloudId)) : _Op.delete(ref)
        ];
      case SyncKey.kCharge:
        final ref = _charges.doc(_childId(k.cloudId, k.year, k.month));
        final c = await repo.chargeByKey(k);
        // Merge rather than replace, so a build that doesn't know a newer
        // field can't strip it from the doc when it saves the ones it knows.
        return [
          c != null
              ? _Op.set(ref, _chargeToMap(c, k.cloudId), merge: true)
              : _Op.delete(ref)
        ];
    }
    return const [];
  }

  /// Makes the cloud copy equal to this device's ledger: writes every local
  /// row, then deletes the cloud documents that have no local counterpart.
  ///
  /// Deliberately **not** erase-then-write. Deleting first made this device's
  /// own listeners see its units "removed" and wipe the local ledger — and if
  /// the rewrite then failed or the app was offline, the data was simply gone
  /// (buglog B04). Here the only documents deleted are ones that already don't
  /// exist locally, so their echo has nothing to remove.
  Future<void> _replaceAll() async {
    final units = await repo.allUnits();
    final payments = await repo.allPayments();
    final charges = await repo.allCharges();
    final cloudIdByUnitId = {
      for (final u in units)
        if (u.cloudId != null) u.id: u.cloudId!,
    };
    final ops = <_Op>[
      for (final u in units)
        if (u.cloudId != null) _Op.set(_units.doc(u.cloudId), _unitToMap(u)),
      for (final p in payments)
        if (cloudIdByUnitId[p.unitId] != null)
          _Op.set(
              _payments
                  .doc(_childId(cloudIdByUnitId[p.unitId]!, p.year, p.month)),
              _paymentToMap(p, cloudIdByUnitId[p.unitId]!)),
      for (final c in charges)
        if (cloudIdByUnitId[c.unitId] != null)
          _Op.set(
              _charges
                  .doc(_childId(cloudIdByUnitId[c.unitId]!, c.year, c.month)),
              _chargeToMap(c, cloudIdByUnitId[c.unitId]!)),
    ];
    final keep = {for (final op in ops) op.ref.path};
    final (u, p, c) =
        await (_units.get(), _payments.get(), _charges.get()).wait;
    for (final snap in [u, p, c]) {
      for (final d in snap.docs) {
        if (!keep.contains(d.reference.path)) ops.add(_Op.delete(d.reference));
      }
    }
    await _commitChunked(ops);
  }

  // ---- Owner settings (root user doc, alongside the ledger subcollections) --

  /// Mirrors the owner's calendar mode ('bs'/'ad'), currency ('npr'/'usd')
  /// and annual escalation rate so they follow the login to other devices.
  /// The PIN stays device-local.
  void pushSettings(String calendarMode, double rate, String currency) {
    if (_detached) return;
    _fire(() => _root.set(
          {
            'calendarMode': calendarMode,
            'currency': currency,
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

  // =========================================================================
  // Reconcile (one-shot at sync start)
  // =========================================================================

  Future<void> reconcile() async {
    status?.setSyncing();
    try {
      await _reconcile();
      // Pushes queued by _reconcile settle via _fire; if none were queued,
      // mark synced now.
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
      // guard). Treat as a fresh device: wipe local (and its outbox), pull
      // this owner's cloud.
      debugPrint('Sync: owner changed ($owner → $uid); wiping local cache.');
      await repo.eraseAllLocal();
      await _pull(deleteMissing: false);
      await prefs.setString(_kOwnerUid, uid);
      await prefs.setBool('$_kSyncedOnce::$uid', true);
      return;
    }

    final syncedOnce = prefs.getBool('$_kSyncedOnce::$uid') ?? false;

    // 1. The outbox goes up first: whatever was changed here and never
    //    acknowledged (a change made before sync finished starting, in a
    //    session where it couldn't start, or whose push failed). Fired, not
    //    awaited — offline, an acknowledgement never comes — and the pull
    //    below leaves every pending key alone either way.
    final pending = await repo.pendingPushes();
    if (pending.isNotEmpty) {
      push(
        [for (final p in pending) SyncKey.fromRow(p)],
        pending.map((p) => p.seq).reduce(math.max),
      );
    }

    // 2. Pull. After the first sync, a local row the cloud doesn't have was
    //    removed on another device; before it, the row exists only here and
    //    is pushed up.
    final fromServer = await _pull(deleteMissing: syncedOnce);

    await prefs.setString(_kOwnerUid, uid);
    // "Synced once" licenses deleting local rows the cloud lacks, so it is
    // only earned by a pull that really saw the server's state.
    if (fromServer) await prefs.setBool('$_kSyncedOnce::$uid', true);
  }

  /// Reads each collection once (in parallel) and applies the differences in a
  /// single local transaction. Returns whether the data came from the server.
  ///
  /// A cache-only read (offline) is applied as updates only: it is not proof
  /// of what the cloud holds, so nothing is deleted and nothing is taken to be
  /// "only on this device".
  Future<bool> _pull({required bool deleteMissing}) async {
    final (u, p, c) =
        await (_units.get(), _payments.get(), _charges.get()).wait;
    final fromServer = !(u.metadata.isFromCache ||
        p.metadata.isFromCache ||
        c.metadata.isFromCache);
    final res = await repo.applyRemote(
      units: [
        for (final d in u.docs)
          ?_unitFrom(d.id, d.data()),
      ],
      payments: [
        for (final d in p.docs)
          ?_paymentFrom(d.id, d.data()),
      ],
      charges: [
        for (final d in c.docs)
          ?_chargeFrom(d.id, d.data()),
      ],
      fullSnapshot: fromServer,
      deleteMissing: deleteMissing && fromServer,
    );
    if (res.toPush.isNotEmpty) await repo.queueKeys(res.toPush);
    return fromServer;
  }

  // =========================================================================
  // Listen (steady state) — apply remote changes into drift, never push.
  // =========================================================================

  void attachListeners(VoidCallback onApply) {
    if (_detached) return; // signed out while sync was still starting
    _onApply = onApply;
    _subs.add(_units.snapshots().listen(
        (s) => _enqueue(() => _onUnitsSnapshot(s)),
        onError: _onStreamError));
    _subs.add(_payments.snapshots().listen(
        (s) => _enqueue(() => _onChildSnapshot(s, isPayment: true)),
        onError: _onStreamError));
    _subs.add(_charges.snapshots().listen(
        (s) => _enqueue(() => _onChildSnapshot(s, isPayment: false)),
        onError: _onStreamError));
    _subs.add(_root.snapshots().listen(_onRootSnapshot, onError: _onStreamError));
  }

  /// Runs [job] after every earlier listener job has finished; a failure is
  /// reported and does not stop the ones behind it.
  void _enqueue(Future<void> Function() job) {
    _serial = _serial.then((_) async {
      if (_detached) return;
      try {
        await job();
      } catch (e) {
        debugPrint('Sync: applying a remote change failed: $e');
        status?.setError('$e');
      }
    });
  }

  /// A listener died (permission denied, account signed out elsewhere, …).
  /// Without this the stream would end silently with the badge still saying
  /// "synced".
  void _onStreamError(Object e) {
    debugPrint('Sync: listener error: $e');
    status?.setError('$e');
  }

  /// Owner settings doc changed elsewhere — apply calendar mode + rate locally.
  void _onRootSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (snap.metadata.hasPendingWrites) return; // our own echo
    final d = snap.data();
    if (d == null) return;
    onRemoteSettings?.call(
      d['calendarMode'] as String?,
      d['annualRaisePercent'] as num?,
      d['currency'] as String?,
    );
  }

  Future<void> _onUnitsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    final upserts = <RemoteUnit>[];
    final removed = <String>[];
    for (final change in snap.docChanges) {
      if (change.doc.metadata.hasPendingWrites) continue; // our own echo
      if (change.type == DocumentChangeType.removed) {
        removed.add(change.doc.id);
      } else if (_unitFrom(change.doc.id, change.doc.data()) case final r?) {
        upserts.add(r);
      }
    }
    if (upserts.isEmpty && removed.isEmpty) return;
    final res = await repo.applyRemote(units: upserts, removedUnits: removed);
    if (res.toPush.isNotEmpty) await repo.queueKeys(res.toPush);
    // Children that arrived before these units can now resolve.
    final drained = await _drain(upserts.map((u) => u.cloudId));
    // Refresh the UI only when something on screen could have changed — our
    // own acknowledged writes come back identical and change nothing.
    if (res.changed || drained) _scheduleRefresh();
  }

  Future<void> _onChildSnapshot(QuerySnapshot<Map<String, dynamic>> snap,
      {required bool isPayment}) async {
    final payments = <RemotePayment>[];
    final charges = <RemoteCharge>[];
    final removed = <SyncKey>[];
    for (final change in snap.docChanges) {
      if (change.doc.metadata.hasPendingWrites) continue;
      final data = change.doc.data();
      if (change.type == DocumentChangeType.removed) {
        final unitCloudId = data?['unitCloudId'];
        final year = data?['year'];
        final month = data?['month'];
        if (unitCloudId is! String || year is! num || month is! num) continue;
        removed.add(isPayment
            ? SyncKey.payment(unitCloudId, year.toInt(), month.toInt())
            : SyncKey.charge(unitCloudId, year.toInt(), month.toInt()));
      } else if (isPayment) {
        if (_paymentFrom(change.doc.id, data) case final r?) payments.add(r);
      } else {
        if (_chargeFrom(change.doc.id, data) case final r?) charges.add(r);
      }
    }
    if (payments.isEmpty && charges.isEmpty && removed.isEmpty) return;
    final res = await repo.applyRemote(
        payments: payments, charges: charges, removedChildren: removed);
    // Unit not local yet — hold these until its unit doc arrives.
    for (final r in res.orphanPayments) {
      (_waitingPayments[r.unitCloudId] ??= []).add(r);
    }
    for (final r in res.orphanCharges) {
      (_waitingCharges[r.unitCloudId] ??= []).add(r);
    }
    if (res.changed) _scheduleRefresh();
  }

  /// Applies any buffered children for [unitCloudIds] now that the units
  /// exist. Returns whether anything changed locally.
  Future<bool> _drain(Iterable<String> unitCloudIds) async {
    final payments = <RemotePayment>[];
    final charges = <RemoteCharge>[];
    for (final id in unitCloudIds) {
      payments.addAll(_waitingPayments.remove(id) ?? const []);
      charges.addAll(_waitingCharges.remove(id) ?? const []);
    }
    if (payments.isEmpty && charges.isEmpty) return false;
    final res = await repo.applyRemote(payments: payments, charges: charges);
    return res.changed;
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce =
        Timer(const Duration(milliseconds: 250), () => _onApply?.call());
  }

  Future<void> detach() async {
    _detached = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _refreshDebounce?.cancel();
    _waitingPayments.clear();
    _waitingCharges.clear();
    _onApply = null;
  }

  // =========================================================================
  // Serialization
  // =========================================================================
  //
  // Parsing is defensive: a single malformed document (a hand-edited doc, a
  // field of the wrong type) is skipped and logged, never thrown — one bad
  // doc used to abort the whole pull, on every launch.

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

  RemoteUnit? _unitFrom(String cloudId, Map<String, dynamic>? d) {
    try {
      if (d == null) return null;
      final code = (d['code'] as String).trim();
      if (code.isEmpty || code.length > 32) {
        throw FormatException('unit code "$code" is empty or too long');
      }
      var tenant = (d['tenantName'] as String? ?? '').trim();
      if (tenant.isEmpty) tenant = '—'; // the column requires a name
      if (tenant.length > 120) tenant = tenant.substring(0, 120);
      return RemoteUnit(
        cloudId: cloudId,
        code: code,
        tenantName: tenant,
        businessType: d['businessType'] as String? ?? '',
        monthlyRent: (d['monthlyRent'] as num?)?.toInt() ?? 0,
        phone: d['phone'] as String?,
        notes: d['notes'] as String?,
        isActive: d['isActive'] as bool? ?? true,
        createdAt: _toDate(d['createdAt']) ?? DateTime.now(),
        startedOn: _toDate(d['startedOn']),
        lastRaisedOn: _toDate(d['lastRaisedOn']),
        depositAmount: (d['depositAmount'] as num?)?.toInt() ?? 0,
        depositRefunded: d['depositRefunded'] as bool? ?? false,
        depositRefundedOn: _toDate(d['depositRefundedOn']),
      );
    } catch (e) {
      debugPrint('Sync: skipping malformed unit doc $cloudId: $e');
      return null;
    }
  }

  Map<String, dynamic> _paymentToMap(Payment p, String unitCloudId) => {
        'unitCloudId': unitCloudId,
        'year': p.year,
        'month': p.month,
        'amount': p.amount,
        'paidOn': _ts(p.paidOn),
        'method': p.method.name,
        'note': p.note,
        'rentAtPayment': p.rentAtPayment,
        'createdAt': Timestamp.fromDate(p.createdAt),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  RemotePayment? _paymentFrom(String docId, Map<String, dynamic>? d) {
    try {
      if (d == null) return null;
      return RemotePayment(
        unitCloudId: d['unitCloudId'] as String,
        year: (d['year'] as num).toInt(),
        month: (d['month'] as num).toInt(),
        amount: (d['amount'] as num).toInt(),
        paidOn: _toDate(d['paidOn']),
        method: _method(d['method'] as String?),
        note: d['note'] as String?,
        hasRent: d.containsKey('rentAtPayment'),
        rentAtPayment: (d['rentAtPayment'] as num?)?.toInt(),
      );
    } catch (e) {
      debugPrint('Sync: skipping malformed payment doc $docId: $e');
      return null;
    }
  }

  Map<String, dynamic> _chargeToMap(Charge c, String unitCloudId) => {
        'unitCloudId': unitCloudId,
        'year': c.year,
        'month': c.month,
        'electricity': c.electricity,
        'water': c.water,
        'service': c.service,
        'deduction': c.deduction,
        'deductionNote': c.deductionNote,
        'createdAt': Timestamp.fromDate(c.createdAt),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  RemoteCharge? _chargeFrom(String docId, Map<String, dynamic>? d) {
    try {
      if (d == null) return null;
      // A doc saved by a build that predates the deduction has no such keys:
      // "absent" must leave this device's value alone, not zero it.
      final hasDeduction = d.containsKey('deduction');
      final hasNote = d.containsKey('deductionNote');
      return RemoteCharge(
        unitCloudId: d['unitCloudId'] as String,
        year: (d['year'] as num).toInt(),
        month: (d['month'] as num).toInt(),
        electricity: (d['electricity'] as num?)?.toInt() ?? 0,
        water: (d['water'] as num?)?.toInt() ?? 0,
        service: (d['service'] as num?)?.toInt() ?? 0,
        hasDeduction: hasDeduction,
        deduction: (d['deduction'] as num?)?.toInt() ?? 0,
        hasDeductionNote: hasNote,
        deductionNote: d['deductionNote'] as String?,
      );
    } catch (e) {
      debugPrint('Sync: skipping malformed charge doc $docId: $e');
      return null;
    }
  }

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
  /// last one acks, or `error` if it fails. A failed push leaves its keys in
  /// the outbox, so it is retried at the next sync start.
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
        final data = op.data;
        if (data == null) {
          batch.delete(op.ref);
        } else if (op.merge) {
          batch.set(op.ref, data, SetOptions(merge: true));
        } else {
          batch.set(op.ref, data);
        }
      }
      await batch.commit();
    }
  }
}

/// A pending batch operation: [data] == null means delete, else set (merged
/// into the existing doc when [merge]).
class _Op {
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic>? data;
  final bool merge;
  _Op.set(this.ref, Map<String, dynamic> this.data, {this.merge = false});
  _Op.delete(this.ref)
      : data = null,
        merge = false;
}
