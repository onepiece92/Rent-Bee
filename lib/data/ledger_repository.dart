import 'package:csv/csv.dart';
import 'package:drift/drift.dart';

import '../domain/bs_calendar.dart';
import '../domain/models.dart';
import 'database.dart';

/// All persistence + business logic (§4) lives here, on top of Drift.
class LedgerRepository {
  final AppDatabase db;
  LedgerRepository(this.db);

  // ---- Units ----------------------------------------------------------

  Future<List<Unit>> allUnits() => db.select(db.units).get();

  Future<int> createUnit(UnitsCompanion entry) =>
      db.into(db.units).insert(entry);

  Future<void> updateUnit(Unit unit) =>
      db.update(db.units).replace(unit);

  /// Deleting a unit cascades its payment history.
  Future<void> deleteUnit(int id) =>
      (db.delete(db.units)..where((s) => s.id.equals(id))).go();

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
    final byUnit = {for (final p in payments) p.unitId: p};

    final rows = [
      for (final s in units)
        UnitRow(unit: s, payment: byUnit[s.id]),
    ];

    rows.sort((a, b) {
      // pending (false) before paid (true)
      if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
      return a.unit.code.compareTo(b.unit.code);
    });
    return rows;
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
    await _upsertPayment(PaymentsCompanion.insert(
      unitId: unit.id,
      year: year,
      month: month,
      amount: amount ?? unit.monthlyRent,
      paidOn: Value(paidOn ?? DateTime.now()),
      method: Value(method),
      note: Value(note),
    ));
  }

  /// Insert-or-update a payment keyed by its `(unit, year, month)` unique index.
  /// Drift's [insertOnConflictUpdate] only targets the primary key (`id`), which
  /// we never supply here — so it would always INSERT and trip the unique index
  /// (SqliteException 2067). Naming the unique columns as the conflict target
  /// makes the upsert behave as documented.
  Future<void> _upsertPayment(PaymentsCompanion entry) =>
      db.into(db.payments).insert(
            entry,
            onConflict: DoUpdate(
              (_) => entry,
              target: [db.payments.unitId, db.payments.year, db.payments.month],
            ),
          );

  /// Update an existing payment record's editable fields.
  Future<void> updatePayment(Payment payment) =>
      db.update(db.payments).replace(payment);

  /// Undo: delete the row for (unit_id, year, month).
  Future<void> undo(int unitId, int year, int month) {
    return (db.delete(db.payments)
          ..where((p) =>
              p.unitId.equals(unitId) &
              p.year.equals(year) &
              p.month.equals(month)))
        .go();
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
      await (db.delete(db.charges)
            ..where((c) =>
                c.unitId.equals(unitId) &
                c.year.equals(year) &
                c.month.equals(month)))
          .go();
      return;
    }
    final entry = ChargesCompanion.insert(
      unitId: unitId,
      year: year,
      month: month,
      electricity: Value(e),
      water: Value(w),
      service: Value(s),
    );
    // Upsert on the (unit, year, month) unique index — see [_upsertPayment] for
    // why we name the target rather than using insertOnConflictUpdate.
    await db.into(db.charges).insert(
          entry,
          onConflict: DoUpdate(
            (_) => entry,
            target: [db.charges.unitId, db.charges.year, db.charges.month],
          ),
        );
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

  // ---- Reporting ---------------------------------------------------------

  Future<MonthSummary> summary(int year, int month) async {
    final units = await allUnits();
    final active = units.where((s) => s.isActive).toList();
    final payments = await paymentsForMonth(year, month);
    final rentById = {for (final s in active) s.id: s.monthlyRent};

    // Amount recorded per active unit (one row per month; fold defensively).
    final paidById = <int, int>{};
    for (final p in payments) {
      if (rentById.containsKey(p.unitId)) {
        paidById[p.unitId] = (paidById[p.unitId] ?? 0) + p.amount;
      }
    }

    final expected = active.fold<int>(0, (sum, s) => sum + s.monthlyRent);
    final collected = paidById.values.fold<int>(0, (a, b) => a + b);
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

  /// Aggregated totals for an inclusive BS month range within one year.
  /// Works for any span: a single month (start == end) behaves like
  /// [summary], a quarter (3 months), or a full year (1–12).
  Future<PeriodSummary> periodSummary(
      int year, int startMonth, int endMonth) async {
    final units = await allUnits();
    final active = units.where((s) => s.isActive).toList();
    final activeIds = {for (final s in active) s.id};
    final payments = (await paymentsForRange(year, startMonth, endMonth))
        .where((p) => activeIds.contains(p.unitId))
        .toList();

    final monthlyExpected =
        active.fold<int>(0, (sum, s) => sum + s.monthlyRent);
    final span = endMonth - startMonth + 1;

    // Per-month breakdown.
    final buckets = <MonthBucket>[];
    for (var m = startMonth; m <= endMonth; m++) {
      final collected = payments
          .where((p) => p.month == m)
          .fold<int>(0, (sum, p) => sum + p.amount);
      buckets.add(MonthBucket(
        year: year,
        month: m,
        expected: monthlyExpected,
        collected: collected,
      ));
    }

    // Amount paid per (unit, month) — partial payments included.
    final paidByUnitMonth = <int, Map<int, int>>{};
    for (final p in payments) {
      final byMonth = (paidByUnitMonth[p.unitId] ??= <int, int>{});
      byMonth[p.month] = (byMonth[p.month] ?? 0) + p.amount;
    }

    // Outstanding per unit + count of fully-settled (unit, month) slots.
    // Owed is the true shortfall (rent − paid) summed over the period, so a
    // partially-paid month contributes its remainder rather than all-or-nothing.
    final outstanding = <PeriodDebt>[];
    var paidSlots = 0;
    for (final s in active) {
      final byMonth = paidByUnitMonth[s.id] ?? const <int, int>{};
      var owed = 0;
      var monthsUnpaid = 0;
      for (var m = startMonth; m <= endMonth; m++) {
        final paid = byMonth[m] ?? 0;
        if (paid >= s.monthlyRent) {
          paidSlots++;
        } else {
          owed += s.monthlyRent - paid; // counts full or partial shortfall
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
      expected: monthlyExpected * span,
      collected: payments.fold<int>(0, (sum, p) => sum + p.amount),
      paidSlots: paidSlots,
      totalSlots: active.length * span,
      months: buckets,
      outstanding: outstanding,
    );
  }

  /// Recent paid/partial/unpaid per month for a unit, newest first. Each entry
  /// carries the amount collected plus the unit's current rent as the expected,
  /// so the UI can distinguish a full payment from a partial one. (The 6-month
  /// window is shorter than the annual escalation cycle, so current rent is the
  /// right yardstick for these months in practice.)
  Future<List<HistoryEntry>> history(int unitId, BsMonth from,
      {int months = 6}) async {
    final unit = await (db.select(db.units)
          ..where((u) => u.id.equals(unitId)))
        .getSingleOrNull();
    final expected = unit?.monthlyRent ?? 0;
    final entries = <HistoryEntry>[];
    var cursor = from;
    for (var i = 0; i < months; i++) {
      final rows = (await (db.select(db.payments)
            ..where((p) =>
                p.unitId.equals(unitId) &
                p.year.equals(cursor.year) &
                p.month.equals(cursor.month)))
          .get());
      entries.add(HistoryEntry(
        year: cursor.year,
        month: cursor.month,
        amount: rows.isNotEmpty ? rows.first.amount : 0,
        expected: expected,
      ));
      cursor = cursor.previous();
    }
    return entries;
  }

  /// CSV of the month: unit, tenant, rent, status, paid_on, method.
  Future<String> exportCsv(int year, int month) async {
    final rows = await rowsForMonth(year, month);
    final buf = StringBuffer()
      ..writeln('code,tenant,rent,status,paid_on,method,amount');
    for (final r in rows) {
      buf.writeln(_csvRow(r));
    }
    return buf.toString();
  }

  /// CSV across an inclusive BS month range, one row per (unit, month),
  /// with a leading month column. Single-month ranges still work.
  Future<String> exportCsvRange(
      int year, int startMonth, int endMonth) async {
    final buf = StringBuffer()
      ..writeln('month,code,tenant,rent,status,paid_on,method,amount');
    for (var m = startMonth; m <= endMonth; m++) {
      final rows = await rowsForMonth(year, m);
      final monthLabel = BsCalendar.label(m);
      for (final r in rows) {
        buf.writeln(_csvRow(r, monthLabel: monthLabel));
      }
    }
    return buf.toString();
  }

  /// One CSV data row for a unit's month. [monthLabel], when given, prepends the
  /// leading `month` column used by range exports; omit it for single-month
  /// exports. Column order matches the headers written by the callers.
  static String _csvRow(UnitRow r, {String? monthLabel}) {
    final p = r.payment;
    return [
      if (monthLabel != null) _csv(monthLabel),
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
      final rent = int.tryParse(cell(iRent));

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
      final amount = int.tryParse(cell(iAmount));
      final monthNum = _monthNumber(cell(iMonth));
      if (monthNum != null &&
          amount != null &&
          amount > 0 &&
          status != 'pending') {
        await _upsertPayment(PaymentsCompanion.insert(
          unitId: unitId,
          year: int.tryParse(cell(iYear)) ?? fallbackYear,
          month: monthNum,
          amount: amount,
          paidOn: Value(DateTime.tryParse(cell(iPaidOn))),
          method: Value(_method(cell(iMethod))),
        ));
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

  static PayMethod _method(String s) {
    for (final m in PayMethod.values) {
      if (m.name.toLowerCase() == s.toLowerCase()) return m;
    }
    return PayMethod.cash;
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
    await eraseAll();
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
      final id = await createUnit(UnitsCompanion.insert(
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

  /// Deletes every payment and unit. Irreversible.
  Future<void> eraseAll() async {
    await db.delete(db.payments).go();
    await db.delete(db.units).go();
  }
}
