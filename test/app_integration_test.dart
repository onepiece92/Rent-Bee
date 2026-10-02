import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/main.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/state/ledger_provider.dart';
import 'package:unit_ledger/state/settings_provider.dart';
import 'package:unit_ledger/domain/models.dart';
import 'package:unit_ledger/ui/screens/home_screen.dart';
import 'package:unit_ledger/ui/screens/reports_screen.dart';
import 'package:unit_ledger/ui/screens/settings_screen.dart';
import 'package:unit_ledger/ui/screens/units_screen.dart';
import 'package:unit_ledger/ui/sheets/edit_unit_sheet.dart';
import 'package:unit_ledger/ui/sheets/unit_detail_sheet.dart';
import 'package:unit_ledger/ui/widgets/glass.dart';
import 'package:unit_ledger/ui/widgets/scaffold_with_navbar.dart';

/// App-level integration tests: boot the REAL widget tree (router + providers +
/// onboarding gate + bottom sheets) over an in-memory database and drive
/// end-to-end journeys, asserting both the UI and the underlying DB.
///
/// Runs headlessly via `flutter test` (no device). `sync` stays null so Firebase
/// is never touched; guest mode unlocks straight into the app. The shell has an
/// infinite background animation + a carousel timer, so we never call
/// pumpAndSettle — we advance time with fixed pumps.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;
  late AuthProvider auth;
  late SettingsProvider settings;
  late SharedPreferences prefs;

  // Fast stand-in for the isolate PBKDF2 derive — keeps onboarding instant.
  Future<String> fastDerive(String pin, String salt, int iters) async =>
      'hash:$pin';

  setUp(() async {
    // Disable the automatic lease escalation so rents are date-independent in
    // these tests (the default is 5%, which would raise seeded units once their
    // anniversary passes relative to the real clock).
    SharedPreferences.setMockInitialValues({'annual_raise_pct': 0.0});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    auth = AuthProvider.forTest(prefs, fastDerive); // not onboarded
    settings = SettingsProvider(prefs);
  });
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester t) async {
    // Phone-sized, tall surface so nothing important is off-screen / unhittable.
    t.view.physicalSize = const Size(412, 915);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(UnitLedgerApp(
        auth: auth, settings: settings, repo: repo, prefs: prefs));
    await t.pump(); // first frame
    await t.pump(const Duration(milliseconds: 100)); // ledger.init + redirect
  }

  // Advance time without ever settling (background animation never stops).
  Future<void> settle(WidgetTester t, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('onboarding gate routes to phone verify, then guest unlock '
      'reaches the home ledger', (tester) async {
    await pumpApp(tester);
    // Not onboarded → the router parks the user on phone verification.
    expect(find.text('Verify your phone number to get started'), findsOneWidget);

    // Unlock via the debug guest path (no Firebase) and the gate opens.
    auth.enterGuestMode();
    await settle(tester);

    // Empty ledger → the home empty-state CTA is shown.
    expect(find.text('Add your first unit'), findsOneWidget);
  });

  testWidgets('add a unit through the real form → DB + home list update',
      (tester) async {
    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester);

    // Open the create-unit sheet from the empty state.
    await tester.tap(find.text('Add your first unit'));
    await settle(tester);
    expect(find.text('New Unit'), findsOneWidget);

    // Field order in EditUnitSheet: code(0), tenant(1), business(2),
    // rent(3), phone(4), deposit(5). Code is pre-suggested ('A-01').
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Maya Tamang');
    await tester.enterText(fields.at(3), '15000');
    await settle(tester);

    // The save button is a custom InkWell labelled 'Add Unit'; scope to the
    // sheet so we don't hit the nav bar's 'Add Unit' label.
    await tester.tap(find.descendant(
      of: find.byType(EditUnitSheet),
      matching: find.text('Add Unit'),
    ));
    await settle(tester);

    // DB has the unit...
    final units = await repo.allUnits();
    expect(units.length, 1);
    expect(units.single.code, 'A-01');
    expect(units.single.tenantName, 'Maya Tamang');
    expect(units.single.monthlyRent, 15000);
    expect(units.single.cloudId, isNotNull); // stamped for sync

    // ...and the home list now shows it.
    expect(find.text('Maya Tamang'), findsOneWidget);
  });

  testWidgets('mark a pending unit paid from the home card → payment recorded',
      (tester) async {
    // Seed a unit so the home list renders a pending card with a "Mark paid".
    await repo.createUnit(UnitsCompanion.insert(
      code: 'A-01',
      tenantName: 'Hari',
      monthlyRent: 10000,
      startedOn: Value(DateTime(2025, 6, 15)),
    ));

    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester);

    // The app opens on the current BS month; nothing paid yet.
    final m = bsYearMonth(DateTime.now());
    expect((await repo.summary(m.year, m.month)).collected, 0);
    expect(find.text('Mark paid'), findsOneWidget);

    await tester.tap(find.text('Mark paid'));
    await settle(tester);

    // Payment recorded at the unit's current rent, and the summary reflects it.
    final payments = await repo.paymentsForMonth(m.year, m.month);
    expect(payments.length, 1);
    expect(payments.single.amount, 10000);
    expect((await repo.summary(m.year, m.month)).collected, 10000);
    // The pending pill is gone now that the month is settled.
    expect(find.text('Mark paid'), findsNothing);
  });

  testWidgets('a double tap on Add Unit saves once, with no error (B20)',
      (tester) async {
    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester);
    await tester.tap(find.text('Add your first unit'));
    await settle(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Maya Tamang');
    await tester.enterText(fields.at(3), '15000');
    await settle(tester);

    final save = find.descendant(
        of: find.byType(EditUnitSheet), matching: find.text('Add Unit'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false); // before the first finishes
    await settle(tester, 12);

    expect((await repo.allUnits()).length, 1);
    expect(find.textContaining('Could not save'), findsNothing,
        reason: 'the second submit used to fail on the duplicate code');
    expect(find.byType(EditUnitSheet), findsNothing, reason: 'sheet closed');
  });

  testWidgets('changing the escalation rate re-prices the month on screen '
      '(B22)', (tester) async {
    // Started Jestha 2079, raised once → 11,000 since Jestha 2080.
    await repo.createUnit(UnitsCompanion.insert(
      code: 'M-01',
      tenantName: 'Min',
      monthlyRent: 11000,
      startedOn: Value(adForBsMonthStart(2079, 2)),
      lastRaisedOn: Value(adForBsMonthStart(2080, 2)),
    ));
    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester);
    final ledger = Provider.of<LedgerProvider>(
        tester.element(find.byType(HomeScreen)),
        listen: false);

    // Baishakh 2080 — the month before that raise. With escalation off the
    // app cannot know the older rent and shows today's.
    await ledger.goToMonth(const BsMonth(2080, 1));
    await settle(tester);
    expect(ledger.visibleRows.single.monthRent, 11000);

    // The owner turns escalation on (here, or on another device).
    await settings.setAnnualRaisePercent(10);
    await settle(tester);
    expect(ledger.visibleRows.single.monthRent, 10000,
        reason: 'the open month is re-priced without a restart');
    expect(ledger.summary.expected, 10000);
  });

  testWidgets('only glass that floats over content is blurred (S3)',
      (tester) async {
    await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01', tenantName: 'Hari', monthlyRent: 10000));
    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester, 20); // let the outgoing page leave the tree

    // Home: month arrows and the add button are glass, but sit on the flat
    // page colour — the tab bar is the only surface with content behind it.
    expect(find.byType(GlassIconButton), findsNWidgets(2));
    expect(find.byType(BackdropFilter), findsOneWidget,
        reason: 'was 4 on Home (7 across the tabs) — each an offscreen '
            'layer re-blurred every frame');
    expect(
        find.descendant(
            of: find.byType(ScaffoldWithNavBar),
            matching: find.byType(BackdropFilter)),
        findsOneWidget);

    for (final tab in ['Reports', 'Units']) {
      await tester.tap(find.text(tab).last);
      await settle(tester);
      expect(find.byType(BackdropFilter), findsOneWidget, reason: tab);
    }
  });

  testWidgets('Reports is not recomputed while hidden, nor for a keystroke '
      '(S4)', (tester) async {
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final counting = _CountingRepo(db);
    repo = counting;
    await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01', tenantName: 'Hari', monthlyRent: 10000));
    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester, 20);

    await tester.tap(find.text('Reports').last);
    await settle(tester);
    expect(counting.reports, 1, reason: 'computed when first shown');

    // Back on the Ledger: search and mark paid. Reports is off-screen.
    await tester.tap(find.text('Ledger').last);
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Search tenant or unit…'), 'Hari');
    await settle(tester);
    await tester.tap(find.text('Mark paid'));
    await settle(tester, 12);
    expect(counting.reports, 1,
        reason: 'each used to re-run the period queries behind the scenes');

    // Shown again: one reload, with the payment in it.
    await tester.tap(find.text('Reports').last);
    await settle(tester);
    expect(counting.reports, 2);

    // While visible, a change that is not data (the Ledger's filter) is
    // ignored; a data change still reloads.
    final ledger = Provider.of<LedgerProvider>(
        tester.element(find.byType(ReportsScreen)),
        listen: false);
    ledger.setFilter(LedgerFilter.paid);
    await settle(tester, 12);
    expect(counting.reports, 2);
    await ledger.undo((await repo.allUnits()).single.id);
    await settle(tester, 12);
    expect(counting.reports, 3);
  });

  testWidgets('a keystroke in search rebuilds the list, not the other tabs '
      '(S6)', (tester) async {
    await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01', tenantName: 'Hari', monthlyRent: 10000));
    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester, 20);
    // Visit the other tabs so they exist (the shell keeps them alive).
    for (final tab in ['Units', 'Settings', 'Ledger']) {
      await tester.tap(find.text(tab).last);
      await settle(tester);
    }

    final rebuilt = <Type, int>{};
    // Installed after every tab has been built, so each call for one of the
    // screens is a rebuild. (The flag the hook passes is only maintained
    // while debugPrintRebuildDirtyWidgets is on, so it is not used.)
    debugOnRebuildDirtyWidget = (e, _) {
      rebuilt.update(e.widget.runtimeType, (n) => n + 1, ifAbsent: () => 1);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await tester.enterText(
        find.widgetWithText(TextField, 'Search tenant or unit…'), 'Har');
    await settle(tester);
    expect(rebuilt[SettingsScreen], isNull,
        reason: 'used to rebuild on every Ledger notification');
    expect(rebuilt[UnitsScreen], isNull);
    expect(rebuilt[HomeScreen], isNull);

    // A data change reaches the Units directory, and still not Settings.
    rebuilt.clear();
    await tester.tap(find.text('Mark paid'));
    await settle(tester, 12);
    expect(rebuilt[UnitsScreen], 1);
    expect(rebuilt[SettingsScreen], isNull);

    // Settings does follow the facts it shows: the unit count.
    rebuilt.clear();
    await repo.createUnit(UnitsCompanion.insert(
        code: 'A-02', tenantName: 'Sita', monthlyRent: 9000));
    await Provider.of<LedgerProvider>(
            tester.element(find.byType(HomeScreen)),
            listen: false)
        .refresh();
    await settle(tester);
    expect(rebuilt[SettingsScreen], 1);
  });

  testWidgets('unit sheet: avatar follows the paid state; history and icon '
      'buttons are labelled (B32)', (tester) async {
    await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01',
        tenantName: 'Hari',
        monthlyRent: 10000,
        phone: const Value('+9779801234501')));
    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester, 20);
    final semantics = tester.ensureSemantics();

    // The icon-only reminder button says what it does.
    expect(find.byTooltip('Send reminder'), findsOneWidget);

    await tester.tap(find.text('Hari'));
    await settle(tester, 12);
    final sheet = find.byType(UnitDetailSheet);
    CodeAvatar avatar() => tester.widget<CodeAvatar>(
        find.descendant(of: sheet, matching: find.byType(CodeAvatar)));
    expect(avatar().paid, isFalse, reason: 'was always green ("paid")');

    // Every month in the history strip states its status in words.
    final m = bsYearMonth(DateTime.now());
    final thisMonth = BsMonth(m.year, m.month).labelIn(settings.calendar);
    expect(find.bySemanticsLabel('$thisMonth, not paid'), findsOneWidget);

    await tester.tap(find.descendant(
        of: sheet, matching: find.textContaining('Collect')).first);
    await settle(tester, 12);
    expect(avatar().paid, isTrue);
    expect(find.bySemanticsLabel('$thisMonth, paid'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Change PIN: wrong current PIN is refused, the right one '
      'changes it (B32)', (tester) async {
    await pumpApp(tester);
    auth.enterGuestMode();
    await auth.setPin('1234');
    await settle(tester, 20);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.tap(find.text('Change PIN'));
    await settle(tester);

    final pins = find.byType(TextFormField);
    await tester.enterText(pins.at(0), '9999');
    await tester.enterText(pins.at(1), '4321');
    await tester.enterText(pins.at(2), '4321');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Current PIN is incorrect'), findsOneWidget);
    expect(find.text('Confirm new PIN'), findsOneWidget, reason: 'still open');

    await tester.enterText(pins.at(0), '1234');
    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Save'), warnIfMissed: false); // double tap
    await settle(tester, 12);
    expect(find.text('Confirm new PIN'), findsNothing);
    expect(find.text('PIN updated'), findsOneWidget);
    auth.lock();
    expect(await auth.unlock('1234'), isFalse);
    expect(await auth.unlock('4321'), isTrue);
    await tester.pump(const Duration(seconds: 3)); // toasts
  });

  testWidgets('the search box still shows the query after a lock (B19)',
      (tester) async {
    for (final (code, name) in [('A-01', 'Hari'), ('A-02', 'Sita')]) {
      await repo.createUnit(UnitsCompanion.insert(
          code: code, tenantName: name, monthlyRent: 10000));
    }
    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester);

    // By hint: during a route change the outgoing page's fields are still
    // in the tree.
    final search = find.widgetWithText(TextField, 'Search tenant or unit…');
    await tester.enterText(search, 'Sita');
    await settle(tester);
    expect(find.text('Hari'), findsNothing);

    // Auto-lock replaces the screen; the provider (and its query) lives on.
    auth.lock();
    await settle(tester, 20);
    expect(find.byType(HomeScreen, skipOffstage: false), findsNothing,
        reason: 'the Home screen is torn down while locked');
    auth.enterGuestMode();
    await settle(tester, 20);

    expect(find.text('Hari'), findsNothing, reason: 'the list is filtered…');
    expect(tester.widget<TextField>(search).controller!.text, 'Sita',
        reason: '…so the box must say by what (it used to come back empty)');
  });

  testWidgets('a ledger that cannot load says so and offers a retry (B10)',
      (tester) async {
    await db.close();
    // A database whose schema cannot be created: every query fails.
    db = AppDatabase.forTesting(NativeDatabase.memory(
        setup: (raw) => raw.execute('CREATE TABLE units (nope INTEGER)')));
    repo = LedgerRepository(db);

    await pumpApp(tester);
    auth.enterGuestMode();
    await settle(tester);

    expect(find.text('Could not load your ledger'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'used to spin forever');
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Could not load your ledger'), findsOneWidget);
  });

  group('Generate demo data confirmation', () {
    // Unlocks, opens Settings, scrolls to the Data section and taps the row.
    Future<void> tapGenerateDemo(WidgetTester t) async {
      await pumpApp(t);
      auth.enterGuestMode();
      await settle(t);
      await t.tap(find.text('Settings'));
      await settle(t);
      final list = find
          .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable))
          .first;
      await t.drag(list, const Offset(0, -3000));
      await settle(t);
      await t.tap(find.text('Generate demo data'));
      await settle(t);
    }

    TextButton action(WidgetTester t, String label) => t.widget<TextButton>(
        find.ancestor(of: find.text(label), matching: find.byType(TextButton)));

    // The success toast holds a 2.6 s timer; let it finish so no timer is
    // pending when the test tears the tree down.
    Future<void> drainToast(WidgetTester t) async {
      await t.pump(const Duration(seconds: 3));
      await settle(t);
    }

    testWidgets('an empty ledger keeps the one-tap confirm', (tester) async {
      await tapGenerateDemo(tester);
      // Nothing to overwrite → the plain dialog, no typing.
      expect(find.text('Generate demo data?'), findsOneWidget);
      expect(find.textContaining('REPLACE'), findsNothing);

      await tester.tap(find.text('Generate'));
      await settle(tester, 12);
      expect((await repo.allUnits()).length, greaterThan(1));
      await drainToast(tester);
    });

    testWidgets('existing data must be confirmed by typing REPLACE',
        (tester) async {
      await repo.createUnit(UnitsCompanion.insert(
          code: 'MY-01', tenantName: 'Real Tenant', monthlyRent: 10000));
      await tapGenerateDemo(tester);

      // The dialog names what is at stake and the button starts disabled.
      expect(find.textContaining('You have 1 unit with payment history'),
          findsOneWidget);
      expect(find.text('Type REPLACE to confirm.'), findsOneWidget);
      // A guest session has no cloud mirror, so no claim about other devices.
      expect(find.textContaining('every other device'), findsNothing);
      expect(action(tester, 'Replace').onPressed, isNull);

      // A stray tap on the disabled button overwrites nothing.
      await tester.tap(find.text('Replace'));
      await settle(tester);
      expect((await repo.allUnits()).single.code, 'MY-01');

      await tester.enterText(find.byType(TextField), 'replace');
      await tester.pump();
      expect(action(tester, 'Replace').onPressed, isNotNull);
      await tester.tap(find.text('Replace'));
      await settle(tester, 12);

      final units = await repo.allUnits();
      expect(units.any((u) => u.code == 'MY-01'), isFalse);
      expect(units.length, greaterThan(1));
      await drainToast(tester);
    });
  });
}

/// Counts how often the Reports figures are computed.
class _CountingRepo extends LedgerRepository {
  _CountingRepo(super.db);
  int reports = 0;

  @override
  Future<PeriodSummary> periodSummarySpan(BsMonth start, BsMonth end,
      {double percent = 0}) {
    reports++;
    return super.periodSummarySpan(start, end, percent: percent);
  }
}
