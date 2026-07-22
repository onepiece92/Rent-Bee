import '../data/database.dart';

/// Payment state of a unit for a given month.
enum PayStatus { pending, partial, paid }

/// A unit joined with its payment (if any) for the selected month.
class UnitRow {
  final Unit unit;
  final Payment? payment; // null = nothing recorded this month

  const UnitRow({required this.unit, this.payment});

  /// Amount recorded for this month so far (0 if no payment row).
  int get paidAmount => payment?.amount ?? 0;

  /// Remaining due against the unit's current rent, floored at 0.
  int get remaining =>
      (unit.monthlyRent - paidAmount).clamp(0, unit.monthlyRent);

  /// pending (nothing/zero) · partial (some, < rent) · paid (>= rent).
  PayStatus get status {
    if (payment == null || paidAmount <= 0) return PayStatus.pending;
    if (paidAmount >= unit.monthlyRent) return PayStatus.paid;
    return PayStatus.partial;
  }

  /// True only when the month is settled in full.
  bool get isPaid => status == PayStatus.paid;
  bool get isPartial => status == PayStatus.partial;
}

/// Dashboard totals for a selected (year, month).
class MonthSummary {
  final int expected; // sum of monthly_rent over active units started by then
  final int collected; // sum of ALL payments.amount for the month
  final int paidCount; // active units settled in full this month
  final int partialCount; // active units with a partial payment this month
  final int activeCount; // active units total

  const MonthSummary({
    required this.expected,
    required this.collected,
    required this.paidCount,
    this.partialCount = 0,
    required this.activeCount,
  });

  /// Outstanding amount, floored at 0 — a unit that overpaid (e.g. rent was
  /// lowered after a higher payment was captured) never shows negative pending.
  int get pending => (expected - collected).clamp(0, expected);

  /// Collected fraction 0.0–1.0 (guards divide-by-zero).
  double get progress => expected == 0 ? 0 : (collected / expected).clamp(0, 1);

  int get percent => (progress * 100).round();
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

  const MonthBucket({
    required this.year,
    required this.month,
    required this.expected,
    required this.collected,
  });

  int get pending => (expected - collected).clamp(0, expected);

  double get progress =>
      expected == 0 ? 0 : (collected / expected).clamp(0, 1);
}

/// One unit's unpaid total across a multi-month period.
class PeriodDebt {
  final Unit unit;
  final int amountOwed; // unpaid months × current monthly_rent
  final int monthsUnpaid;

  const PeriodDebt({
    required this.unit,
    required this.amountOwed,
    required this.monthsUnpaid,
  });
}

/// Aggregated totals for a period of one or more BS months (the unifying
/// type behind month/quarter/year reports). For a single month it carries
/// exactly one [months] bucket and is equivalent to a [MonthSummary].
///
/// `expected` is `months × current active rent` — rent changes over time are
/// not back-dated, matching the existing month [MonthSummary] definition.
class PeriodSummary {
  final int expected; // sum of per-month expected across the period
  final int collected; // sum of ALL payments in the period (incl. vacated)
  final int paidSlots; // (unit, month) pairs paid
  final int totalSlots; // activeCount × month span
  final List<MonthBucket> months; // per-month breakdown, in order
  final List<PeriodDebt> outstanding; // units still owing, largest first

  const PeriodSummary({
    required this.expected,
    required this.collected,
    required this.paidSlots,
    required this.totalSlots,
    required this.months,
    required this.outstanding,
  });

  int get pending => (expected - collected).clamp(0, expected);

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

  /// Rent expected for this month — lets the UI tell partial from full.
  final int expected;

  const HistoryEntry({
    required this.year,
    required this.month,
    required this.amount,
    required this.expected,
  });

  /// Fraction of the expected rent collected, clamped to 0..1.
  double get progress => expected > 0
      ? (amount / expected).clamp(0, 1).toDouble()
      : (amount > 0 ? 1 : 0);

  /// Paid in full — the collected amount covers the expected rent.
  bool get isPaid => amount > 0 && amount >= expected;

  /// Something was collected, but less than the expected rent.
  bool get isPartial => amount > 0 && amount < expected;
}
