import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/bs_calendar.dart';
import '../domain/models.dart';
import 'database.dart';
import 'firestore_sync_service.dart';

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
    sync?.upsertUnit(unit);
    return id;
  }

  Future<void> updateUnit(Unit unit) async {
    await db.update(db.units).replace(unit);
    sync?.upsertUnit(unit);
  }

  /// Deleting a unit cascades its payment history.
  Future<void> deleteUnit(int id) async {
    final unit = await (db.select(db.units)..where((u) => u.id.equals(id)))
        .getSingleOrNull();
    await (db.delete(db.units)..where((s) => s.id.equals(id))).go();
    final cloudId = unit?.cloudId;
    if (cloudId != null) sync?.deleteUnit(cloudId);
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
      final anchorBs = bsYearMonth(u.lastRaisedOn ?? u.startedOn!);

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
      // Stamp the latest applied anniversary (1st of the BS start month).
      final stamp = adForBsMonthStart(latestAnniversaryYear, startBs.month);
      updated.add(u.copyWith(monthlyRent: rent, lastRaisedOn: Value(stamp)));
    }

    if (updated.isNotEmpty) {
      await db.batch((b) {
        for (final u in updated) {
          b.replace(db.units, u);
        }
      });
      sync?.upsertUnits(updated);
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
  Future<List<UnitRow>> rowsForMonth(int year, int month) async {
    final units = await allUnits();
    final payments = await paymentsForMonth(year, month);
    return _rowsFrom(units, payments);
  }

  /// Build sorted [UnitRow]s from already-loaded units + that month's payments.
  List<UnitRow> _rowsFrom(List<Unit> units, List<Payment> payments) {
    final byUnit = {for (final p in payments) p.unitId: p};
    final rows = [
      for (final s in units) UnitRow(unit: s, payment: byUnit[s.id]),
    ];
    rows.sort((a, b) {
      // active before vacant, so a moved-out unit never crowds the working
      // pending list; within active: pending (false) before paid (true)
      if (a.unit.isActive != b.unit.isActive) return a.unit.isActive ? -1 : 1;
      if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
      return a.unit.code.compareTo(b.unit.code);
    });
    return rows;
  }

  /// Rows **and** summary for a month from a single units+payments load — used
  /// by the provider's refresh so a mark-paid/undo/edit re-queries the DB once
  /// (2 queries) instead of via rowsForMonth + summary (4 queries).
  Future<({List<UnitRow> rows, MonthSummary summary})> monthView(
      int year, int month) async {
    final units = await allUnits();
    final payments = await paymentsForMonth(year, month);
    return (
      rows: _rowsFrom(units, payments),
      summary: _summaryFrom(units, payments, year, month),
    );
  }

  /// True when [unit] had already started (or has no recorded start date) by
  /// BS ([year], [month]) — months before a tenant moved in expect no rent.
  static bool _startedBy(Unit unit, int year, int month) {
    final started = unit.startedOn;
    if (started == null) return true;
    final sb = bsYearMonth(started);
    return year > sb.year || (year == sb.year && month >= sb.month);
  }

  /// Mark paid: upsert a payment row. amount defaults to the unit's
  /// current monthly_rent (captured per record), paid_on = today, method = cash.
  Future<void> markPaid(
    Unit unit,
    int year,
    int month, {
    int? amount,
    DateTime? paidOn,
    PayMethod method = PayMethod.cash,
    String? note,
  }) async {
    await _upsertPaymentLocal(PaymentsCompanion.insert(
      unitId: unit.id,
      year: year,
      month: month,
      amount: amount ?? unit.monthlyRent,
      paidOn: Value(paidOn ?? DateTime.now()),
      method: Value(method),
      note: Value(note),
    ));
    await _pushPaymentFor(unit.id, year, month);
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

  /// Re-reads a payment + its unit's cloudId and pushes it to the cloud mirror.
  Future<void> _pushPaymentFor(int unitId, int year, int month) async {
    if (sync == null) return;
    final cloudId = await cloudIdForUnitId(unitId);
    if (cloudId == null) return;
    final p = await (db.select(db.payments)
          ..where((x) =>
              x.unitId.equals(unitId) &
              x.year.equals(year) &
              x.month.equals(month)))
        .getSingleOrNull();
    if (p != null) sync!.upsertPayment(p, cloudId);
  }

  /// Update an existing payment record's editable fields.
  Future<void> updatePayment(Payment payment) async {
    await db.update(db.payments).replace(payment);
    await _pushPaymentFor(payment.unitId, payment.year, payment.month);
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
    if (cloudId != null) sync?.deletePayment(cloudId, year, month);
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

  /// Insert-or-update this month's electricity/water/service charges for a unit
  /// (negatives floored at 0). When all three are 0 the row is deleted instead,
  /// keeping the table sparse so "no charges" and "all zero" read the same.
  Future<void> setCharges(
    int unitId,
    int year,
    int month, {
    int electricity = 0,
    int water = 0,
    int service = 0,
  }) async {
    final e = electricity < 0 ? 0 : electricity;
    final w = water < 0 ? 0 : water;
    final s = service < 0 ? 0 : service;
    if (e == 0 && w == 0 && s == 0) {
      await _deleteChargeLocal(unitId, year, month);
      // Mirror the delete to the cloud, else a stale charge resurrects on
      // another device.
      final cloudId = await cloudIdForUnitId(unitId);
      if (cloudId != null) sync?.deleteCharge(cloudId, year, month);
      return;
    }
    await _upsertChargeLocal(ChargesCompanion.insert(
      unitId: unitId,
      year: year,
      month: month,
      electricity: Value(e),
      water: Value(w),
      service: Value(s),
    ));
    await _pushChargeFor(unitId, year, month);
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

  Future<void> _pushChargeFor(int unitId, int year, int month) async {
    if (sync == null) return;
    final cloudId = await cloudIdForUnitId(unitId);
    if (cloudId == null) return;
    final c = await (db.select(db.charges)
          ..where((x) =>
              x.unitId.equals(unitId) &
              x.year.equals(year) &
              x.month.equals(month)))
        .getSingleOrNull();
    if (c != null) sync!.upsertCharge(c, cloudId);
  }

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

  // ---- Reporting ---------------------------------------------------------

  Future<MonthSummary> summary(int year, int month) async {
    final units = await allUnits();
    final payments = await paymentsForMonth(year, month);
    return _summaryFrom(units, payments, year, month);
  }

  /// Dashboard totals from already-loaded units + that month's payments.
  /// `expected` counts active units that had **started** by ([year], [month]) —
  /// a tenant who moved in later owes nothing for earlier months. `collected`
  /// sums every payment recorded for the month, including from since-vacated
  /// units, so money actually received is never understated.
  MonthSummary _summaryFrom(
      List<Unit> units, List<Payment> payments, int year, int month) {
    final active = units
        .where((s) => s.isActive && _startedBy(s, year, month))
        .toList();
    final rentById = {for (final s in active) s.id: s.monthlyRent};

    // Amount recorded per active unit (one row per month; fold defensively).
    final paidById = <int, int>{};
    for (final p in payments) {
      if (rentById.containsKey(p.unitId)) {
        paidById[p.unitId] = (paidById[p.unitId] ?? 0) + p.amount;
      }
    }

    final expected = active.fold<int>(0, (sum, s) => sum + s.monthlyRent);
    final collected = payments.fold<int>(0, (sum, p) => sum + p.amount);
    var paidCount = 0;
    var partialCount = 0;
    paidById.forEach((id, amt) {
      if (amt <= 0) return;
      if (amt >= (rentById[id] ?? 0)) {
        paidCount++;
      } else {
        partialCount++;
      }
    });

    return MonthSummary(
      expected: expected,
      collected: collected,
      paidCount: paidCount,
      partialCount: partialCount,
      activeCount: active.length,
    );
  }

  /// The rent that was in effect for [unit] during BS [year]/[month],
  /// reconstructed by unwinding the [percent]% anniversary escalations baked
  /// into its current rent. Months at or after the latest applied raise return
  /// the stored rent exactly; earlier months return the lower pre-raise rent —
  /// so a later escalation never inflates historical expected/outstanding
  /// ("phantom debt"). Falls back to the current rent when there's no start
  /// date or escalation is off. Months **before** the unit's recorded start
  /// return 0 — no rent was owed before the tenant moved in.
  static int rentInEffect(Unit unit, int year, int month, double percent) {
    if (!_startedBy(unit, year, month)) return 0;
    final started = unit.startedOn;
    if (percent <= 0 || started == null) return unit.monthlyRent;
    final startBs = bsYearMonth(started);
    final anchorBs = bsYearMonth(unit.lastRaisedOn ?? started);
    // Anniversaries already compounded into the stored rent.
    final coveredThroughYear =
        anchorBs.month >= startBs.month ? anchorBs.year : anchorBs.year - 1;
    final totalRaises = coveredThroughYear - startBs.year;
    if (totalRaises <= 0) return unit.monthlyRent;
    // Anniversaries that had occurred by the queried month.
    final raisesByThen =
        ((month >= startBs.month ? year : year - 1) - startBs.year)
            .clamp(0, totalRaises);
    final stepsBack = totalRaises - raisesByThen;
    if (stepsBack <= 0) return unit.monthlyRent;
    // Unwind the rounding each step (inverse of _rentAfter's compound).
    var r = unit.monthlyRent;
    for (var i = 0; i < stepsBack; i++) {
      r = (r * 100 / (100 + percent)).round();
    }
    return r;
  }

  /// Aggregated totals for an inclusive BS month range within one year.
  /// Works for any span: a single month (start == end) behaves like
  /// [summary], a quarter (3 months), or a full year (1–12). [percent] is the
  /// active escalation rate, used to price historical months at the rent that
  /// applied then (see [rentInEffect]).
  Future<PeriodSummary> periodSummary(
      int year, int startMonth, int endMonth,
      {double percent = 0}) async {
    final units = await allUnits();
    final active = units.where((s) => s.isActive).toList();
    // ALL payments in range — including from since-vacated units, so the
    // period's `collected` reflects money actually received. Expected and
    // per-unit outstanding still cover active units only.
    final payments = await paymentsForRange(year, startMonth, endMonth);

    final span = endMonth - startMonth + 1;

    // Amount paid per (unit, month) — partial payments included.
    final paidByUnitMonth = <int, Map<int, int>>{};
    for (final p in payments) {
      final byMonth = (paidByUnitMonth[p.unitId] ??= <int, int>{});
      byMonth[p.month] = (byMonth[p.month] ?? 0) + p.amount;
    }

    // Per-month breakdown — expected uses the rent in effect THAT month for
    // each unit, so a later escalation can't inflate a historical month.
    final buckets = <MonthBucket>[];
    var totalExpected = 0;
    for (var m = startMonth; m <= endMonth; m++) {
      final monthExpected = active.fold<int>(
          0, (sum, s) => sum + rentInEffect(s, year, m, percent));
      final collected = payments
          .where((p) => p.month == m)
          .fold<int>(0, (sum, p) => sum + p.amount);
      buckets.add(MonthBucket(
        year: year,
        month: m,
        expected: monthExpected,
        collected: collected,
      ));
      totalExpected += monthExpected;
    }

    // Outstanding per unit + count of fully-settled (unit, month) slots.
    // Owed is the true shortfall (rent-in-effect − paid) summed over the
    // period, so a month paid in full at the old rate isn't re-charged after a
    // raise, and a partial month contributes only its remainder.
    final outstanding = <PeriodDebt>[];
    var paidSlots = 0;
    for (final s in active) {
      final byMonth = paidByUnitMonth[s.id] ?? const <int, int>{};
      var owed = 0;
      var monthsUnpaid = 0;
      for (var m = startMonth; m <= endMonth; m++) {
        final due = rentInEffect(s, year, m, percent);
        final paid = byMonth[m] ?? 0;
        if (paid >= due) {
          paidSlots++;
        } else {
          owed += due - paid; // full or partial shortfall at the month's rate
          monthsUnpaid++;
        }
      }
      if (owed > 0) {
        outstanding.add(PeriodDebt(
          unit: s,
          amountOwed: owed,
          monthsUnpaid: monthsUnpaid,
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
      paidSlots: paidSlots,
      totalSlots: active.length * span,
      months: buckets,
      outstanding: outstanding,
    );
  }

  /// Recent paid/partial/unpaid per month for a unit, newest first. Each entry
  /// carries the amount collected plus the rent **in effect that month** (see
  /// [rentInEffect], using the [percent] escalation rate) as the expected — so
  /// a month fully paid at the pre-raise rate still reads as paid after an
  /// anniversary raise lands, instead of flipping to partial.
  Future<List<HistoryEntry>> history(int unitId, BsMonth from,
      {int months = 6, double percent = 0}) async {
    final unit = await (db.select(db.units)
          ..where((u) => u.id.equals(unitId)))
        .getSingleOrNull();
    if (unit == null) return const [];

    // One query for all of this unit's payments (bounded — a few dozen rows),
    // then fill the window in memory instead of a SELECT per month (N+1).
    final paid = await (db.select(db.payments)
          ..where((p) => p.unitId.equals(unitId)))
        .get();
    final amountByMonth = {for (final p in paid) (p.year, p.month): p.amount};

    final entries = <HistoryEntry>[];
    var cursor = from;
    for (var i = 0; i < months; i++) {
      entries.add(HistoryEntry(
        year: cursor.year,
        month: cursor.month,
        amount: amountByMonth[(cursor.year, cursor.month)] ?? 0,
        expected: rentInEffect(unit, cursor.year, cursor.month, percent),
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
  Future<String> exportCsvRange(
      int year, int startMonth, int endMonth) async {
    // One units load + one ranged payments query (was rowsForMonth per month —
    // e.g. 24 queries for a full year). The `year` column makes the round-trip
    // year-safe: importCsv reads it instead of falling back to the open year.
    final units = [...await allUnits()]
      ..sort((a, b) => a.code.compareTo(b.code));
    final payments = await paymentsForRange(year, startMonth, endMonth);
    final byKey = {for (final p in payments) (p.unitId, p.month): p};
    final buf = StringBuffer()
      ..writeln('month,year,code,tenant,rent,status,paid_on,method,amount');
    for (var m = startMonth; m <= endMonth; m++) {
      final monthLabel = BsCalendar.label(m);
      for (final s in units) {
        final r = UnitRow(unit: s, payment: byKey[(s.id, m)]);
        buf.writeln(_csvRow(r, monthLabel: monthLabel, year: year));
      }
    }
    return buf.toString();
  }

  /// One CSV data row for a unit's month. [monthLabel]/[year], when given,
  /// prepend the leading `month`,`year` columns used by range exports; omit them
  /// for single-month exports. Column order matches the headers the callers write.
  static String _csvRow(UnitRow r, {String? monthLabel, int? year}) {
    final p = r.payment;
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
  /// tenant, rent, month, status, paid_on, method, amount, year. The BS year
  /// comes from a `year` column if present, otherwise [fallbackYear] (the
  /// export omits year, so single-year files import into the selected year).
  /// Existing data not referenced by the file is left untouched. Returns the
  /// number of units added/updated and payments written.
  Future<({int unitsAdded, int unitsUpdated, int payments})> importCsv(
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
        iAmount = col('amount');
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

      // Upsert the payment for settled/partial rows carrying an amount.
      final status = cell(iStatus).toLowerCase();
      final amount = _parseInt(cell(iAmount));
      final monthNum = _monthNumber(cell(iMonth));
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
        await _pushPaymentFor(unitId, pYear, monthNum);
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
  Future<String> exportBackupJson({DateTime? exportedAt}) async {
    final units = await allUnits();
    final payments = await allPayments();
    final charges = await allCharges();
    final data = <String, dynamic>{
      'app': 'rent-bee',
      'type': 'backup',
      'formatVersion': backupFormatVersion,
      'schemaVersion': db.schemaVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'units': [for (final u in units) _unitToBackup(u)],
      'payments': [for (final p in payments) _paymentToBackup(p)],
      'charges': [for (final c in charges) _chargeToBackup(c)],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Restores an [exportBackupJson] snapshot, **replacing all current data**.
  /// Atomic: the whole local rebuild runs in one drift transaction, so a
  /// malformed row throws and rolls back, leaving the existing ledger intact.
  /// Unit `cloudId`s are preserved so a restored ledger keeps its cross-device
  /// identity; local int ids are reassigned and payment/charge rows remapped to
  /// the new ids. With sync on, the cloud copy is replaced in one sequenced
  /// erase-then-write afterwards (mirrors [generateDemoData]). Returns the
  /// number of rows written.
  Future<({int units, int payments, int charges})> importBackupJson(
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
      return (units: idMap.length, payments: pCount, charges: cCount);
    });

    // One sequenced cloud replace for the whole restored dataset.
    if (sync != null) {
      final allU = await allUnits();
      final map = {
        for (final u in allU)
          if (u.cloudId != null) u.id: u.cloudId!,
      };
      sync!.replaceAllCloud(
        units: allU,
        payments: await allPayments(),
        charges: await allCharges(),
        cloudIdByUnitId: map,
      );
    }
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
        createdAt: Value(_date(m['createdAt']) ?? DateTime.now()),
      );

  /// True when a cloud-sync session is live (signed-in, non-guest owner).
  bool get cloudSyncActive => sync != null;

  /// Forces a full re-push of the whole local ledger to the cloud in one
  /// sequenced erase-then-write. Used by the manual "Back up to cloud now"
  /// action (and after a long offline stretch); a no-op when not signed in.
  Future<void> resyncAllToCloud() async {
    final s = sync;
    if (s == null) return;
    final units = await allUnits();
    s.replaceAllCloud(
      units: units,
      payments: await allPayments(),
      charges: await allCharges(),
      cloudIdByUnitId: {
        for (final u in units)
          if (u.cloudId != null) u.id: u.cloudId!,
      },
    );
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
        lastRaisedOn: Value(adForBsMonthStart(startYear + anniv, startMonth)),
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
          payments.add(PaymentsCompanion.insert(
            unitId: ids[i],
            year: cursor.year,
            month: cursor.month,
            amount: _rentAfter(bases[i], pct, anniv < 0 ? 0 : anniv),
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
    if (sync != null) {
      final allU = await allUnits();
      final map = {
        for (final u in allU)
          if (u.cloudId != null) u.id: u.cloudId!,
      };
      sync!.replaceAllCloud(
        units: allU,
        payments: await allPayments(),
        charges: await allCharges(),
        cloudIdByUnitId: map,
      );
    }
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
    sync?.eraseAllCloud();
  }

  /// Drift-only wipe (no cloud push). Used by the sync owner-guard when a
  /// different owner signs in on this device.
  Future<void> eraseAllLocal() async {
    await db.delete(db.payments).go();
    await db.delete(db.units).go();
  }

  // ---- Cloud sync: drift-only apply path (called by FirestoreSyncService;
  //      these NEVER push, which is what makes echo loops impossible) ---------

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
