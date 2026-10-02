import 'package:drift/drift.dart' show Value;

import 'database.dart';

/// Plain value types shared by the repository and the cloud mirror. Nothing
/// here knows about Firestore, so the repository stays free of it.

/// Identifies one syncable thing: a unit, one unit-month payment or charges
/// row, or the whole ledger. The unit is always named by its stable `cloudId`
/// (the local int id differs per device).
class SyncKey {
  static const kUnit = 'unit';
  static const kPayment = 'payment';
  static const kCharge = 'charge';
  static const kAll = 'all';

  final String kind;
  final String cloudId;
  final int year;
  final int month;

  const SyncKey.unit(this.cloudId)
      : kind = kUnit,
        year = 0,
        month = 0;
  const SyncKey.payment(this.cloudId, this.year, this.month) : kind = kPayment;
  const SyncKey.charge(this.cloudId, this.year, this.month) : kind = kCharge;

  /// Replace the whole cloud copy with this device's ledger.
  const SyncKey.all()
      : kind = kAll,
        cloudId = '',
        year = 0,
        month = 0;

  SyncKey.fromRow(PendingPush p)
      : kind = p.kind,
        cloudId = p.cloudId,
        year = p.year,
        month = p.month;

  bool get isAll => kind == kAll;

  @override
  bool operator ==(Object other) =>
      other is SyncKey &&
      other.kind == kind &&
      other.cloudId == cloudId &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(kind, cloudId, year, month);

  @override
  String toString() => isAll ? 'all' : '$kind:$cloudId:$year/$month';
}

/// Drift stores timestamps to the second; a cloud Timestamp carries more. Two
/// dates are the same stored value when they agree to the second.
bool sameInstant(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.millisecondsSinceEpoch ~/ 1000 == b.millisecondsSinceEpoch ~/ 1000;
}

/// A unit as the cloud holds it.
class RemoteUnit {
  final String cloudId;
  final String code;
  final String tenantName;
  final String businessType;
  final int monthlyRent;
  final String? phone;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? startedOn;
  final DateTime? lastRaisedOn;
  final int depositAmount;
  final bool depositRefunded;
  final DateTime? depositRefundedOn;

  const RemoteUnit({
    required this.cloudId,
    required this.code,
    required this.tenantName,
    required this.businessType,
    required this.monthlyRent,
    required this.phone,
    required this.notes,
    required this.isActive,
    required this.createdAt,
    required this.startedOn,
    required this.lastRaisedOn,
    required this.depositAmount,
    required this.depositRefunded,
    required this.depositRefundedOn,
  });

  RemoteUnit withCode(String newCode) => RemoteUnit(
        cloudId: cloudId,
        code: newCode,
        tenantName: tenantName,
        businessType: businessType,
        monthlyRent: monthlyRent,
        phone: phone,
        notes: notes,
        isActive: isActive,
        createdAt: createdAt,
        startedOn: startedOn,
        lastRaisedOn: lastRaisedOn,
        depositAmount: depositAmount,
        depositRefunded: depositRefunded,
        depositRefundedOn: depositRefundedOn,
      );

  /// True when the local row already holds exactly this state — applying it
  /// would write nothing new (so no write, and no UI refresh, is needed).
  bool matches(Unit u) =>
      u.code == code &&
      u.tenantName == tenantName &&
      u.businessType == businessType &&
      u.monthlyRent == monthlyRent &&
      u.phone == phone &&
      u.notes == notes &&
      u.isActive == isActive &&
      sameInstant(u.startedOn, startedOn) &&
      sameInstant(u.lastRaisedOn, lastRaisedOn) &&
      u.depositAmount == depositAmount &&
      u.depositRefunded == depositRefunded &&
      sameInstant(u.depositRefundedOn, depositRefundedOn);

