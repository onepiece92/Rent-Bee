import '../data/database.dart';
import 'bs_calendar.dart';

/// Payment state of a unit for a given month.
enum PayStatus { pending, partial, paid }

/// Total actually due for a month: [rent] plus the month's utility/service
/// [charges] (electricity + water + service), less the landlord's [deduction]
/// (goods or services taken from the tenant's shop against rent).
/// Never negative: a deduction larger than rent + charges reads as 0 due, and
/// a negative rent or charge (possible via a restored backup or cloud doc,
/// which don't floor them) is treated as 0 rather than tripping `clamp`'s
/// bounds check.
int netDue(int rent, int deduction, {int charges = 0}) {
  final due = rent +
      (charges < 0 ? 0 : charges) -
      (deduction < 0 ? 0 : deduction);
  return due < 0 ? 0 : due;
}

/// Whether a month is settled: the cash [paid] covers the [due], or nothing
/// was due because the [deduction] alone covered the rent. A month with no
/// rent, no cash and no deduction is *not* settled — there is nothing to show
/// as paid. The single rule behind [UnitRow.status], [HistoryEntry.isPaid]
/// and the month summary's paid count.
bool settles({required int paid, required int due, required int deduction}) =>
    paid >= due && (paid > 0 || deduction > 0);

/// A unit joined with its payment (if any) for the selected month.
class UnitRow {
  final Unit unit;
  final Payment? payment; // null = nothing recorded this month

  /// This month's utility/service charges total (electricity + water +
  /// service, 0 = none). See [netDue].
  final int charges;

  /// Landlord's deduction against this month's rent (0 = none). See [netDue].
  final int deduction;

  /// The rent that applies to THIS month, when it differs from the unit's
  /// current rent: the rent a recorded payment was made against, or the rent
  /// in effect back then (before a later raise). Null = the current rent.
  final int? rent;

  /// False for a month before the tenant moved in: nothing was owed, so the
  /// row offers nothing to collect.
  final bool started;

  const UnitRow({
    required this.unit,
    this.payment,
    this.charges = 0,
    this.deduction = 0,
    this.rent,
    this.started = true,
  });

  /// Amount recorded for this month so far (0 if no payment row).
  int get paidAmount => payment?.amount ?? 0;

  /// This month's rent (see [rent]).
  int get monthRent => rent ?? unit.monthlyRent;

  /// Cash due this month: rent + charges − deduction, floored at 0. Nothing
  /// is due for a month before the tenancy started.
  int get totalDue =>
      started ? netDue(monthRent, deduction, charges: charges) : 0;

  /// Remaining due against this month's [totalDue], floored at 0.
  int get remaining => (totalDue - paidAmount).clamp(0, totalDue);

  /// pending (nothing/zero) · partial (some, < due) · paid — see [settles].
  PayStatus get status {
    if (settles(paid: paidAmount, due: totalDue, deduction: deduction)) {
      return PayStatus.paid;
    }
    return paidAmount <= 0 ? PayStatus.pending : PayStatus.partial;
  }

  /// True only when the month is settled in full.
  bool get isPaid => status == PayStatus.paid;
  bool get isPartial => status == PayStatus.partial;
}

/// Dashboard totals for a selected (year, month).
class MonthSummary {
  final int expected; // Σ (rent + charges − deduction) over active units started by then
  final int collected; // sum of ALL payments.amount for the month
  final int paidCount; // active units settled in full this month
  final int partialCount; // active units with a partial payment this month
  final int activeCount; // active units total

  /// What is still owed: each active unit's own shortfall (due − paid, never
  /// negative), added up. Null only for summaries built without it.
  final int? outstanding;

  const MonthSummary({
    required this.expected,
    required this.collected,
    required this.paidCount,
    this.partialCount = 0,
    required this.activeCount,
    this.outstanding,
  });

  /// Outstanding amount. Per-unit shortfalls, NOT `expected − collected`:
  /// `collected` also counts money from since-vacated units and overpayments,
  /// which would hide another unit's unpaid rent (one tenant owing 10,000 and
  /// a vacated one having paid 10,000 used to read as "nothing pending" —
  /// buglog B06).
  int get pending => outstanding ?? (expected - collected).clamp(0, expected);

  /// Collected fraction 0.0–1.0 (guards divide-by-zero).
  double get progress => expected == 0 ? 0 : (collected / expected).clamp(0, 1);

  int get percent => (progress * 100).round();

  // Value equality, so a widget selecting the summary rebuilds only when a
  // figure actually changed — not on every reload that produced the same one.
  @override
  bool operator ==(Object other) =>
      other is MonthSummary &&
      other.expected == expected &&
      other.collected == collected &&
      other.paidCount == paidCount &&
      other.partialCount == partialCount &&
      other.activeCount == activeCount &&
      other.outstanding == outstanding;

  @override
  int get hashCode => Object.hash(
      expected, collected, paidCount, partialCount, activeCount, outstanding);
}

/// Reporting granularity for the Reports screen.
enum ReportScope { month, quarter, year }

extension ReportScopeLabel on ReportScope {
  String get label => switch (this) {
        ReportScope.month => 'Month',
        ReportScope.quarter => 'Quarter',
        ReportScope.year => 'Year',
      };

