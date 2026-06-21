import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/main.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/state/settings_provider.dart';
import 'package:unit_ledger/ui/sheets/edit_unit_sheet.dart';

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

    // Default month is Jestha 2082; nothing paid yet.
    expect((await repo.summary(2082, 2)).collected, 0);
    expect(find.text('Mark paid'), findsOneWidget);

    await tester.tap(find.text('Mark paid'));
    await settle(tester);

    // Payment recorded at the unit's current rent, and the summary reflects it.
    final payments = await repo.paymentsForMonth(2082, 2);
    expect(payments.length, 1);
    expect(payments.single.amount, 10000);
    expect((await repo.summary(2082, 2)).collected, 10000);
    // The pending pill is gone now that the month is settled.
    expect(find.text('Mark paid'), findsNothing);
  });
}
