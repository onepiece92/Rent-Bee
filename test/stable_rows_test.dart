import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/state/ledger_provider.dart';

/// Marking a unit paid must not move another tenant under the finger: the
/// natural order is pending-first, so the paid row used to drop down the list
/// (or leave the Pending filter) and a double-tap marked the next unit paid
/// too. (buglog B08.) And a failed load must say so instead of spinning
/// forever. (buglog B10.)
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;
  late LedgerProvider ledger;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    for (final code in ['A-01', 'A-02', 'A-03']) {
      await repo.createUnit(UnitsCompanion.insert(
          code: code, tenantName: 'Tenant $code', monthlyRent: 10000));
    }
    ledger = LedgerProvider(repo, initialMonth: const BsMonth(2082, 2));
    await ledger.init();
  });
  tearDown(() => db.close());

  List<String> codes() => [for (final r in ledger.visibleRows) r.unit.code];

  test('mark paid keeps every row where it was', () async {
    expect(codes(), ['A-01', 'A-02', 'A-03']);
    await ledger.markPaid(ledger.visibleRows.first.unit);
    expect(codes(), ['A-01', 'A-02', 'A-03'],
        reason: 'A-01 used to drop to the bottom, sliding A-02 under the tap');
    expect(ledger.visibleRows.first.isPaid, isTrue);

    // A real reload (pull to refresh, month switch) re-sorts: pending first.
    await ledger.refresh();
    expect(codes(), ['A-02', 'A-03', 'A-01']);
  });

  test('undo keeps the order too', () async {
    await ledger.markPaid(ledger.visibleRows.last.unit);
    await ledger.refresh();
    expect(codes(), ['A-01', 'A-02', 'A-03']);
    await ledger.markPaid(ledger.visibleRows.first.unit);
    await ledger.undo(ledger.visibleRows.first.unit.id);
    expect(codes(), ['A-01', 'A-02', 'A-03']);
  });

  test('in the Pending filter the paid row stays put until the filter changes',
      () async {
    ledger.setFilter(LedgerFilter.pending);
    await ledger.markPaid(ledger.visibleRows.first.unit);
    expect(codes(), ['A-01', 'A-02', 'A-03'],
        reason: 'the row must not vanish and pull A-02 under the finger');

    ledger.setFilter(LedgerFilter.all);
    ledger.setFilter(LedgerFilter.pending);
    expect(codes(), ['A-02', 'A-03']);
  });

  test('in the Paid filter an undone row stays put until a reload', () async {
    await ledger.markPaid(ledger.visibleRows[0].unit);
    await ledger.markPaid(ledger.visibleRows[1].unit);
    ledger.setFilter(LedgerFilter.paid);
    expect(codes(), ['A-01', 'A-02']);
    await ledger.undo(ledger.visibleRows.first.unit.id);
    expect(codes(), ['A-01', 'A-02']);
    await ledger.refresh();
    expect(codes(), ['A-02']);
  });

  test('a unit added elsewhere appears after the rows already shown',
      () async {
    await ledger.markPaid(ledger.visibleRows.first.unit);
    // Arrives from another device: the list is refreshed in place.
    await repo.createUnit(UnitsCompanion.insert(
        code: 'A-00', tenantName: 'New', monthlyRent: 5000));
    await ledger.refresh(keepOrder: true);
    expect(codes(), ['A-01', 'A-02', 'A-03', 'A-00']);
  });

  test('a failed load reports the error and recovers on retry (B10)',
      () async {
    final broken = AppDatabase.forTesting(NativeDatabase.memory(
        setup: (raw) => raw.execute('CREATE TABLE units (nope INTEGER)')));
    final p = LedgerProvider(LedgerRepository(broken),
        initialMonth: const BsMonth(2082, 2));
    var notified = 0;
    p.addListener(() => notified++);

    await p.init(annualRaisePercent: 10); // the catch-up fails too: no throw
    expect(p.loading, isFalse, reason: 'used to stay true forever');
    expect(p.loadError, isNotNull);
    expect(notified, greaterThan(0));
    await broken.close();

    // A working ledger clears the error on the next load.
    expect(ledger.loadError, isNull);
    await ledger.refresh(showLoading: true);
    expect(ledger.loadError, isNull);
    expect(ledger.loading, isFalse);
  });
}
