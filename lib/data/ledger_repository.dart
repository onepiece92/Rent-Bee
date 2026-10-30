import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/bs_calendar.dart';
import '../domain/models.dart';
import 'database.dart';
import 'firestore_sync_service.dart';
import 'sync_types.dart';

/// All persistence + business logic (§4) lives here, on top of Drift.
///
/// Cloud sync is a write-through mirror: each mutation writes drift (the UI's
/// source of truth) then fires the matching [sync] push. The `applyRemote*` /
/// `*Local` methods are the drift-only counterparts the sync listener calls —
/// they never push, which is what makes echo loops impossible.
class LedgerRepository {
  final AppDatabase db;
  LedgerRepository(this.db);

  static final _uuid = Uuid();

  /// Live cloud mirror, set after sign-in (null for guest sessions and tests,
  /// where the repository behaves exactly as a local-only store).
  FirestoreSyncService? sync;

  // ---- Units ----------------------------------------------------------

  Future<List<Unit>> allUnits() => db.select(db.units).get();
  Future<List<Payment>> allPayments() => db.select(db.payments).get();
  Future<List<Charge>> allCharges() => db.select(db.charges).get();

  Future<String?> cloudIdForUnitId(int unitId) async {
    final u = await (db.select(db.units)..where((t) => t.id.equals(unitId)))
        .getSingleOrNull();
    return u?.cloudId;
  }

  Future<int?> localUnitIdForCloudId(String cloudId) async {
    final u = await (db.select(db.units)..where((t) => t.cloudId.equals(cloudId)))
        .getSingleOrNull();
    return u?.id;
  }

  /// Drift-only unit insert that stamps a stable cloudId. Used by [createUnit]
  /// (which then pushes) and by bulk builders like demo data (one cloud push
  /// at the end instead of one per unit).
  Future<int> _insertUnitLocal(UnitsCompanion entry) {
    // Stamp a stable cloudId at creation so the unit syncs with a key that
    // survives `code` edits and differs from the per-device int id.
    final withCloud =
        entry.cloudId.present ? entry : entry.copyWith(cloudId: Value(_uuid.v4()));
    return db.into(db.units).insert(withCloud);
  }

  Future<int> createUnit(UnitsCompanion entry) async {
    final id = await _insertUnitLocal(entry);
    final unit =
        await (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();
    await _queueUnit(unit.cloudId);
    return id;
  }

  Future<void> updateUnit(Unit unit) async {
    await db.update(db.units).replace(unit);
    await _queueUnit(unit.cloudId);
  }

  /// Deleting a unit cascades its payment history.
  Future<void> deleteUnit(int id) async {
    final unit = await (db.select(db.units)..where((u) => u.id.equals(id)))
        .getSingleOrNull();
    await (db.delete(db.units)..where((s) => s.id.equals(id))).go();
    await _queueUnit(unit?.cloudId);
  }

  // ---- Outbox (see [PendingPushes]) --------------------------------------
  //
  // Every local change goes through [_queue]: it records the changed keys in
  // the outbox and hands them to the cloud mirror, if one is attached. The
  // mirror pushes the *current* local row for each key and clears the outbox
  // row once the cloud acknowledges it. Until then the key is "pending", and
  // a pull never overwrites or deletes a pending row (see [applyRemote]).

  int _lastSeq = 0;

  /// A strictly increasing sequence number for outbox rows.
  int _nextSeq() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return _lastSeq = now > _lastSeq ? now : _lastSeq + 1;
  }

  Future<void> _queue(List<SyncKey> keys) async {
    if (keys.isEmpty) return;
    final held = Zone.current[_heldKeys];
    if (held is Set<SyncKey>) {
      held.addAll(keys); // inside [_atomically]: recorded once, at commit
      return;
    }
    final seq = _nextSeq();
    await _record(keys, seq);
    sync?.push(keys, seq);
  }