  /// Every synced column (not the local `id`). Works as an insert and as an
  /// update; [includeCreatedAt] is for inserts only — an update never moves
  /// the row's creation time.
  UnitsCompanion toCompanion({bool includeCreatedAt = true}) => UnitsCompanion(
        cloudId: Value(cloudId),
        code: Value(code),
        tenantName: Value(tenantName),
        businessType: Value(businessType),
        monthlyRent: Value(monthlyRent),
        phone: Value(phone),
        notes: Value(notes),
        isActive: Value(isActive),
        createdAt: includeCreatedAt ? Value(createdAt) : const Value.absent(),
        startedOn: Value(startedOn),
        lastRaisedOn: Value(lastRaisedOn),
        depositAmount: Value(depositAmount),
        depositRefunded: Value(depositRefunded),
        depositRefundedOn: Value(depositRefundedOn),
      );
}

/// One unit-month payment as the cloud holds it.
class RemotePayment {
  final String unitCloudId;
  final int year;
  final int month;
  final int amount;
  final DateTime? paidOn;
  final PayMethod method;
  final String? note;

  /// The rent the payment was made against. [hasRent] is false for a document
  /// saved by an app build that predates the field — absent must leave this
  /// device's value alone.
  final bool hasRent;
  final int? rentAtPayment;

  const RemotePayment({
    required this.unitCloudId,
    required this.year,
    required this.month,
    required this.amount,
    required this.paidOn,
    required this.method,
    required this.note,
    this.hasRent = false,
    this.rentAtPayment,
  });

  SyncKey get key => SyncKey.payment(unitCloudId, year, month);

  bool matches(Payment p) =>
      p.amount == amount &&
      sameInstant(p.paidOn, paidOn) &&
      p.method == method &&
      p.note == note &&
      (!hasRent || p.rentAtPayment == rentAtPayment);

  PaymentsCompanion toCompanion(int unitId) => PaymentsCompanion(
        unitId: Value(unitId),
        year: Value(year),
        month: Value(month),
        amount: Value(amount),
        paidOn: Value(paidOn),
        method: Value(method),
        note: Value(note),
        rentAtPayment: hasRent ? Value(rentAtPayment) : const Value.absent(),
      );
}

/// One unit-month charges row as the cloud holds it. [deduction] and the note
/// are null-with-a-flag because a document saved by an app build that predates
/// the deduction simply has no such fields — and "absent" must leave this
/// device's value alone, not zero it.
class RemoteCharge {
  final String unitCloudId;
  final int year;
  final int month;
  final int electricity;
  final int water;
  final int service;
  final bool hasDeduction;
  final int deduction;
  final bool hasDeductionNote;
  final String? deductionNote;

  const RemoteCharge({
    required this.unitCloudId,
    required this.year,
    required this.month,
    required this.electricity,
    required this.water,
    required this.service,
    required this.hasDeduction,
    required this.deduction,
    required this.hasDeductionNote,
    required this.deductionNote,
  });

  SyncKey get key => SyncKey.charge(unitCloudId, year, month);

  bool matches(Charge c) =>
      c.electricity == electricity &&
      c.water == water &&
      c.service == service &&
      (!hasDeduction || c.deduction == deduction) &&
      (!hasDeductionNote || c.deductionNote == deductionNote);

  ChargesCompanion toCompanion(int unitId) => ChargesCompanion(
        unitId: Value(unitId),
        year: Value(year),
        month: Value(month),
        electricity: Value(electricity),
        water: Value(water),
        service: Value(service),
        deduction: hasDeduction ? Value(deduction) : const Value.absent(),
        deductionNote:
            hasDeductionNote ? Value(deductionNote) : const Value.absent(),
      );
}

/// What applying a batch of remote state did.
class RemoteApplyResult {
  /// Whether any local row was inserted, updated or deleted.
  final bool changed;

  /// Payments / charges whose unit is not on this device yet. For a live
  /// listener batch the caller buffers them until the unit arrives.
  final List<RemotePayment> orphanPayments;
  final List<RemoteCharge> orphanCharges;

  /// Keys the caller should now push: rows that exist only on this device
  /// (first sync), and units renamed to resolve a code collision.
  final List<SyncKey> toPush;

  const RemoteApplyResult({
    this.changed = false,
    this.orphanPayments = const [],
    this.orphanCharges = const [],
    this.toPush = const [],
  });
}