  /// Number of BS months this scope spans.
  int get months => switch (this) {
        ReportScope.month => 1,
        ReportScope.quarter => 3,
        ReportScope.year => 12,
      };
}

/// One BS month's totals inside a [PeriodSummary] breakdown.
class MonthBucket {
  final int year;
  final int month; // 1–12
  final int expected;
  final int collected;

  /// Per-unit shortfalls for this month, added up (see [MonthSummary.pending]).
  final int? outstanding;

  const MonthBucket({
    required this.year,
    required this.month,
    required this.expected,
    required this.collected,
    this.outstanding,
  });

  int get pending => outstanding ?? (expected - collected).clamp(0, expected);

  double get progress =>
      expected == 0 ? 0 : (collected / expected).clamp(0, 1);
}

/// One unit's unpaid total across a multi-month period.
class PeriodDebt {
  final Unit unit;
  final int amountOwed; // the shortfalls of the unpaid months, added up
  final int monthsUnpaid;

  /// The months this unit still owes for, oldest first — so the UI can act
  /// on (and a reminder can name) the right month, not just "the period".
  final List<BsMonth> unpaidMonths;

  const PeriodDebt({
    required this.unit,
    required this.amountOwed,
    required this.monthsUnpaid,
    this.unpaidMonths = const [],
  });
}

/// Aggregated totals for a period of one or more BS months (the unifying
/// type behind month/quarter/year reports). For a single month it carries
/// exactly one [months] bucket and is equivalent to a [MonthSummary].
///
/// `expected` prices each month at the rent in effect then plus its utility
/// charges, net of its deduction — rent changes over time are not back-dated,
/// matching the month [MonthSummary] definition.
///
/// [rentExpected], [chargesExpected] and [deductions] split `expected` into
/// its income components. Each month's deduction is capped at that month's
/// rent + charges (mirroring `netDue`'s floor), so the identity
/// `expected == rentExpected + chargesExpected − deductions` holds exactly.
class PeriodSummary {
  final int expected; // sum of per-month expected across the period
  final int collected; // sum of ALL payments in the period (incl. vacated)
  final int rentExpected; // the rent share of expected
  final int chargesExpected; // the utility-charges share of expected
  final int deductions; // total deducted (capped per month, see above)
  final int paidSlots; // (unit, month) pairs paid
  final int totalSlots; // (unit, month) pairs actually owed (post-start only)
  final List<MonthBucket> months; // per-month breakdown, in order
  final List<PeriodDebt> outstanding; // units still owing, largest first

  const PeriodSummary({
    required this.expected,
    required this.collected,
    this.rentExpected = 0,
    this.chargesExpected = 0,
    this.deductions = 0,
    required this.paidSlots,
    required this.totalSlots,
    required this.months,
    required this.outstanding,
  });

  /// What is still owed across the period: the [outstanding] units' own
  /// shortfalls, not `expected − collected` (see [MonthSummary.pending]).
  int get pending => outstanding.fold(0, (sum, d) => sum + d.amountOwed);

  double get progress =>
      expected == 0 ? 0 : (collected / expected).clamp(0, 1);

  int get percent => (progress * 100).round();
}

/// The landlord's standing deposit liability — refundable money still held.
///
/// `held` is deposits on **active** tenancies (normal liability); `dueBack` is
/// deposits on **vacated** units not yet refunded (money that should already
/// have been returned). `total` is the full amount owed back to tenants.
class DepositLiability {
  final int held; // active tenants' deposits still held
  final int dueBack; // vacated, not-yet-refunded deposits
  final int heldCount; // active units holding a deposit
  final int dueBackCount; // vacated units still owing a refund

  const DepositLiability({
    this.held = 0,
    this.dueBack = 0,
    this.heldCount = 0,
    this.dueBackCount = 0,
  });

  /// Total refundable money the landlord is on the hook for.
  int get total => held + dueBack;

  /// Whether any deposit is overdue for refund (a vacated unit not refunded).
  bool get hasOverdue => dueBack > 0;
}

/// One entry in a unit's recent month history.
class HistoryEntry {
  final int year;
  final int month;

  /// Amount collected for this month (0 if nothing recorded).
  final int amount;

  /// Total expected for this month — lets the UI tell partial from full.
  /// Already rent + charges, net of any [deduction] (see [netDue]).
  final int expected;

  /// Landlord's deduction against this month's rent (0 = none). Only consulted
  /// to tell "fully deducted, nothing to collect" from "not started yet" when
  /// [expected] is 0.
  final int deduction;

  const HistoryEntry({
    required this.year,
    required this.month,
    required this.amount,
    required this.expected,
    this.deduction = 0,
  });

  /// Fraction of the expected rent collected, clamped to 0..1.
  double get progress => expected > 0
      ? (amount / expected).clamp(0, 1).toDouble()
      : (amount > 0 ? 1 : 0);

  /// Paid in full — see [settles].
  bool get isPaid =>
      settles(paid: amount, due: expected, deduction: deduction);

  /// Something was collected, but less than the expected rent.
  bool get isPartial => amount > 0 && amount < expected;
}