  Future<void> _record(Iterable<SyncKey> keys, int seq) async {
    await db.batch((b) {
      for (final k in keys) {
        b.insert(
          db.pendingPushes,
          PendingPushesCompanion.insert(
            kind: k.kind,
            cloudId: k.cloudId,
            year: Value(k.year),
            month: Value(k.month),
            seq: seq,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  static final _heldKeys = Object();

  /// Runs a multi-row change as one unit: every write in [body] — through the
  /// ordinary mutators — lands in a single transaction together with its
  /// outbox rows, and the cloud is told only after the commit. If anything
  /// throws, nothing was written here and nothing was pushed.
  Future<T> _atomically<T>(Future<T> Function() body) async {
    final keys = <SyncKey>{};
    var seq = 0;
    final result = await runZoned(
      () => db.transaction(() async {
        final r = await body();
        if (keys.isNotEmpty) await _record(keys, seq = _nextSeq());
        return r;
      }),
      zoneValues: {_heldKeys: keys},
    );
    if (keys.isNotEmpty) sync?.push(keys.toList(), seq);
    return result;
  }

  Future<void> _queueUnit(String? cloudId) async {
    if (cloudId != null) await _queue([SyncKey.unit(cloudId)]);
  }

  Future<void> _queuePayment(int unitId, int year, int month,
      {String? cloudId}) async {
    final cid = cloudId ?? await cloudIdForUnitId(unitId);
    if (cid != null) await _queue([SyncKey.payment(cid, year, month)]);
  }

  Future<void> _queueCharge(int unitId, int year, int month) async {
    final cid = await cloudIdForUnitId(unitId);
    if (cid != null) await _queue([SyncKey.charge(cid, year, month)]);
  }

  /// Queues [keys] for a push — for the cloud mirror, which learns during a
  /// pull that some rows exist only on this device.
  Future<void> queueKeys(List<SyncKey> keys) => _queue(keys);

  /// Everything changed locally that the cloud has not acknowledged yet.
  Future<List<PendingPush>> pendingPushes() =>
      db.select(db.pendingPushes).get();

  /// Clears the outbox rows for [keys] once the cloud has acknowledged a push
  /// that started at [seq]. A key queued again since then carries a newer
  /// sequence number and stays pending.
  Future<void> clearPending(Iterable<SyncKey> keys, int seq) => db.batch((b) {
        for (final k in keys) {
          b.deleteWhere(
              db.pendingPushes,
              (t) =>
                  t.kind.equals(k.kind) &
                  t.cloudId.equals(k.cloudId) &
                  t.year.equals(k.year) &
                  t.month.equals(k.month) &
                  t.seq.isSmallerOrEqualValue(seq));
        }
      });

  /// After a whole-ledger replace is acknowledged: everything queued up to
  /// [seq] is covered by it.
  Future<void> clearAllPending(int seq) => (db.delete(db.pendingPushes)
        ..where((t) => t.seq.isSmallerOrEqualValue(seq)))
      .go();

  // ---- Current local state by sync key (what a push sends) ---------------

  Future<Unit?> unitByCloudId(String cloudId) =>
      (db.select(db.units)..where((t) => t.cloudId.equals(cloudId)))
          .getSingleOrNull();

  Future<Payment?> paymentByKey(SyncKey k) async {
    final unitId = await localUnitIdForCloudId(k.cloudId);
    if (unitId == null) return null;
    return (db.select(db.payments)
          ..where((p) =>
              p.unitId.equals(unitId) &
              p.year.equals(k.year) &
              p.month.equals(k.month)))
        .getSingleOrNull();
  }

  Future<Charge?> chargeByKey(SyncKey k) async {
    final unitId = await localUnitIdForCloudId(k.cloudId);
    if (unitId == null) return null;
    return chargesFor(unitId, k.year, k.month);
  }

  /// Applies the automatic annual lease escalation. Each **active** unit with a
  /// recorded `started_on` is raised by [percent]% on the **anniversary of its
  /// rent-start BS month** — the same month, one year on, every year.
  ///
  /// Runs as a catch-up at app start: a unit is raised once for every full
  /// anniversary that has passed since it started (or since its last raise),
  /// compounding [percent]% per year (rounded to whole NPR each year). So a
  /// unit started Jestha 2081 is raised in Jestha 2082, again in Jestha 2083,
  /// and so on — and if the app wasn't opened for two years, both land at once.
  /// Idempotent: re-running the same day changes nothing.
  ///
  /// No-op when [percent] <= 0, or for units that are inactive or have no start
  /// date. Recorded payments are captured per record (§4), so history is
  /// unaffected. Returns the number of units raised.
  Future<int> applyAnniversaryRaises({
    required double percent,
    DateTime? asOf,
  }) async {
    if (percent <= 0) return 0;
    final nowBs = bsYearMonth(asOf ?? DateTime.now());
    final units = await allUnits();

    final updated = <Unit>[];
    for (final u in units) {
      if (!u.isActive || u.startedOn == null) continue;
      final startBs = bsYearMonth(u.startedOn!);
      // The stamp is read tolerantly (see [bsMonthOfRaiseStamp]): it is an
      // instant that another device, in another time zone, may see a day off.
      final last = u.lastRaisedOn;
      final anchorBs = last != null ? bsMonthOfRaiseStamp(last) : startBs;

      // Latest BS year whose anniversary month (startBs.month) has arrived…
      final latestAnniversaryYear =
          nowBs.month >= startBs.month ? nowBs.year : nowBs.year - 1;
      // …and the anniversary year already covered by the anchor.
      final coveredThroughYear =
          anchorBs.month >= startBs.month ? anchorBs.year : anchorBs.year - 1;

      final dueYears = latestAnniversaryYear - coveredThroughYear;
      if (dueYears <= 0) continue;

      var rent = u.monthlyRent;
      for (var i = 0; i < dueYears; i++) {
        rent = ((rent * (100 + percent)) / 100).round();
      }
      // Stamp the latest applied anniversary: mid-month, so the stamp names
      // the same BS month on every device (buglog B01).
      final stamp = raiseStampFor(latestAnniversaryYear, startBs.month);
      updated.add(u.copyWith(monthlyRent: rent, lastRaisedOn: Value(stamp)));
    }

    if (updated.isNotEmpty) {
      await db.batch((b) {
        for (final u in updated) {
          b.replace(db.units, u);
        }
      });
      await _queue([
        for (final u in updated)
          if (u.cloudId != null) SyncKey.unit(u.cloudId!),
      ]);
    }
    return updated.length;
  }

  // ---- Payments ----------------------------------------------------------

  Future<List<Payment>> paymentsForMonth(int year, int month) {
    return (db.select(db.payments)
          ..where((p) => p.year.equals(year) & p.month.equals(month)))
        .get();
  }

  /// Payments for an inclusive BS month range within a single year
  /// (Baishakh=1 … Chaitra=12). Used by quarter/year reporting.
  Future<List<Payment>> paymentsForRange(
      int year, int startMonth, int endMonth) {
    return (db.select(db.payments)
          ..where((p) =>
              p.year.equals(year) &
              p.month.isBetweenValues(startMonth, endMonth)))
        .get();
  }

  /// Units joined with their payment (if any) for the month, sorted
  /// pending-first then paid (§4 "List sort").
  Future<List<UnitRow>> rowsForMonth(int year, int month,
      {double percent = 0}) async {
    final (units, payments, charges) = await _monthReads(year, month);
    return _rowsFrom(units, payments, charges, year, month, percent);
  }

  /// The rent that applies to a unit in BS ([year], [month]) — the one rule
  /// every screen prices a month by, so the Ledger, the unit sheet and Reports
  /// can't disagree (buglog B05):
  ///   1. the rent a recorded payment was made against, if there is one;
  ///   2. otherwise the rent in effect that month ([RentSchedule.rentFor]:
  ///      today's rent with later anniversary raises unwound; 0 before the
  ///      tenant moved in).
  static int _monthRent(
          RentSchedule schedule, Payment? payment, int year, int month) =>
      payment?.rentAtPayment ?? schedule.rentFor(year, month);

  /// The three independent reads behind a month view, issued together so the
  /// background DB isolate pipelines them into one round trip, not three.
  Future<(List<Unit>, List<Payment>, List<Charge>)> _monthReads(
          int year, int month) =>
      (allUnits(), paymentsForMonth(year, month), chargesForMonth(year, month))
          .wait;

  /// Build sorted [UnitRow]s from already-loaded units + that month's payments
  /// and charges rows (the latter carry each unit's utility charges and rent
  /// deduction, both of which feed the month's due).
  List<UnitRow> _rowsFrom(List<Unit> units, List<Payment> payments,
      List<Charge> charges, int year, int month, double percent) {
    final byUnit = {for (final p in payments) p.unitId: p};
    final deductionByUnit = _deductionByUnit(charges);
    final chargesByUnit = _chargesByUnit(charges);
    final rows = <UnitRow>[];
    for (final s in units) {
      final schedule = RentSchedule(s, percent);
      rows.add(UnitRow(
        unit: s,
        payment: byUnit[s.id],
        charges: chargesByUnit[s.id] ?? 0,
        deduction: deductionByUnit[s.id] ?? 0,
        rent: _monthRent(schedule, byUnit[s.id], year, month),
        started: schedule.startedBy(year, month),
      ));
    }
    rows.sort((a, b) {
      // active before vacant, so a moved-out unit never crowds the working
      // pending list; within active: pending (false) before paid (true)
      if (a.unit.isActive != b.unit.isActive) return a.unit.isActive ? -1 : 1;
      if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
      return a.unit.code.compareTo(b.unit.code);
    });
    return rows;
  }

  /// Rows **and** summary for a month from a single units+payments+charges
  /// load — used by the provider's refresh so a mark-paid/undo/edit re-queries
  /// the DB once (3 queries) instead of via rowsForMonth + summary (6 queries).
  ///
  /// [percent] is the active escalation rate, used to price a past month at
  /// the rent in effect then.
  Future<({List<UnitRow> rows, MonthSummary summary})> monthView(
      int year, int month,
      {double percent = 0}) async {
    final (units, payments, charges) = await _monthReads(year, month);
    return (
      rows: _rowsFrom(units, payments, charges, year, month, percent),
      summary: _summaryFrom(units, payments, charges, year, month, percent),
    );
  }

  /// True when [unit] had already started (or has no recorded start date) by
  /// BS ([year], [month]) — months before a tenant moved in expect no rent.
  static bool _startedBy(Unit unit, int year, int month) =>
      RentSchedule(unit, 0).startedBy(year, month);

  /// Mark paid: upsert a payment row. amount defaults to the month's due — the
  /// unit's current monthly_rent plus the month's utility charges, less any
  /// rent deduction (captured per record), paid_on = today, method = cash. A
  /// non-positive amount clears the month instead (see [undo]), matching the
  /// partial dialog's "blank = undo".
  Future<void> markPaid(
    Unit unit,
    int year,
    int month, {
    int? amount,
    DateTime? paidOn,
    PayMethod method = PayMethod.cash,
    String? note,
    int? rent,
  }) async {
    // [rent] is the rent that applies to this month — the row's `monthRent`,
    // which the app always passes. It is stored on the payment so the month
    // keeps being priced at what was actually charged. Without it nothing is
    // stored (the current rent would be a wrong guess for a past month) and
    // the month falls back to the rent reconstructed for it.
    final monthRent = rent ?? unit.monthlyRent;
    // "Settle in full" means what's actually owed this month, not the headline
    // rent: utility charges come on top, goods taken from the shop come off
    // (see netDue).
    final chargeRow = await chargesFor(unit.id, year, month);
    final due = amount ??
        netDue(monthRent, chargeRow?.deduction ?? 0,
            charges: chargeRow == null ? 0 : _chargesTotal(chargeRow));
    // Nothing to record — rent 0, fully deducted, or an explicit blank: clear
    // the month rather than store an empty payment row that would sync to
    // every device and still read as pending.
    if (due <= 0) {
      await undo(unit.id, year, month);
      return;
    }
    await _upsertPaymentLocal(PaymentsCompanion.insert(
      unitId: unit.id,
      year: year,
      month: month,
      amount: due,
      rentAtPayment: rent == null ? const Value.absent() : Value(rent),
      paidOn: Value(paidOn ?? DateTime.now()),
      method: Value(method),
      note: Value(note),
    ));
    await _queuePayment(unit.id, year, month, cloudId: unit.cloudId);
  }

  /// Insert-or-update a payment keyed by its `(unit, year, month)` unique index.
  /// Drift's [insertOnConflictUpdate] only targets the primary key (`id`), which
  /// we never supply here — so it would always INSERT and trip the unique index
  /// (SqliteException 2067). Naming the unique columns as the conflict target
  /// makes the upsert behave as documented. Drift-only — callers push.
  Future<void> _upsertPaymentLocal(PaymentsCompanion entry) =>
      db.into(db.payments).insert(
            entry,
            onConflict: DoUpdate(
              (_) => entry,
              target: [db.payments.unitId, db.payments.year, db.payments.month],
            ),
          );

  /// Update an existing payment record's editable fields.
  Future<void> updatePayment(Payment payment) async {
    await db.update(db.payments).replace(payment);
    await _queuePayment(payment.unitId, payment.year, payment.month);
  }

  /// Undo: delete the row for (unit_id, year, month).
  Future<void> undo(int unitId, int year, int month) async {
    final cloudId = await cloudIdForUnitId(unitId);
    await (db.delete(db.payments)
          ..where((p) =>
              p.unitId.equals(unitId) &
              p.year.equals(year) &
              p.month.equals(month)))
        .go();
    await _queuePayment(unitId, year, month, cloudId: cloudId);
  }

  // ---- Charges (variable per-month utility/service fees) -----------------

  /// This unit's charges row for the month, or null if nothing recorded.
  Future<Charge?> chargesFor(int unitId, int year, int month) {
    return (db.select(db.charges)
          ..where((c) =>
              c.unitId.equals(unitId) &
              c.year.equals(year) &
              c.month.equals(month)))
        .getSingleOrNull();
  }

  /// All charges rows for a BS month (any unit) — one query for a month view.
  Future<List<Charge>> chargesForMonth(int year, int month) {
    return (db.select(db.charges)
          ..where((c) => c.year.equals(year) & c.month.equals(month)))
        .get();
  }

  /// Charges rows for an inclusive BS month range within a single year. Used
  /// by quarter/year reporting to price each month net of its deduction.
  Future<List<Charge>> chargesForRange(
      int year, int startMonth, int endMonth) {
    return (db.select(db.charges)
          ..where((c) =>
              c.year.equals(year) &
              c.month.isBetweenValues(startMonth, endMonth)))
        .get();
  }

  /// The row's utility/service charges total (electricity + water + service).
  static int _chargesTotal(Charge c) => c.electricity + c.water + c.service;

  /// unitId → that month's rent deduction, from one month's charges rows.
  static Map<int, int> _deductionByUnit(List<Charge> charges) =>
      {for (final c in charges) c.unitId: c.deduction};

  /// unitId → that month's charges total, from one month's charges rows.
  static Map<int, int> _chargesByUnit(List<Charge> charges) =>
      {for (final c in charges) c.unitId: _chargesTotal(c)};

  /// Insert-or-update this month's electricity/water/service charges for a unit
  /// (negatives floored at 0). The row's rent deduction is left as it was —
  /// that's [setDeduction]'s field. When everything on the row is 0 it is
  /// deleted instead, keeping the table sparse so "no charges" and "all zero"
  /// read the same.
  Future<void> setCharges(
    int unitId,
    int year,
    int month, {
    int electricity = 0,
    int water = 0,
    int service = 0,
  }) async {
    final existing = await chargesFor(unitId, year, month);
    await _writeCharge(
      unitId,
      year,
      month,
      electricity: electricity,
      water: water,
      service: service,
      deduction: existing?.deduction ?? 0,
      deductionNote: existing?.deductionNote,
    );
  }

  /// Set the landlord's rent deduction for a unit-month — [amount] (whole NPR,
  /// floored at 0) credited to the tenant against rent, e.g. for goods the
  /// landlord took from their shop, with an optional [note] saying what for.
  /// 0 clears the deduction (and its note); the utility charges on the same
  /// row are left untouched.
  Future<void> setDeduction(
    int unitId,
    int year,
    int month, {
    required int amount,
    String? note,
  }) async {
    final existing = await chargesFor(unitId, year, month);
    await _writeCharge(
      unitId,
      year,
      month,
      electricity: existing?.electricity ?? 0,
      water: existing?.water ?? 0,
      service: existing?.service ?? 0,
      deduction: amount,
      deductionNote: note,
    );
  }

  /// Writes the full (unit, month) charges row: negatives floor to 0, a note
  /// only survives alongside a non-zero deduction, and an all-zero row is
  /// deleted rather than stored — locally and in the cloud, else a stale row
  /// resurrects on another device.
  Future<void> _writeCharge(
    int unitId,
    int year,
    int month, {
    required int electricity,
    required int water,
    required int service,
    required int deduction,
    required String? deductionNote,
  }) async {
    final e = electricity < 0 ? 0 : electricity;
    final w = water < 0 ? 0 : water;
    final s = service < 0 ? 0 : service;
    final d = deduction < 0 ? 0 : deduction;
    final note = deductionNote?.trim();
    final n = (d == 0 || note == null || note.isEmpty) ? null : note;
    if (e == 0 && w == 0 && s == 0 && d == 0) {
      await _deleteChargeLocal(unitId, year, month);
      await _queueCharge(unitId, year, month);
      return;
    }
    await _upsertChargeLocal(ChargesCompanion.insert(
      unitId: unitId,
      year: year,
      month: month,
      electricity: Value(e),
      water: Value(w),
      service: Value(s),
      deduction: Value(d),
      deductionNote: Value(n),
    ));
    await _queueCharge(unitId, year, month);
  }

  Future<void> _deleteChargeLocal(int unitId, int year, int month) =>
      (db.delete(db.charges)
            ..where((c) =>
                c.unitId.equals(unitId) &
                c.year.equals(year) &
                c.month.equals(month)))
          .go();

  /// Upsert on the (unit, year, month) unique index — see [_upsertPaymentLocal]
  /// for why we name the target. Drift-only — callers push.
  Future<void> _upsertChargeLocal(ChargesCompanion entry) =>
      db.into(db.charges).insert(
            entry,
            onConflict: DoUpdate(
              (_) => entry,
              target: [db.charges.unitId, db.charges.year, db.charges.month],
            ),
          );

  // ---- Deposit -----------------------------------------------------------

  /// Set the held security-deposit amount for a unit (whole NPR, floored at 0).
  Future<void> setDeposit(Unit unit, int amount) =>
      updateUnit(unit.copyWith(depositAmount: amount < 0 ? 0 : amount));

  /// Flip a unit's deposit between held and refunded, stamping or clearing the
  /// refund date to match.
  Future<void> setDepositRefunded(Unit unit, bool refunded, {DateTime? on}) =>
      updateUnit(unit.copyWith(
        depositRefunded: refunded,
        depositRefundedOn: Value(refunded ? (on ?? DateTime.now()) : null),
      ));

  /// Total refundable deposits the landlord is still holding — the standing
  /// liability. Splits deposits on active tenancies (`held`) from those on
  /// vacated units not yet refunded (`dueBack`, overdue to return).
  Future<DepositLiability> depositLiability() async {
    final units = await allUnits();
    var held = 0, dueBack = 0, heldCount = 0, dueBackCount = 0;
    for (final u in units) {
      if (u.depositRefunded || u.depositAmount <= 0) continue;
      if (u.isActive) {
        held += u.depositAmount;
        heldCount++;
      } else {
        dueBack += u.depositAmount;
        dueBackCount++;
      }
    }
    return DepositLiability(
      held: held,
      dueBack: dueBack,
      heldCount: heldCount,
      dueBackCount: dueBackCount,
    );
  }

  /// Vacated units still holding a tenant's deposit (the `dueBack` side of
  /// [depositLiability]), sorted by code — the refunds that are overdue.
  Future<List<Unit>> unitsOwingDepositRefund() async {
    final units = await allUnits();
    return [
      for (final u in units)
        if (!u.isActive && !u.depositRefunded && u.depositAmount > 0) u
    ]..sort((a, b) => a.code.compareTo(b.code));
  }

  // ---- Reporting ---------------------------------------------------------

  Future<MonthSummary> summary(int year, int month,
      {double percent = 0}) async {
    final (units, payments, charges) = await _monthReads(year, month);
    return _summaryFrom(units, payments, charges, year, month, percent);
  }

  /// Dashboard totals from already-loaded units + that month's payments and
  /// charges rows. `expected` counts active units that had **started** by
  /// ([year], [month]) — a tenant who moved in later owes nothing for earlier
  /// months — each priced at rent + that month's utility charges, net of its
  /// rent deduction. `collected` sums every payment recorded for the month,
  /// including from since-vacated units, so money actually received is never
  /// understated.
  MonthSummary _summaryFrom(List<Unit> units, List<Payment> payments,
      List<Charge> charges, int year, int month, double percent) {
    final active = units
        .where((s) => s.isActive && _startedBy(s, year, month))
        .toList();
    final deductionById = _deductionByUnit(charges);
    final chargesById = _chargesByUnit(charges);
    final paymentById = {for (final p in payments) p.unitId: p};
    final dueById = {
      for (final s in active)
        s.id: netDue(
            _monthRent(RentSchedule(s, percent), paymentById[s.id], year, month),
            deductionById[s.id] ?? 0,
            charges: chargesById[s.id] ?? 0),
    };

    // Amount recorded per active unit (one row per month; fold defensively).
    final paidById = <int, int>{};
    for (final p in payments) {
      if (dueById.containsKey(p.unitId)) {
        paidById[p.unitId] = (paidById[p.unitId] ?? 0) + p.amount;
      }
    }

    final expected = dueById.values.fold<int>(0, (sum, d) => sum + d);
    final collected = payments.fold<int>(0, (sum, p) => sum + p.amount);
    var paidCount = 0;
    var partialCount = 0;
    // Still owed: each unit's own shortfall. Not `expected − collected` —
    // `collected` includes vacated units and overpayments, which would cancel
    // out another unit's unpaid rent (buglog B06).
    var outstanding = 0;
    dueById.forEach((id, due) {
      final amt = paidById[id] ?? 0;
      if (amt < due) outstanding += due - amt;
      if (settles(paid: amt, due: due, deduction: deductionById[id] ?? 0)) {
        paidCount++;
      } else if (amt > 0) {
        partialCount++;
      }
    });

    return MonthSummary(
      expected: expected,
      collected: collected,
      paidCount: paidCount,
      partialCount: partialCount,
      activeCount: active.length,
      outstanding: outstanding,
    );
  }

  /// The rent that was in effect for [unit] during BS [year]/[month] — see
  /// [RentSchedule.rentFor]. One-off form; to price a run of months for the
  /// same unit build a [RentSchedule] once and reuse it.
  static int rentInEffect(Unit unit, int year, int month, double percent) =>
      RentSchedule(unit, percent).rentFor(year, month);

  /// Aggregated totals for an inclusive BS month range within one year —
  /// convenience form of [periodSummarySpan] for the common quarter/BS-year
  /// scopes and existing call sites.
  Future<PeriodSummary> periodSummary(
          int year, int startMonth, int endMonth, {double percent = 0}) =>
      periodSummarySpan(BsMonth(year, startMonth), BsMonth(year, endMonth),
          percent: percent);

  /// The one month-key both span queries and the aggregation share.
  static int _monthKey(int year, int month) => year * 100 + month;

  static bool _inSpan(int year, int month, BsMonth start, BsMonth end) {
    final k = _monthKey(year, month);
    return k >= _monthKey(start.year, start.month) &&
        k <= _monthKey(end.year, end.month);
  }

  /// Payments for an inclusive span of BS months that may cross BS-year
  /// boundaries (e.g. an AD calendar year, Magh → Poush). Mirrors
  /// [history]'s pattern: bound the query to the span's years, filter the
  /// exact months in memory.
  Future<List<Payment>> paymentsForSpan(BsMonth start, BsMonth end) async {
    final rows = await (db.select(db.payments)
          ..where((p) => p.year.isBetweenValues(start.year, end.year)))
        .get();
    return [
      for (final p in rows)
        if (_inSpan(p.year, p.month, start, end)) p
    ];
  }

  /// Charges rows for an inclusive span of BS months (see [paymentsForSpan]).
  Future<List<Charge>> chargesForSpan(BsMonth start, BsMonth end) async {
    final rows = await (db.select(db.charges)
          ..where((c) => c.year.isBetweenValues(start.year, end.year)))
        .get();
    return [
      for (final c in rows)
        if (_inSpan(c.year, c.month, start, end)) c
    ];
  }

  /// The inclusive run of BS months from [start] through [end].
  static List<BsMonth> _spanMonths(BsMonth start, BsMonth end) {
    final months = <BsMonth>[];
    for (var m = start;; m = m.next()) {
      months.add(m);
      if (m == end) return months;
      if (months.length > 36) {
        throw ArgumentError('span end precedes start, or span exceeds 36 months');
      }
    }
  }

  /// Aggregated totals for any inclusive run of BS months, crossing BS-year
  /// boundaries freely — a single month, a quarter, a BS year, or an AD
  /// calendar year (which spans two BS years: Magh → Poush). [percent] is the
  /// active escalation rate, used to price historical months at the rent that
  /// applied then (see [rentInEffect]).
  Future<PeriodSummary> periodSummarySpan(BsMonth start, BsMonth end,
      {double percent = 0}) async {
    final months = _spanMonths(start, end);
    // ALL payments in range — including from since-vacated units, so the
    // period's `collected` reflects money actually received. Expected and
    // per-unit outstanding still cover active units only. The three reads are
    // independent, so they go to the DB isolate together.
    final (units, payments, charges) = await (
      allUnits(),
      paymentsForSpan(start, end),
      chargesForSpan(start, end),
    ).wait;
    final active = units.where((s) => s.isActive).toList();
    // Adjustments per (unit, year, month) — every month is priced at rent +
    // its utility charges, net of its rent deduction. Keys carry the year so
    // the same month number in two BS years can't collide across a span.
    final deductionByKey = {
      for (final c in charges) (c.unitId, c.year, c.month): c.deduction
    };
    final chargesByKey = {
      for (final c in charges) (c.unitId, c.year, c.month): _chargesTotal(c)
    };
    // The full rows too, for the per-type breakdown and deduction notes.
    final chargeRowByKey = {
      for (final c in charges) (c.unitId, c.year, c.month): c
    };
    // One schedule per unit: its BS anchors convert once for all the months.
    final schedules = {for (final s in active) s.id: RentSchedule(s, percent)};
    // Amount paid per (unit, year, month) — partial payments included — and
    // the payment row itself, for the rent it was made against.
    final paidByKey = <(int, int, int), int>{};
    final paymentByKey = <(int, int, int), Payment>{};
    for (final p in payments) {
      final k = (p.unitId, p.year, p.month);
      paidByKey[k] = (paidByKey[k] ?? 0) + p.amount;
      paymentByKey[k] = p;
    }
    // The month's rent: what a payment was made against, else the rent in
    // effect then (see [_monthRent]).
    int rentFor(Unit s, BsMonth m) => _monthRent(schedules[s.id]!,
        paymentByKey[(s.id, m.year, m.month)], m.year, m.month);
    int dueFor(Unit s, BsMonth m) {
      final schedule = schedules[s.id]!;
      // Adjustments on a month before the tenant moved in must not create a
      // phantom due — nothing was owed then (mirrors history()).
      if (!schedule.startedBy(m.year, m.month)) return 0;
      return netDue(rentFor(s, m),
          deductionByKey[(s.id, m.year, m.month)] ?? 0,
          charges: chargesByKey[(s.id, m.year, m.month)] ?? 0);
    }

    // Per-month breakdown — expected uses the rent in effect THAT month for
    // each unit, so a later escalation can't inflate a historical month.
    // Alongside it, split expected into its income components: rent, utility
    // charges, and deductions capped at each month's rent + charges (the same
    // floor netDue applies), so rent + charges − deductions == expected.
    final buckets = <MonthBucket>[];
    var totalExpected = 0;
    var rentExpected = 0, chargesExpected = 0, deductionsTotal = 0;
    // Per-type charge intel, gated identically to chargesExpected so the
    // breakdown's total reconciles with it exactly.
    var elecTotal = 0, waterTotal = 0, serviceTotal = 0;
    final elecUnits = <int>{}, waterUnits = <int>{}, serviceUnits = <int>{};
    final unitsWithCharges = <int>{};
    final deductionEntries = <DeductionEntry>[];
    for (final m in months) {
      var monthExpected = 0;
      var monthOutstanding = 0;
      for (final s in active) {
        final schedule = schedules[s.id]!;
        if (!schedule.startedBy(m.year, m.month)) continue;
        final rent = rentFor(s, m);
        final monthCharges = chargesByKey[(s.id, m.year, m.month)] ?? 0;
        final deduction = deductionByKey[(s.id, m.year, m.month)] ?? 0;
        final capped =
            deduction > rent + monthCharges ? rent + monthCharges : deduction;
        rentExpected += rent;
        chargesExpected += monthCharges;
        deductionsTotal += capped < 0 ? 0 : capped;
        final row = chargeRowByKey[(s.id, m.year, m.month)];
        if (row != null) {
          if (row.electricity > 0) {
            elecTotal += row.electricity;
            elecUnits.add(s.id);
          }
          if (row.water > 0) {
            waterTotal += row.water;
            waterUnits.add(s.id);
          }
          if (row.service > 0) {
            serviceTotal += row.service;
            serviceUnits.add(s.id);
          }
          if (_chargesTotal(row) > 0) unitsWithCharges.add(s.id);
          if (capped > 0) {
            deductionEntries.add(DeductionEntry(
              unit: s,
              month: m,
              amount: capped,
              note: row.deductionNote,
            ));
          }
        }
        final due = dueFor(s, m);
        monthExpected += due;
        final paid = paidByKey[(s.id, m.year, m.month)] ?? 0;
        if (paid < due) monthOutstanding += due - paid;
      }
      final collected = payments
          .where((p) => p.year == m.year && p.month == m.month)
          .fold<int>(0, (sum, p) => sum + p.amount);
      buckets.add(MonthBucket(
        year: m.year,
        month: m.month,
        expected: monthExpected,
        collected: collected,
        outstanding: monthOutstanding,
      ));
      totalExpected += monthExpected;
    }

    // Outstanding per unit + count of fully-settled (unit, month) slots.
    // Owed is the true shortfall (rent-in-effect − paid) summed over the
    // period, so a month paid in full at the old rate isn't re-charged after a
    // raise, and a partial month contributes only its remainder. Months before
    // a tenant moved in are not slots at all — they count in neither the
    // paid tally nor the denominator, so "Paid n/m" reflects months actually
    // owed, not the calendar span.
    final outstanding = <PeriodDebt>[];
    var paidSlots = 0;
    var startedSlots = 0;
    for (final s in active) {
      var owed = 0;
      final unpaid = <BsMonth>[];
      for (final m in months) {
        if (!schedules[s.id]!.startedBy(m.year, m.month)) continue;
        startedSlots++;
        final due = dueFor(s, m);
        final paid = paidByKey[(s.id, m.year, m.month)] ?? 0;
        if (paid >= due) {
          paidSlots++;
        } else {
          owed += due - paid; // full or partial shortfall at the month's rate
          unpaid.add(m);
        }
      }
      if (owed > 0) {
        outstanding.add(PeriodDebt(
          unit: s,
          amountOwed: owed,
          monthsUnpaid: unpaid.length,
          unpaidMonths: unpaid,
        ));
      }
    }
    outstanding.sort((a, b) {
      final byAmount = b.amountOwed.compareTo(a.amountOwed);
      return byAmount != 0 ? byAmount : a.unit.code.compareTo(b.unit.code);
    });

    return PeriodSummary(
      expected: totalExpected,
      collected: payments.fold<int>(0, (sum, p) => sum + p.amount),
      rentExpected: rentExpected,
      chargesExpected: chargesExpected,
      deductions: deductionsTotal,
      paidSlots: paidSlots,
      totalSlots: startedSlots,
      months: buckets,
      outstanding: outstanding,
      chargesBreakdown: ChargesBreakdown(
        electricity: elecTotal,
        water: waterTotal,
        service: serviceTotal,
        electricityUnits: elecUnits.length,
        waterUnits: waterUnits.length,
        serviceUnits: serviceUnits.length,
      ),
      deductionEntries: deductionEntries,
      unitsWithCharges: unitsWithCharges.length,
    );
  }

  /// Recent paid/partial/unpaid per month for a unit, newest first. Each entry
  /// carries the amount collected plus the rent **in effect that month** (see
  /// [rentInEffect], using the [percent] escalation rate) plus that month's
  /// utility charges, net of its rent deduction, as the expected — so
  /// a month fully paid at the pre-raise rate still reads as paid after an
  /// anniversary raise lands, instead of flipping to partial.
  Future<List<HistoryEntry>> history(int unitId, BsMonth from,
      {int months = 6, double percent = 0}) async {
    // The window spans at most two BS years: bound both row queries to them
    // (the (unit, year, month) unique index serves the lookup) instead of
    // loading the unit's whole history, and issue the three reads together —
    // one round trip to the DB isolate. Then fill the window in memory rather
    // than a SELECT per month (N+1).
    var oldest = from;
    for (var i = 1; i < months; i++) {
      oldest = oldest.previous();
    }
    final (unit, paid, charges) = await (
      (db.select(db.units)..where((u) => u.id.equals(unitId)))
          .getSingleOrNull(),
      (db.select(db.payments)
            ..where((p) =>
                p.unitId.equals(unitId) &
                p.year.isBetweenValues(oldest.year, from.year)))
          .get(),
      (db.select(db.charges)
            ..where((c) =>
                c.unitId.equals(unitId) &
                c.year.isBetweenValues(oldest.year, from.year)))
          .get(),
    ).wait;
    if (unit == null) return const [];
    final paymentByMonth = {for (final p in paid) (p.year, p.month): p};
    final deductionByMonth = {
      for (final c in charges) (c.year, c.month): c.deduction
    };
    final chargesByMonth = {
      for (final c in charges) (c.year, c.month): _chargesTotal(c)
    };

    final schedule = RentSchedule(unit, percent);
    final entries = <HistoryEntry>[];
    var cursor = from;
    for (var i = 0; i < months; i++) {
      final key = (cursor.year, cursor.month);
      // Adjustments recorded against a month before the tenant moved in must
      // not read as due or "covered by deduction" — nothing was owed then.
      final started = schedule.startedBy(cursor.year, cursor.month);
      final deduction = started ? (deductionByMonth[key] ?? 0) : 0;
      final monthCharges = started ? (chargesByMonth[key] ?? 0) : 0;
      entries.add(HistoryEntry(
        year: cursor.year,
        month: cursor.month,
        amount: paymentByMonth[key]?.amount ?? 0,
        expected: netDue(
            _monthRent(
                schedule, paymentByMonth[key], cursor.year, cursor.month),
            deduction,
            charges: monthCharges),
        deduction: deduction,
      ));
      cursor = cursor.previous();
    }
    return entries;
  }

  /// CSV across an inclusive BS month range, one row per (unit, month), with
  /// leading `month`,`year` columns. Single-month ranges work too — pass the
  /// same month as start and end (this is the only CSV export path; the UI uses
  /// it for month, quarter, and year scopes). The `year` column keeps the
  /// round-trip year-safe.
  Future<String> exportCsvRange(int year, int startMonth, int endMonth) =>
      exportCsvSpan(BsMonth(year, startMonth), BsMonth(year, endMonth));

  /// Span form of [exportCsvRange]: any inclusive run of BS months, crossing
  /// BS-year boundaries freely (the AD calendar-year report needs Magh →
  /// Poush). Every row carries its own `year`, so the round-trip is safe.
  Future<String> exportCsvSpan(BsMonth start, BsMonth end) async {
    // One units load + one ranged payments query (was rowsForMonth per month —
    // e.g. 24 queries for a full year). The `year` column makes the round-trip
    // year-safe: importCsv reads it instead of falling back to the open year.
    final (allU, payments, charges) = await (
      allUnits(),
      paymentsForSpan(start, end),
      chargesForSpan(start, end),
    ).wait;
    final units = [...allU]..sort((a, b) => a.code.compareTo(b.code));
    final byKey = {for (final p in payments) (p.unitId, p.year, p.month): p};
    // `rent` stays the unit's headline rent (importCsv reads it back as
    // monthly_rent); the month's deduction and utility charges travel in their
    // own columns so a month settled with either still round-trips as paid.
    final chargeByKey = {
      for (final c in charges) (c.unitId, c.year, c.month): c
    };
    final buf = StringBuffer()
      ..writeln('month,year,code,tenant,rent,status,paid_on,method,amount,'
          'deduction,electricity,water,service');
    for (final m in _spanMonths(start, end)) {
      final monthLabel = BsCalendar.label(m.month);
      for (final s in units) {
        final charge = chargeByKey[(s.id, m.year, m.month)];
        final r = UnitRow(
          unit: s,
          payment: byKey[(s.id, m.year, m.month)],
          charges: charge == null ? 0 : _chargesTotal(charge),
          deduction: charge?.deduction ?? 0,
          // The status column follows the rent the payment was made against.
          rent: byKey[(s.id, m.year, m.month)]?.rentAtPayment,
        );
        buf.writeln(
            _csvRow(r, charge: charge, monthLabel: monthLabel, year: m.year));
      }
    }
    return buf.toString();
  }

  /// One CSV data row for a unit's month. [monthLabel]/[year], when given,
  /// prepend the leading `month`,`year` columns used by range exports; omit them
  /// for single-month exports. Column order matches the headers the callers write.
  static String _csvRow(UnitRow r,
      {Charge? charge, String? monthLabel, int? year}) {
    final p = r.payment;
    String opt(int? v) => (v == null || v == 0) ? '' : '$v';
    return [
      if (monthLabel != null) _csv(monthLabel),
      if (year != null) '$year',
      _csv(r.unit.code),
      _csv(r.unit.tenantName),
      r.unit.monthlyRent,
      _statusLabel(r),
      p?.paidOn?.toIso8601String().split('T').first ?? '',
      p?.method.name ?? '',
      p?.amount.toString() ?? '',
      opt(r.deduction),
      opt(charge?.electricity),
      opt(charge?.water),
      opt(charge?.service),
    ].join(',');
  }

  static String _csv(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static String _statusLabel(UnitRow r) => switch (r.status) {
        PayStatus.paid => 'paid',
        PayStatus.partial => 'partial',
        PayStatus.pending => 'pending',
      };

  // ---- Import ------------------------------------------------------------

  /// Merges a CSV in Rent Bee's export format into the ledger:
  ///   • units are upserted by `code` (new ones created, existing ones get
  ///     their tenant/rent updated), and
  ///   • paid/partial rows become payments, upserted by (unit, month).
  ///
  /// Recognised columns (case-insensitive header, order-independent): code*,
  /// tenant, rent, month, status, paid_on, method, amount, deduction,
  /// electricity, water, service, year.
  /// The BS year comes from a `year` column if present, otherwise
  /// [fallbackYear] (single-year files import into the selected year).
  /// Existing data not referenced by the file is left untouched. Returns the
  /// number of units added/updated and payments written.
  ///
  /// All or nothing: a file that fails part-way leaves the ledger (and the
  /// cloud copy) exactly as it was — never half a file merged in.
  Future<({int unitsAdded, int unitsUpdated, int payments})> importCsv(
    String content, {
    required int fallbackYear,
  }) =>
      _atomically(() => _importCsv(content, fallbackYear: fallbackYear));

  /// Text of a picked CSV file. Strict: a file that is not UTF-8 (Excel's
  /// plain "CSV" on Windows, or "Unicode Text") is refused with a way out,
  /// instead of being imported with tenant names turned into "\uFFFD" marks.
  static String decodeCsv(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FormatException(
          'This file is not saved as UTF-8, so names in it would be damaged. '
          'Save it again as "CSV UTF-8" and retry.');
    }
  }

  Future<({int unitsAdded, int unitsUpdated, int payments})> _importCsv(
    String content, {
    required int fallbackYear,
  }) async {
    final table = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(content.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
    if (table.length < 2) {
      return (unitsAdded: 0, unitsUpdated: 0, payments: 0);
    }

    final header =
        table.first.map((e) => e.toString().trim().toLowerCase()).toList();
    int col(String name) => header.indexOf(name);
    final iYear = col('year'),
        iMonth = col('month'),
        iCode = col('code'),
        iTenant = col('tenant'),
        iRent = col('rent'),
        iStatus = col('status'),
        iPaidOn = col('paid_on'),
        iMethod = col('method'),
        iAmount = col('amount'),
        iDeduction = col('deduction'),
        iElectricity = col('electricity'),
        iWater = col('water'),
        iService = col('service');
    if (iCode < 0) {
      throw const FormatException('CSV is missing a "code" column.');
    }

    final byCode = {for (final u in await allUnits()) u.code: u};
    var unitsAdded = 0, unitsUpdated = 0, payments = 0;

    for (var r = 1; r < table.length; r++) {
      final row = table[r];
      String cell(int i) =>
          (i >= 0 && i < row.length) ? row[i].toString().trim() : '';
      final code = cell(iCode);
      if (code.isEmpty) continue;
      final tenant = cell(iTenant);
      final rent = _parseInt(cell(iRent));

      // Upsert the unit (idempotent across this unit's repeated month rows).
      int unitId;
      final existing = byCode[code];
      if (existing != null) {
        unitId = existing.id;
        final updated = existing.copyWith(
          tenantName: tenant.isEmpty ? existing.tenantName : tenant,
          monthlyRent:
              (rent == null || rent < 0) ? existing.monthlyRent : rent,
        );
        if (updated != existing) {
          await updateUnit(updated);
          byCode[code] = updated;
          unitsUpdated++;
        }
      } else {
        unitId = await createUnit(UnitsCompanion.insert(
          code: code,
          tenantName: tenant.isEmpty ? '(imported)' : tenant,
          monthlyRent: (rent == null || rent < 0) ? 0 : rent,
        ));
        // Cache it so later rows for the same code don't re-create it.
        byCode[code] = await (db.select(db.units)
              ..where((u) => u.id.equals(unitId)))
            .getSingle();
        unitsAdded++;
      }

      final monthNum = _monthNumber(cell(iMonth));

      // The month's rent deduction, when the file carries one (our own export
      // does) — without it a deduction-settled month would import as pending.
      final deduction = _parseInt(cell(iDeduction));
      if (monthNum != null && deduction != null && deduction > 0) {
        await setDeduction(unitId, _year(cell(iYear), fallbackYear), monthNum,
            amount: deduction);
      }

      // The month's utility charges likewise feed the due — without them a
      // paid month that included charges would import as overpaid/ambiguous.
      final electricity = _parseInt(cell(iElectricity)) ?? 0;
      final water = _parseInt(cell(iWater)) ?? 0;
      final service = _parseInt(cell(iService)) ?? 0;
      if (monthNum != null && (electricity > 0 || water > 0 || service > 0)) {
        await setCharges(unitId, _year(cell(iYear), fallbackYear), monthNum,
            electricity: electricity, water: water, service: service);
      }

      // Upsert the payment for settled/partial rows carrying an amount.
      final status = cell(iStatus).toLowerCase();
      final amount = _parseInt(cell(iAmount));
      if (monthNum != null &&
          amount != null &&
          amount > 0 &&
          status != 'pending') {
        final pYear = _year(cell(iYear), fallbackYear);
        await _upsertPaymentLocal(PaymentsCompanion.insert(
          unitId: unitId,
          year: pYear,
          month: monthNum,
          amount: amount,
          paidOn: Value(_parsePaidOn(cell(iPaidOn))),
          method: Value(_method(cell(iMethod))),
        ));
        await _queuePayment(unitId, pYear, monthNum);
        payments++;
      }
    }
    return (
      unitsAdded: unitsAdded,
      unitsUpdated: unitsUpdated,
      payments: payments
    );
  }

  /// BS month from a cell that is either a 1–12 number or a month name.
  static int? _monthNumber(String s) {
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n != null) return (n >= 1 && n <= 12) ? n : null;
    final i = BsCalendar.monthLabels
        .indexWhere((m) => m.toLowerCase() == s.toLowerCase());
    return i < 0 ? null : i + 1;
  }

  /// Resolves a payment-method cell to a [PayMethod]. Exact enum names win; then
  /// common real-world synonyms map to the closest method. A blank cell is the
  /// default `cash`; an unrecognised non-empty value becomes `other` (rather
  /// than silently masquerading as a cash receipt).
  static PayMethod _method(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return PayMethod.cash;
    for (final m in PayMethod.values) {
      if (m.name == t) return m;
    }
    final c = t.replaceAll(RegExp(r'[\s_-]'), '');
    const wallet = {
      'esewa', 'khalti', 'imepay', 'ime', 'fonepay', 'connectips', 'mobile',
      'digital', 'qr', 'wallet',
    };
    const bank = {
      'cheque', 'check', 'transfer', 'banktransfer', 'deposit', 'online',
    };
    if (wallet.contains(c)) return PayMethod.wallet;
    if (bank.contains(c)) return PayMethod.bank;
    return PayMethod.other;
  }

  /// Lenient whole-number parse for human/spreadsheet-formatted cells: tolerates
  /// thousands separators, currency symbols, and surrounding text (`"Rs 10,000"`,
  /// `"10000.50"` → 10000), truncating any decimal fraction. Returns null when no
  /// digits are present. Used for rent and amount so a formatted cell isn't
  /// silently read as 0 / dropped.
  static int? _parseInt(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    final neg = s.startsWith('-');
    final dot = s.indexOf('.');
    if (dot >= 0) s = s.substring(0, dot); // drop the fractional part
    s = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    return (n != null && neg) ? -n : n;
  }

  /// BS year from a cell, validated to a sane range; out-of-range or unparseable
  /// values fall back to [fallbackYear] (the open year) rather than mis-filing a
  /// payment into a year the UI can never reach.
  static int _year(String cell, int fallbackYear) {
    final y = _parseInt(cell);
    return (y != null && y >= 2000 && y <= 2200) ? y : fallbackYear;
  }

  /// Parses a `paid_on` date. Prefers ISO 8601 (what the export writes); also
  /// accepts the common day-first (`20/05/2025`, `20-05-2025`) and year-first
  /// (`2025/5/20`) shapes a person might hand-type. Returns null on anything
  /// else, leaving the payment dateless rather than guessing wrong.
  static DateTime? _parsePaidOn(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final parts = s.split(RegExp(r'[/.\-]'));
    if (parts.length != 3) return null;
    final a = int.tryParse(parts[0]),
        b = int.tryParse(parts[1]),
        c = int.tryParse(parts[2]);
    if (a == null || b == null || c == null) return null;
    if (a > 31) return _ymd(a, b, c); // year-first: yyyy/M/d
    if (c > 31) return _ymd(c, b, a); // day-first:  d/M/yyyy
    return null; // ambiguous (e.g. 2-digit year) — don't guess
  }

  static DateTime? _ymd(int y, int m, int d) =>
      (m >= 1 && m <= 12 && d >= 1 && d <= 31) ? DateTime(y, m, d) : null;

  // ---- JSON backup / restore ---------------------------------------------

  /// Current backup-file format version. Bumped only if the JSON shape changes
  /// in a way [importBackupJson] must branch on (independent of the DB schema
  /// version, which is also recorded for diagnostics).
  static const backupFormatVersion = 1;

  /// A complete, lossless JSON snapshot of the whole ledger — every unit,
  /// payment, and charge with all columns. Unlike [exportCsvRange] (a per-month
  /// collection sheet carrying only code/tenant/rent + that month's payment),
  /// this round-trips through [importBackupJson] exactly: deposits, utility
  /// charges, occupancy, lease-escalation anchors, payment methods and notes
  /// all survive. This is the file to use as a real backup.
  /// [currency] is the ledger's active currency ('npr'/'usd') at export time —
  /// carried so a restore doesn't silently revert to NPR (see
  /// [SettingsProvider.currency], threaded in from the UI layer since the
  /// repository has no settings dependency of its own).
  Future<String> exportBackupJson({DateTime? exportedAt, String? currency}) async {
    final units = await allUnits();
    final payments = await allPayments();
    final charges = await allCharges();
    final data = <String, dynamic>{
      'app': 'rent-bee',
      'type': 'backup',
      'formatVersion': backupFormatVersion,
      'schemaVersion': db.schemaVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'currency': currency,
      'units': [for (final u in units) _unitToBackup(u)],
      'payments': [for (final p in payments) _paymentToBackup(p)],
      'charges': [for (final c in charges) _chargeToBackup(c)],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Reads what a backup file contains without changing anything — so the
  /// restore dialog can say what is about to replace the ledger, and refuse a
  /// file that would leave it empty. Throws [FormatException] for anything
  /// that isn't a Rent Bee backup.
  static ({int units, int payments, int charges, DateTime? exportedAt})
      inspectBackup(String content) {
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'rent-bee' ||
        decoded['type'] != 'backup') {
      throw const FormatException(
          'Not a Rent Bee backup file (expected a JSON backup export).');
    }
    int count(String key) => (decoded[key] as List?)?.length ?? 0;
    return (
      units: count('units'),
      payments: count('payments'),
      charges: count('charges'),
      exportedAt: _date(decoded['exportedAt']),
    );
  }

  /// Restores an [exportBackupJson] snapshot, **replacing all current data**.
  /// Atomic: the whole local rebuild runs in one drift transaction, so a
  /// malformed row throws and rolls back, leaving the existing ledger intact.
  /// Unit `cloudId`s are preserved so a restored ledger keeps its cross-device
  /// identity; local int ids are reassigned and payment/charge rows remapped to
  /// the new ids. With sync on, the cloud copy is replaced in one sequenced
  /// erase-then-write afterwards (mirrors [generateDemoData]). Returns the
  /// number of rows written.
  Future<({int units, int payments, int charges, String? currency})>
      importBackupJson(
    String content,
  ) async {
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'rent-bee' ||
        decoded['type'] != 'backup') {
      throw const FormatException(
          'Not a Rent Bee backup file (expected a JSON backup export).');
    }
    final unitMaps =
        ((decoded['units'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final paymentMaps = ((decoded['payments'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final chargeMaps = ((decoded['charges'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();

    final result = await db.transaction(() async {
      await eraseAllLocal();
      final idMap = <int, int>{}; // backup unit id → new local id
      for (final m in unitMaps) {
        final newId = await _insertUnitLocal(_unitFromBackup(m));
        idMap[(m['id'] as num).toInt()] = newId;
      }
      var pCount = 0, cCount = 0;
      for (final m in paymentMaps) {
        final nu = idMap[(m['unitId'] as num).toInt()];
        if (nu == null) continue;
        await db.into(db.payments).insert(_paymentFromBackup(m, nu));
        pCount++;
      }
      for (final m in chargeMaps) {
        final nu = idMap[(m['unitId'] as num).toInt()];
        if (nu == null) continue;
        await db.into(db.charges).insert(_chargeFromBackup(m, nu));
        cCount++;
      }
      return (
        units: idMap.length,
        payments: pCount,
        charges: cCount,
        currency: decoded['currency'] as String?,
      );
    });

    // One sequenced cloud replace for the whole restored dataset.
    await _queue(const [SyncKey.all()]);
    return result;
  }

  static String? _iso(DateTime? d) => d?.toIso8601String();
  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  static Map<String, dynamic> _unitToBackup(Unit u) => {
        'id': u.id,
        'cloudId': u.cloudId,
        'code': u.code,
        'tenantName': u.tenantName,
        'businessType': u.businessType,
        'monthlyRent': u.monthlyRent,
        'phone': u.phone,
        'notes': u.notes,
        'isActive': u.isActive,
        'createdAt': _iso(u.createdAt),
        'startedOn': _iso(u.startedOn),
        'lastRaisedOn': _iso(u.lastRaisedOn),
        'depositAmount': u.depositAmount,
        'depositRefunded': u.depositRefunded,
        'depositRefundedOn': _iso(u.depositRefundedOn),
      };

  static Map<String, dynamic> _paymentToBackup(Payment p) => {
        'unitId': p.unitId,
        'year': p.year,
        'month': p.month,
        'amount': p.amount,
        'rentAtPayment': p.rentAtPayment,
        'paidOn': _iso(p.paidOn),
        'method': p.method.name,
        'note': p.note,
        'createdAt': _iso(p.createdAt),
      };

  static Map<String, dynamic> _chargeToBackup(Charge c) => {
        'unitId': c.unitId,
        'year': c.year,
        'month': c.month,
        'electricity': c.electricity,
        'water': c.water,
        'service': c.service,
        'deduction': c.deduction,
        'deductionNote': c.deductionNote,
        'createdAt': _iso(c.createdAt),
      };

  // A null cloudId in the file → absent so [_insertUnitLocal] stamps a fresh
  // UUID; a present one is preserved to keep the unit's cross-device identity.
  UnitsCompanion _unitFromBackup(Map<String, dynamic> m) {
    final cloudId = m['cloudId'] as String?;
    return UnitsCompanion.insert(
      code: m['code'] as String,
      tenantName: m['tenantName'] as String? ?? '',
      monthlyRent: (m['monthlyRent'] as num?)?.toInt() ?? 0,
      cloudId: cloudId == null ? const Value.absent() : Value(cloudId),
      businessType: Value(m['businessType'] as String? ?? ''),
      phone: Value(m['phone'] as String?),
      notes: Value(m['notes'] as String?),
      isActive: Value(m['isActive'] as bool? ?? true),
      createdAt: Value(_date(m['createdAt']) ?? DateTime.now()),
      startedOn: Value(_date(m['startedOn'])),
      lastRaisedOn: Value(_date(m['lastRaisedOn'])),
      depositAmount: Value((m['depositAmount'] as num?)?.toInt() ?? 0),
      depositRefunded: Value(m['depositRefunded'] as bool? ?? false),
      depositRefundedOn: Value(_date(m['depositRefundedOn'])),
    );
  }

  PaymentsCompanion _paymentFromBackup(Map<String, dynamic> m, int unitId) =>
      PaymentsCompanion.insert(
        unitId: unitId,
        year: (m['year'] as num).toInt(),
        month: (m['month'] as num).toInt(),
        amount: (m['amount'] as num).toInt(),
        rentAtPayment: Value((m['rentAtPayment'] as num?)?.toInt()),
        paidOn: Value(_date(m['paidOn'])),
        method: Value(_method(m['method'] as String? ?? '')),
        note: Value(m['note'] as String?),
        createdAt: Value(_date(m['createdAt']) ?? DateTime.now()),
      );

  ChargesCompanion _chargeFromBackup(Map<String, dynamic> m, int unitId) =>
      ChargesCompanion.insert(
        unitId: unitId,
        year: (m['year'] as num).toInt(),
        month: (m['month'] as num).toInt(),
        electricity: Value((m['electricity'] as num?)?.toInt() ?? 0),
        water: Value((m['water'] as num?)?.toInt() ?? 0),
        service: Value((m['service'] as num?)?.toInt() ?? 0),
        deduction: Value((m['deduction'] as num?)?.toInt() ?? 0),
        deductionNote: Value(m['deductionNote'] as String?),
        createdAt: Value(_date(m['createdAt']) ?? DateTime.now()),
      );

  /// True when a cloud-sync session is live (signed-in, non-guest owner).
  bool get cloudSyncActive => sync != null;

  /// Forces a full re-push of the whole local ledger to the cloud: every
  /// local row is written, then cloud documents with no local counterpart are
  /// removed. Used by the manual "Back up to cloud now" action; a no-op when
  /// not signed in.
  Future<void> resyncAllToCloud() async {
    if (sync == null) return;
    await _queue(const [SyncKey.all()]);
  }

  // ---- Seed / demo / reset -----------------------------------------------

  /// Sample units: [code, tenant, business, monthlyRent, phone].
  static const _demoUnits = [
    ['A-01', 'Rajesh Shrestha', 'Tea & Snacks', 18000, '9801234501'],
    ['A-02', 'Anjali Thapa', 'Tailoring', 15000, '9801234502'],
    ['A-03', 'Bikash Gurung', 'Mobile Repair', 22000, '9801234503'],
    ['A-04', 'Sita Magar', 'Beauty Parlour', 20000, '9801234504'],
    ['B-01', 'Hari Adhikari', 'Stationery', 16000, '9801234505'],
    ['B-02', 'Maya Tamang', 'Grocery', 25000, '9801234506'],
    ['B-03', 'Deepak Rai', 'Hardware', 28000, '9801234507'],
    ['B-04', 'Sunita K.C.', 'Clothing', 24000, '9801234508'],
    ['C-01', 'Ramesh Poudel', 'Pharmacy', 30000, '9801234509'],
    ['C-02', 'Gita Bhandari', 'Bakery', 19000, '9801234510'],
  ];


  /// Replaces all data with a realistic [years]-year demo dataset anchored at
  /// [anchor] (the selected month). Each unit starts [years] years back and its
  /// rent **grows on every anniversary** by [annualRaisePercent]% — so each
  /// month's payment is recorded at the rent that was in effect *that* BS year,
  /// and the lease-escalation feature is visible across history.
  ///
  /// The stored `monthly_rent` is the latest compounded value, and `lastRaisedOn`
  /// is stamped at the current anniversary so the launch auto-raise is a no-op.
  /// ~70% of (unit, month) slots are collected, so the ledger looks lived-in.
  Future<void> generateDemoData(
    BsMonth anchor, {
    double annualRaisePercent = 5,
    int years = 3,
  }) async {
    // Build the whole dataset locally first (drift-only), then push it to the
    // cloud once as a single sequenced erase-then-write (see [pushBulk] caller
    // below) — avoids per-row pushes racing with the erase.
    await eraseAllLocal();
    final pct = annualRaisePercent > 0 ? annualRaisePercent : 5.0;
    final now = DateTime.now();

    // The last unit demonstrates a completed tenancy: it moved out
    // [vacatedMonthsAgo] months ago — marked vacant, deposit refunded, and no
    // payments/charges after that month.
    final vacantIndex = _demoUnits.length - 1;
    const vacatedMonthsAgo = 7;
    var vm = anchor;
    for (var k = 0; k < vacatedMonthsAgo; k++) {
      vm = vm.previous();
    }
    final vacatedOn = adForBsMonthStart(vm.year, vm.month);

    // Insert units: started [years] years back (anniversary months spread for
    // variety), at the compounded current rent, each holding a ~2-month deposit.
    final ids = <int>[]; // parallel to _demoUnits
    final bases = <int>[]; // oldest (starting) rent per unit
    final startMonths = <int>[];
    final startYear = anchor.year - years;
    for (var i = 0; i < _demoUnits.length; i++) {
      final base = _demoUnits[i][3] as int;
      final startMonth = ((anchor.month - 1 + i * 2) % 12) + 1;
      // Anniversaries elapsed as of the anchor month.
      final anniv =
          (anchor.month >= startMonth ? anchor.year : anchor.year - 1) -
              startYear;
      final vacant = i == vacantIndex;
      final id = await _insertUnitLocal(UnitsCompanion.insert(
        code: _demoUnits[i][0] as String,
        tenantName: _demoUnits[i][1] as String,
        businessType: Value(_demoUnits[i][2] as String),
        monthlyRent: _rentAfter(base, pct, anniv),
        phone: Value(_demoUnits[i][4] as String),
        startedOn: Value(adForBsMonthStart(startYear, startMonth)),
        lastRaisedOn: Value(raiseStampFor(startYear + anniv, startMonth)),
        depositAmount: Value(base * 2), // ~2 months, set at move-in
        isActive: Value(!vacant),
        depositRefunded: Value(vacant),
        depositRefundedOn: Value(vacant ? vacatedOn : null),
      ));
      ids.add(id);
      bases.add(base);
      startMonths.add(startMonth);
    }

    // Payments (rent, ~70% collected) + monthly utility charges across the
    // window. Charges are billed every active month regardless of rent.
    final payments = <PaymentsCompanion>[];
    final charges = <ChargesCompanion>[];
    var cursor = anchor;
    for (var monthBack = 0; monthBack < years * 12; monthBack++) {
      for (var i = 0; i < ids.length; i++) {
        final sm = startMonths[i];
        // Skip months before this unit started…
        if (cursor.year < startYear ||
            (cursor.year == startYear && cursor.month < sm)) {
          continue;
        }
        // …and after the vacant unit moved out.
        if (i == vacantIndex && monthBack < vacatedMonthsAgo) continue;

        // Monthly utilities (electricity varies seasonally; water + service).
        charges.add(ChargesCompanion.insert(
          unitId: ids[i],
          year: cursor.year,
          month: cursor.month,
          electricity: Value(900 + ((cursor.month + i) % 9) * 160),
          water: Value(250 + (i % 3) * 60),
          service: const Value(400),
        ));

        // Rent, ~70% collected (deterministic), at the period's rent.
        if ((i * 7 + monthBack * 3) % 10 < 7) {
          final anniv = (cursor.month >= sm ? cursor.year : cursor.year - 1) -
              startYear;
          final rentThen = _rentAfter(bases[i], pct, anniv < 0 ? 0 : anniv);
          payments.add(PaymentsCompanion.insert(
            unitId: ids[i],
            year: cursor.year,
            month: cursor.month,
            amount: rentThen,
            rentAtPayment: Value(rentThen),
            paidOn: Value(now),
          ));
        }
      }
      cursor = cursor.previous();
    }
    await db.batch((b) {
      b.insertAll(db.payments, payments);
      b.insertAll(db.charges, charges);
    });

    // One sequenced cloud replace for the whole freshly-built dataset.
    await _queue(const [SyncKey.all()]);
  }

  /// [base] rent compounded by [pct]% for [anniversaries] years, rounded to
  /// whole NPR each year — matching [applyAnniversaryRaises].
  static int _rentAfter(int base, double pct, int anniversaries) {
    var r = base;
    for (var i = 0; i < anniversaries; i++) {
      r = ((r * (100 + pct)) / 100).round();
    }
    return r;
  }

  /// Deletes every payment and unit (charges cascade via FK). Irreversible.
  /// With sync on this is **global** — the cloud copy is wiped too, so every
  /// signed-in device clears. [eraseAllLocal] is the drift-only form.
  Future<void> eraseAll() async {
    await eraseAllLocal();
    // An empty ledger replacing the cloud copy erases it; queued through the
    // outbox so it still happens if sync isn't attached right now.
    await _queue(const [SyncKey.all()]);
  }

  /// Drift-only wipe (no cloud push). Used by the sync owner-guard when a
  /// different owner signs in on this device.
  Future<void> eraseAllLocal() async {
    await db.delete(db.payments).go();
    await db.delete(db.units).go();
    // Nothing is left to push; in particular the previous owner's pending
    // changes must never reach the next owner's cloud.
    await db.delete(db.pendingPushes).go();
  }

  // ---- Cloud sync: drift-only apply path (called by FirestoreSyncService;
  //      these NEVER push, which is what makes echo loops impossible) ---------

  /// Applies a batch of cloud state to the local ledger in **one transaction**,
  /// writing only what actually differs.
  ///
  /// The lists are either a live listener's changes, or — with [fullSnapshot]
  /// — the complete cloud state from a pull. For a full snapshot, a local row
  /// the cloud doesn't have is deleted when [deleteMissing] (it was removed on
  /// another device) or otherwise reported back in `toPush` (first sync: it
  /// exists only here and should go up).
  ///
  /// Three guarantees, all of which the old row-at-a-time apply lacked:
  ///   • **A pending key is never touched.** If this device changed a row and
  ///     the cloud hasn't acknowledged it (see [PendingPushes]), the cloud's
  ///     copy is stale by definition: it neither overwrites nor deletes the
  ///     local row. While a whole-ledger replace is pending, nothing is
  ///     applied at all.
  ///   • **Equal rows cost nothing.** Rows already matching the cloud are
  ///     skipped, so the common pull writes nothing and reports
  ///     `changed: false` — no UI refresh.
  ///   • **Two units with the same code both survive.** The unit with the
  ///     larger cloudId gets a numeric suffix; every device makes the same
  ///     choice, so they converge instead of each silently dropping the
  ///     other's unit.
  ///
  /// Never pushes (that is what makes echo loops impossible); the caller
  /// queues `toPush`.
  Future<RemoteApplyResult> applyRemote({
    List<RemoteUnit> units = const [],
    List<RemotePayment> payments = const [],
    List<RemoteCharge> charges = const [],
    List<String> removedUnits = const [],
    List<SyncKey> removedChildren = const [],
    bool fullSnapshot = false,
    bool deleteMissing = false,
  }) {
    return db.transaction(() async {
      final pending = {
        for (final p in await db.select(db.pendingPushes).get())
          SyncKey.fromRow(p),
      };
      if (pending.any((k) => k.isAll)) return const RemoteApplyResult();

      var changed = false;
      final toPush = <SyncKey>[];
      final writes = <void Function(Batch)>[];
      Future<void> flush() async {
        if (writes.isEmpty) return;
        final ops = List.of(writes);
        writes.clear();
        await db.batch((b) {
          for (final w in ops) {
            w(b);
          }
        });
      }

      // ---- Units ---------------------------------------------------------
      var local = await allUnits();
      final byCloud = <String, Unit>{
        for (final u in local)
          if (u.cloudId != null) u.cloudId!: u,
      };
      // code → the cloudId that holds it (null for a unit with no cloudId).
      final codeOwner = <String, String?>{
        for (final u in local) u.code: u.cloudId,
      };

      void dropUnit(Unit u) {
        writes.add((b) => b.deleteWhere(db.units, (t) => t.id.equals(u.id)));
        byCloud.remove(u.cloudId);
        codeOwner.remove(u.code);
        changed = true;
      }

      // Removals first, so a code they held is free for an incoming unit.
      for (final cid in removedUnits) {
        if (pending.contains(SyncKey.unit(cid))) continue;
        final u = byCloud[cid];
        if (u != null) dropUnit(u);
      }
      if (fullSnapshot) {
        final remoteIds = {for (final r in units) r.cloudId};
        for (final u in local) {
          final cid = u.cloudId;
          if (cid == null || remoteIds.contains(cid)) continue;
          if (pending.contains(SyncKey.unit(cid))) continue;
          if (deleteMissing) {
            dropUnit(u);
          } else {
            toPush.add(SyncKey.unit(cid));
          }
        }
      }

      for (var r in units) {
        if (pending.contains(SyncKey.unit(r.cloudId))) continue;
        if (codeOwner.containsKey(r.code) && codeOwner[r.code] != r.cloudId) {
          // Another unit already holds this code. The larger cloudId yields.
          final owner = codeOwner[r.code];
          if (owner == null || r.cloudId.compareTo(owner) > 0) {
            r = r.withCode(_freeCode(r.code, codeOwner, r.cloudId));
            toPush.add(SyncKey.unit(r.cloudId));
          } else {
            final loser = byCloud[owner]!;
            final newCode = _freeCode(loser.code, codeOwner, owner);
            writes.add((b) => b.update(
                db.units, UnitsCompanion(code: Value(newCode)),
                where: (t) => t.id.equals(loser.id)));
            codeOwner
              ..remove(loser.code)
              ..[newCode] = owner;
            byCloud[owner] = loser.copyWith(code: newCode);
            toPush.add(SyncKey.unit(owner));
            changed = true;
          }
        }
        final row = r;
        final existing = byCloud[row.cloudId];
        if (existing == null) {
          writes.add((b) => b.insert(db.units, row.toCompanion()));
          codeOwner[row.code] = row.cloudId;
          changed = true;
        } else if (!row.matches(existing)) {
          if (existing.code != row.code) {
            codeOwner
              ..remove(existing.code)
              ..[row.code] = row.cloudId;
          }
          writes.add((b) => b.update(
              db.units, row.toCompanion(includeCreatedAt: false),
              where: (t) => t.id.equals(existing.id)));
          changed = true;
        }
      }
      if (writes.isNotEmpty) {
        await flush();
        local = await allUnits(); // ids of the units just inserted
      }

      // ---- Payments and charges -----------------------------------------
      final orphanPayments = <RemotePayment>[];
      final orphanCharges = <RemoteCharge>[];
      final hasChildren = fullSnapshot ||
          payments.isNotEmpty ||
          charges.isNotEmpty ||
          removedChildren.isNotEmpty;
      if (hasChildren) {
        final idByCloud = <String, int>{
          for (final u in local)
            if (u.cloudId != null) u.cloudId!: u.id,
        };
        final cloudById = <int, String>{
          for (final e in idByCloud.entries) e.value: e.key,
        };

        // The local rows this batch could touch: one query per table (the
        // whole table for a full snapshot, else just the units involved).
        final Set<int>? unitIds = fullSnapshot
            ? null
            : {
                for (final r in payments) idByCloud[r.unitCloudId],
                for (final r in charges) idByCloud[r.unitCloudId],
                for (final k in removedChildren) idByCloud[k.cloudId],
              }.whereType<int>().toSet();
        final localPayments = unitIds == null
            ? await allPayments()
            : unitIds.isEmpty
                ? const <Payment>[]
                : await (db.select(db.payments)
                      ..where((p) => p.unitId.isIn(unitIds)))
                    .get();
        final localCharges = unitIds == null
            ? await allCharges()
            : unitIds.isEmpty
                ? const <Charge>[]
                : await (db.select(db.charges)
                      ..where((c) => c.unitId.isIn(unitIds)))
                    .get();
        final payBy = {
          for (final p in localPayments) (p.unitId, p.year, p.month): p,
        };
        final chargeBy = {
          for (final c in localCharges) (c.unitId, c.year, c.month): c,
        };
        final seenPay = <(int, int, int)>{};
        final seenCharge = <(int, int, int)>{};

        for (final r in payments) {
          final unitId = idByCloud[r.unitCloudId];
          if (unitId == null) {
            orphanPayments.add(r);
            continue;
          }
          final k = (unitId, r.year, r.month);
          seenPay.add(k);
          if (pending.contains(r.key)) continue;
          final existing = payBy[k];
          if (existing == null) {
            writes.add((b) => b.insert(db.payments, r.toCompanion(unitId)));
            changed = true;
          } else if (!r.matches(existing)) {
            writes.add((b) => b.update(db.payments, r.toCompanion(unitId),
                where: (t) => t.id.equals(existing.id)));
            changed = true;
          }
        }
        for (final r in charges) {
          final unitId = idByCloud[r.unitCloudId];
          if (unitId == null) {
            orphanCharges.add(r);
            continue;
          }
          final k = (unitId, r.year, r.month);
          seenCharge.add(k);
          if (pending.contains(r.key)) continue;
          final existing = chargeBy[k];
          if (existing == null) {
            writes.add((b) => b.insert(db.charges, r.toCompanion(unitId)));
            changed = true;
          } else if (!r.matches(existing)) {
            writes.add((b) => b.update(db.charges, r.toCompanion(unitId),
                where: (t) => t.id.equals(existing.id)));
            changed = true;
          }
        }

        for (final k in removedChildren) {
          if (pending.contains(k)) continue;
          final unitId = idByCloud[k.cloudId];
          if (unitId == null) continue;
          final key = (unitId, k.year, k.month);
          if (k.kind == SyncKey.kPayment) {
            final e = payBy[key];
            if (e == null) continue;
            writes.add(
                (b) => b.deleteWhere(db.payments, (t) => t.id.equals(e.id)));
          } else {
            final e = chargeBy[key];
            if (e == null) continue;
            writes.add(
                (b) => b.deleteWhere(db.charges, (t) => t.id.equals(e.id)));
          }
          changed = true;
        }

        if (fullSnapshot) {
          for (final p in localPayments) {
            if (seenPay.contains((p.unitId, p.year, p.month))) continue;
            final cid = cloudById[p.unitId];
            if (cid == null) continue;
            final key = SyncKey.payment(cid, p.year, p.month);
            if (pending.contains(key)) continue;
            if (deleteMissing) {
              writes.add((b) =>
                  b.deleteWhere(db.payments, (t) => t.id.equals(p.id)));
              changed = true;
            } else {
              toPush.add(key);
            }
          }
          for (final c in localCharges) {
            if (seenCharge.contains((c.unitId, c.year, c.month))) continue;
            final cid = cloudById[c.unitId];
            if (cid == null) continue;
            final key = SyncKey.charge(cid, c.year, c.month);
            if (pending.contains(key)) continue;
            if (deleteMissing) {
              writes.add(
                  (b) => b.deleteWhere(db.charges, (t) => t.id.equals(c.id)));
              changed = true;
            } else {
              toPush.add(key);
            }
          }
        }
        await flush();
      }

      return RemoteApplyResult(
        changed: changed,
        orphanPayments: orphanPayments,
        orphanCharges: orphanCharges,
        toPush: toPush,
      );
    });
  }

  /// The first free variant of [code] — `code-2`, `code-3`, … — kept within
  /// the 32-character column limit. A code already held by [self] counts as
  /// free (re-resolving the same collision must settle on the same answer).
  static String _freeCode(
      String code, Map<String, String?> owners, String self) {
    for (var n = 2;; n++) {
      final suffix = '-$n';
      final base = code.length + suffix.length > 32
          ? code.substring(0, 32 - suffix.length)
          : code;
      final candidate = '$base$suffix';
      if (!owners.containsKey(candidate) || owners[candidate] == self) {
        return candidate;
      }
    }
  }

  /// Upsert a unit arriving from the cloud, matched by its stable [cloudId].
  /// A `code` collision with another local row (the unique index) is caught and
  /// skipped in v1 rather than crashing the listener.
  Future<void> applyRemoteUnit(UnitsCompanion u) async {
    final cloudId = u.cloudId.value;
    if (cloudId == null) return;
    try {
      final existing = await (db.select(db.units)
            ..where((t) => t.cloudId.equals(cloudId)))
          .getSingleOrNull();
      if (existing == null) {
        await db.into(db.units).insert(u);
      } else {
        await (db.update(db.units)..where((t) => t.id.equals(existing.id)))
            .write(u);
      }
    } catch (e) {
      debugPrint('applyRemoteUnit skipped (code=${u.code.value}): $e');
    }
  }

  Future<void> deleteLocalUnitByCloudId(String cloudId) =>
      (db.delete(db.units)..where((u) => u.cloudId.equals(cloudId))).go();

  Future<void> applyRemotePayment(PaymentsCompanion p) =>
      _upsertPaymentLocal(p);

  Future<void> deleteLocalPayment(int unitId, int year, int month) =>
      (db.delete(db.payments)
            ..where((p) =>
                p.unitId.equals(unitId) &
                p.year.equals(year) &
                p.month.equals(month)))
          .go();

  Future<void> applyRemoteCharge(ChargesCompanion c) => _upsertChargeLocal(c);

  Future<void> deleteLocalCharge(int unitId, int year, int month) =>
      _deleteChargeLocal(unitId, year, month);
}

/// A unit's rent over time under the [percent]% anniversary escalation, with
/// the unit's BS start/anchor months converted once up front.
///
/// Pricing a run of months for one unit — a year report, the history strip —
/// used to redo the Gregorian→BS conversion (a loop over decades inside
/// nepali_utils) three times per (unit, month). Now it's two per unit.
class RentSchedule {
  final Unit unit;
  final double percent;

  /// BS month the tenant started; null when no start date is recorded.
  final ({int year, int month})? _startBs;

  /// Anniversaries already compounded into the stored `monthlyRent`.
  final int _totalRaises;

  factory RentSchedule(Unit unit, double percent) {
    final started = unit.startedOn;
    if (started == null) return RentSchedule._(unit, percent, null, 0);
    final startBs = bsYearMonth(started);
    // With escalation off the anchor is never consulted, so don't convert it
    // (a stray out-of-range lastRaisedOn from a restore would throw here).
    if (percent <= 0) return RentSchedule._(unit, percent, startBs, 0);
    final last = unit.lastRaisedOn;
    final anchorBs = last != null ? bsMonthOfRaiseStamp(last) : startBs;
    final coveredThroughYear =
        anchorBs.month >= startBs.month ? anchorBs.year : anchorBs.year - 1;
    return RentSchedule._(
        unit, percent, startBs, coveredThroughYear - startBs.year);
  }

  const RentSchedule._(
      this.unit, this.percent, this._startBs, this._totalRaises);

  /// True when the unit had started (or has no recorded start) by BS
  /// ([year], [month]) — months before a tenant moved in expect no rent.
  bool startedBy(int year, int month) {
    final sb = _startBs;
    if (sb == null) return true;
    return year > sb.year || (year == sb.year && month >= sb.month);
  }

  /// The rent in effect for BS [year]/[month], reconstructed by unwinding the
  /// escalations baked into the current rent. Months at or after the latest
  /// applied raise return the stored rent exactly; earlier months return the
  /// lower pre-raise rent — so a later escalation never inflates historical
  /// expected/outstanding ("phantom debt"). Falls back to the current rent
  /// when there's no start date or escalation is off; months **before** the
  /// recorded start return 0 — no rent was owed before the tenant moved in.
  int rentFor(int year, int month) {
    if (!startedBy(year, month)) return 0;
    final startBs = _startBs;
    if (percent <= 0 || startBs == null || _totalRaises <= 0) {
      return unit.monthlyRent;
    }
    // Anniversaries that had occurred by the queried month.
    final raisesByThen =
        ((month >= startBs.month ? year : year - 1) - startBs.year)
            .clamp(0, _totalRaises);
    final stepsBack = _totalRaises - raisesByThen;
    if (stepsBack <= 0) return unit.monthlyRent;
    // Unwind the rounding each step (inverse of _rentAfter's compound).
    var r = unit.monthlyRent;
    for (var i = 0; i < stepsBack; i++) {
      r = (r * 100 / (100 + percent)).round();
    }
    return r;
  }
}
