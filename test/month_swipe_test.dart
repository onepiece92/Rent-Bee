import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/domain/models.dart';
import 'package:unit_ledger/main.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/state/ledger_provider.dart';
import 'package:unit_ledger/state/settings_provider.dart';
import 'package:unit_ledger/ui/screens/home_screen.dart';
import 'package:unit_ledger/ui/screens/reports_screen.dart';

/// Swiping left / right on the Ledger and Reports steps to the next /
/// previous period, like Calendar. A small or vertical drag changes nothing,
/// and while the next month loads the previous one stays up but inert.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;
  late AuthProvider auth;
  late SettingsProvider settings;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'annual_raise_pct': 0.0});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    auth = AuthProvider.forTest(prefs, (pin, salt, iters) async => 'h:$pin');
    settings = SettingsProvider(prefs);
    for (var i = 1; i <= 8; i++) {
      await repo.createUnit(UnitsCompanion.insert(
          code: 'A-0$i', tenantName: 'Tenant $i', monthlyRent: 10000));
    }
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester t, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<LedgerProvider> open(WidgetTester t) async {
    t.view.physicalSize = const Size(412, 915);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(UnitLedgerApp(
        auth: auth, settings: settings, repo: repo, prefs: prefs));
    await t.pump();
    auth.enterGuestMode();
    await settle(t, 20);
    return Provider.of<LedgerProvider>(t.element(find.byType(HomeScreen)),
        listen: false);
  }

  final now = bsYearMonth(DateTime.now());
  final thisMonth = BsMonth(now.year, now.month);

  // A point in the middle of the list, clear of the header's buttons.
  Offset middle(WidgetTester t) =>
      t.getCenter(find.text('Tenant 2').first);

  testWidgets('swipe left = next month, swipe right = previous', (t) async {
    final ledger = await open(t);
    expect(ledger.month, thisMonth);

    await t.flingFrom(middle(t), const Offset(-200, 0), 1000);
    await settle(t);
    expect(ledger.month, thisMonth.next());
    expect(find.text(thisMonth.next().monthNameIn(settings.calendar)),
        findsOneWidget, reason: 'the header names the new month');

    await t.flingFrom(middle(t), const Offset(200, 0), 1000);
    await settle(t);
    await t.flingFrom(middle(t), const Offset(200, 0), 1000);
    await settle(t);
    expect(ledger.month, thisMonth.previous());
  });

  testWidgets('a slow drag past a quarter of the width also counts',
      (t) async {
    final ledger = await open(t);
    final g = await t.startGesture(middle(t));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(-10, 0));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump(const Duration(milliseconds: 400)); // stop: no fling
    await g.up();
    await settle(t);
    expect(ledger.month, thisMonth.next());
  });

  testWidgets('a short or vertical drag does not change the month',
      (t) async {
    final ledger = await open(t);

    // Short and slow: under a quarter of the width, no fling.
    final g = await t.startGesture(middle(t));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(-10, 0));
      await t.pump(const Duration(milliseconds: 80));
    }
    await t.pump(const Duration(milliseconds: 400));
    await g.up();
    await settle(t);
    expect(ledger.month, thisMonth);

    // A fast vertical scroll with some sideways wobble scrolls, not swipes.
    await t.flingFrom(middle(t), const Offset(-30, -300), 1500);
    await settle(t, 30);
    expect(ledger.month, thisMonth);
  });

  testWidgets('the arrows still work and the page slides with them',
      (t) async {
    final ledger = await open(t);
    await t.tap(find.bySemanticsLabel('Next month'));
    await t.pump(const Duration(milliseconds: 100));
    // Mid-slide the page is shifted right (it enters from the right)...
    double shift() => t
        .widgetList<Transform>(find.ancestor(
            of: find.byType(CustomScrollView),
            matching: find.byType(Transform)))
        .fold(0.0, (x, w) => x + w.transform.getTranslation().x);
    expect(shift(), greaterThan(0));
    await settle(t);
    // ...and back in place once it lands.
    expect(shift(), 0);
    expect(ledger.month, thisMonth.next());

    // Going back, it enters from the left.
    await t.tap(find.bySemanticsLabel('Previous month'));
    await t.pump(const Duration(milliseconds: 100));
    expect(shift(), lessThan(0));
    await settle(t);
  });

  testWidgets('Reports: swipe steps the period', (t) async {
    await open(t);
    await t.tap(find.text('Reports').last);
    await settle(t);
    final label = thisMonth.labelIn(settings.calendar);
    expect(find.text(label), findsOneWidget);

    await t.flingFrom(t.getCenter(find.byType(ReportsScreen)),
        const Offset(-200, 0), 1000);
    await settle(t);
    expect(find.text(thisMonth.next().labelIn(settings.calendar)),
        findsOneWidget);

    await t.flingFrom(t.getCenter(find.byType(ReportsScreen)),
        const Offset(200, 0), 1000);
    await settle(t);
    expect(find.text(label), findsOneWidget);
  });

  group('while the next month loads', () {
    /// A repository whose month loads wait until released.
    late _GatedRepo gated;
    late LedgerProvider ledger;
    setUp(() async {
      gated = _GatedRepo(db);
      ledger = LedgerProvider(gated, initialMonth: thisMonth);
      await ledger.init();
    });

    test('the old month stays up, marked as switching, with no spinner',
        () async {
      final rowsBefore = ledger.visibleRows;
      gated.hold();
      ledger.nextMonth();
      expect(ledger.month, thisMonth.next(), reason: 'header updates at once');
      expect(ledger.switching, isTrue);
      expect(ledger.loading, isFalse, reason: 'no spinner flash');
      expect(ledger.visibleRows, rowsBefore);

      gated.release();
      await pumpEventQueue();
      expect(ledger.switching, isFalse);
    });

    test('a slow load shows the spinner after a moment', () async {
      gated.hold();
      ledger.nextMonth();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(ledger.loading, isTrue);
      gated.release();
      await pumpEventQueue();
      expect(ledger.loading, isFalse);
      expect(ledger.switching, isFalse);
    });

    test('rapid swipes land on the last month, whatever finishes first',
        () async {
      // Only the first month has a payment, so its figures are recognisable.
      final m1 = thisMonth.next();
      final unit = (await gated.allUnits()).first;
      await gated.markPaid(unit, m1.year, m1.month, amount: 10000);
      gated.hold();
      ledger.nextMonth(); // load 1, held
      gated.hold();
      ledger.nextMonth(); // load 2, held
      expect(ledger.month, thisMonth.next().next());
      gated.releaseLatestFirst();
      await pumpEventQueue();
      expect(ledger.month, thisMonth.next().next());
      expect(ledger.switching, isFalse);
      expect(ledger.summary.collected, 0,
          reason: 'the earlier month finished last but must not land');
    });
  });

  testWidgets('old rows cannot be tapped while the next month loads',
      (t) async {
    final ledger = await open(t);
    final ignoring = find.byWidgetPredicate(
        (w) => w is SliverIgnorePointer && w.ignoring);
    expect(ignoring, findsNothing);
    ledger.setMonth(thisMonth.next());
    await t.pump(); // switching, data not in yet
    if (ledger.switching) expect(ignoring, findsOneWidget);
    await settle(t);
    expect(ignoring, findsNothing);
  });
}

class _GatedRepo extends LedgerRepository {
  _GatedRepo(super.db);
  final _gates = <Completer<void>>[];
  bool _hold = false;

  void hold() => _hold = true;
  void release() {
    for (final g in _gates) {
      g.complete();
    }
    _gates.clear();
  }

  void releaseLatestFirst() {
    for (final g in _gates.reversed) {
      g.complete();
    }
    _gates.clear();
  }

  @override
  Future<({List<UnitRow> rows, MonthSummary summary})> monthView(
      int year, int month,
      {double percent = 0}) async {
    if (_hold) {
      _hold = false;
      final g = Completer<void>();
      _gates.add(g);
      await g.future;
    }
    return super.monthView(year, month, percent: percent);
  }
}
