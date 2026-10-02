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
import 'package:unit_ledger/state/settings_provider.dart';
import 'package:unit_ledger/ui/screens/login_screen.dart';
import 'package:unit_ledger/ui/screens/settings_screen.dart';
import 'package:unit_ledger/ui/sheets/edit_unit_sheet.dart';

/// Every screen must lay out without overflowing at the text sizes people
/// actually set: iOS "Larger Text" at its biggest standard step (~1.35×) and
/// well into the accessibility sizes (2×), on a small phone. (buglog B18.)
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final scale in [1.35, 2.0]) {
    testWidgets('no layout overflows at ${scale}x text', (tester) async {
      SharedPreferences.setMockInitialValues({'annual_raise_pct': 0.0});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LedgerRepository(db);
      final auth = AuthProvider.forTest(
          prefs, (pin, salt, iters) async => 'hash:$pin');
      final settings = SettingsProvider(prefs);

      // A ledger with every row state: pending, paid, part-paid, vacant,
      // long names, big amounts, charges and a deduction.
      final now = bsYearMonth(DateTime.now());
      Future<Unit> unit(String code, String name, int rent,
          {bool active = true, String? phone}) async {
        final id = await repo.createUnit(UnitsCompanion.insert(
          code: code,
          tenantName: name,
          monthlyRent: rent,
          businessType: const Value('Wholesale electronics and repairs'),
          phone: Value(phone),
          isActive: Value(active),
          depositAmount: const Value(250000),
          startedOn: Value(DateTime(2023, 4, 20)),
        ));
        return (db.select(db.units)..where((u) => u.id.equals(id)))
            .getSingle();
      }

      final first = await unit('A-01', 'Hari Bahadur Shrestha Maharjan',
          125000, phone: '+9779801234501');
      await repo.setCharges(first.id, now.year, now.month,
          electricity: 12500, water: 800, service: 1500);
      await repo.setDeduction(first.id, now.year, now.month,
          amount: 3500, note: 'Bought two ceiling fans');
      final paid = await unit('A-02', 'Sita', 18000);
      final part = await unit('B-104', 'Annapurna Trading Company Pvt. Ltd.',
          1250000, phone: '+9779801234502');
      await unit('C-01', 'Vacant shop', 9000, active: false);
      await repo.markPaid(paid, now.year, now.month);
      await repo.markPaid(part, now.year, now.month, amount: 500000);
      await repo.setCharges(part.id, now.year, now.month,
          electricity: 12500, water: 800, service: 1500);
      await repo.setDeduction(part.id, now.year, now.month,
          amount: 3500, note: 'Bought two ceiling fans');

      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // Collect layout errors instead of stopping at the first.
      final problems = <String>[];
      var where = 'start';
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('overflowed')) {
          // Name the widget's source line, so a failure says where to look.
          final at = RegExp(r'lib/[a-z_/]+\.dart:\d+')
                  .firstMatch(details.toString())
                  ?.group(0) ??
              'unknown widget';
          final line = '$where: ${text.split('\n').first} ($at)';
          if (!problems.contains(line)) problems.add(line);
        } else {
          previous?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = previous);

      Future<void> settle([int frames = 10]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      Future<void> scrollThrough(Finder scope) async {
        final list = find
            .descendant(of: scope, matching: find.byType(Scrollable))
            .first;
        for (var i = 0; i < 6; i++) {
          await tester.drag(list, const Offset(0, -500), warnIfMissed: false);
          await settle(3);
        }
        for (var i = 0; i < 6; i++) {
          await tester.drag(list, const Offset(0, 500), warnIfMissed: false);
          await settle(3);
        }
      }

      await tester.pumpWidget(UnitLedgerApp(
          auth: auth, settings: settings, repo: repo, prefs: prefs));
      where = 'phone verification';
      await settle();
      auth.enterGuestMode();
      where = 'Ledger';
      await settle(20);
      await scrollThrough(find.byType(Scaffold).first);

      // Unit sheet (a unit with charges and a deduction).
      where = 'unit sheet';
      // At 2× the rows start below the fold and are built lazily.
      await tester.scrollUntilVisible(
          find.textContaining('Hari Bahadur'), 150,
          scrollable: find.byType(Scrollable).first);
      await settle(3);
      await tester.tap(find.textContaining('Hari Bahadur').first,
          warnIfMissed: false);
      await settle(12);
      if (find.byTooltip('Close').evaluate().isNotEmpty) {
        final sheetList = find.byType(Scrollable).last;
        for (var i = 0; i < 5; i++) {
          await tester.drag(sheetList, const Offset(0, -400),
              warnIfMissed: false);
          await settle(3);
        }
        await tester.tap(find.byTooltip('Close').first, warnIfMissed: false);
        await settle(12);
      } else {
        problems.add('unit sheet: did not open');
      }

      for (final tab in ['Reports', 'Units', 'Settings']) {
        where = tab;
        await tester.tap(find.text(tab).last, warnIfMissed: false);
        await settle(12);
        await scrollThrough(find.byType(Scaffold).first);
      }

      // Alerts: the typed confirmation is the tallest one.
      where = 'Erase alert';
      final settingsList = find
          .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('Erase all data'), 300,
          scrollable: settingsList, maxScrolls: 80);
      await settle();
      await tester.tap(find.text('Erase all data'), warnIfMissed: false);
      await settle(12);
      if (find.text('Cancel').evaluate().isNotEmpty) {
        await tester.tap(find.text('Cancel').last, warnIfMissed: false);
        await settle(12);
      } else {
        problems.add('Erase alert: did not open');
      }

      // Add-unit form.
      where = 'add unit sheet';
      await tester.tap(find.text('Units').last, warnIfMissed: false);
      await settle(12);
      await tester.tap(find.text('Add Unit').first, warnIfMissed: false);
      await settle(12);
      if (find.byType(EditUnitSheet).evaluate().isNotEmpty) {
        final form = find.byType(Scrollable).last;
        for (var i = 0; i < 5; i++) {
          await tester.drag(form, const Offset(0, -400), warnIfMissed: false);
          await settle(3);
        }
        await tester.tap(find.byTooltip('Close').first, warnIfMissed: false);
        await settle(12);
      } else {
        problems.add('add unit sheet: did not open');
      }

      // Lock screen.
      where = 'lock screen';
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3)); // let toasts/timers finish
      FlutterError.onError = previous;
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }

  testWidgets('the lock screen fits at 2x text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthProvider.forTest(
        prefs, (pin, salt, iters) async => 'x',
        hash: 'h', salt: 's', phone: '+9779801234501');
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: const MaterialApp(home: LoginScreen()),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Forgot PIN?'), findsOneWidget);
  });
}
