import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';

/// Covers the per-type charges intel on [PeriodSummary]:
/// [PeriodSummary.chargesBreakdown], [PeriodSummary.deductionEntries] and
/// [PeriodSummary.unitsWithCharges] — the data behind the Reports page's
/// "Charges & deductions" card. The split must obey the same post-start
/// gating as `chargesExpected`, so the card reconciles with Expected exactly.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  // Dates safely inside BS months: Jestha 2082 ≈ mid-May 2025, Asar 2082 ≈
  // late June 2025 (mirrors backup_test's anchors).
  final jestha = DateTime(2025, 5, 20); // BS 2082-2
  final asar = DateTime(2025, 6, 25); // BS 2082-3

  test('splits charges by type with distinct unit counts, and reconciles',
      () async {
    final a = await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01',
        tenantName: 'Asha',
        monthlyRent: 12000,
        startedOn: Value(jestha)));
    final b = await repo.createUnit(UnitsCompanion.insert(
        code: 'B-01',
        tenantName: 'Bibek',
        monthlyRent: 8000,
        startedOn: Value(jestha)));
    await repo.setCharges(a, 2082, 2,
        electricity: 1500, water: 300, service: 400);
    await repo.setDeduction(a, 2082, 2, amount: 700, note: 'flour');
    await repo.setCharges(b, 2082, 2, electricity: 1000);

    final s = await repo.periodSummary(2082, 2, 2);
    final bd = s.chargesBreakdown;
    expect(bd.electricity, 2500);
    expect(bd.electricityUnits, 2);
    expect(bd.water, 300);
    expect(bd.waterUnits, 1);
    expect(bd.service, 400);
    expect(bd.serviceUnits, 1);
    // The card's rows always add up to the grid's charges figure.
    expect(bd.total, s.chargesExpected);
    expect(s.unitsWithCharges, 2);

    final e = s.deductionEntries.single;
    expect(e.unit.id, a);
    expect((e.month.year, e.month.month), (2082, 2));
    expect(e.amount, 700);
    expect(e.note, 'flour');
    expect(s.deductions, 700);
  });

  test('charges and deductions before a unit started are not counted',
      () async {
    final a = await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01',
        tenantName: 'Asha',
        monthlyRent: 12000,
        startedOn: Value(jestha)));
    final c = await repo.createUnit(UnitsCompanion.insert(
        code: 'C-01',
        tenantName: 'Chandra',
        monthlyRent: 7000,
        startedOn: Value(asar))); // starts 2082-3
    await repo.setCharges(a, 2082, 2, electricity: 1500);
    // Pre-start adjustments on C: must create no intel (mirrors the phantom
    // -due rule in dueFor).
    await repo.setCharges(c, 2082, 2, electricity: 9999);
    await repo.setDeduction(c, 2082, 2, amount: 500, note: 'too early');
    await repo.setCharges(c, 2082, 3, electricity: 200);

    // Month scope on Jestha: only A's charges exist for a started unit.
    final month = await repo.periodSummary(2082, 2, 2);
    expect(month.chargesBreakdown.electricity, 1500);
    expect(month.chargesBreakdown.electricityUnits, 1);
    expect(month.chargesBreakdown.total, month.chargesExpected);
    expect(month.unitsWithCharges, 1);
    expect(month.totalSlots, 1, reason: 'C has not started by Jestha');
    expect(month.deductionEntries, isEmpty);

    // Two-month span: C's Asar charges join, its Jestha ones still do not.
    final span = await repo.periodSummary(2082, 2, 3);
    expect(span.chargesBreakdown.electricity, 1700);
    expect(span.chargesBreakdown.electricityUnits, 2);
    expect(span.chargesBreakdown.total, span.chargesExpected);
    expect(span.unitsWithCharges, 2);
    expect(span.deductionEntries, isEmpty);
  });

  test('a deduction entry is capped at the month\'s rent + charges', () async {
    final d = await repo.createUnit(UnitsCompanion.insert(
        code: 'D-01',
        tenantName: 'Devi',
        monthlyRent: 1000,
        startedOn: Value(jestha)));
    await repo.setDeduction(d, 2082, 2, amount: 5000, note: 'big barter');

    final s = await repo.periodSummary(2082, 2, 2);
    expect(s.deductionEntries.single.amount, 1000);
    expect(s.deductions, 1000);
    // A deduction-only row is not "charges entered".
    expect(s.unitsWithCharges, 0);
    expect(s.chargesBreakdown.total, 0);
  });

  test('entries across a multi-month span come out in month order', () async {
    final a = await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01',
        tenantName: 'Asha',
        monthlyRent: 12000,
        startedOn: Value(jestha)));
    await repo.setDeduction(a, 2082, 3, amount: 300, note: 'later');
    await repo.setDeduction(a, 2082, 2, amount: 200, note: 'earlier');

    final s = await repo.periodSummary(2082, 2, 3);
    expect(
      [for (final e in s.deductionEntries) (e.month.month, e.amount, e.note)],
      [(2, 200, 'earlier'), (3, 300, 'later')],
    );
  });
}
