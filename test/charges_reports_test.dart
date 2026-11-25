import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/main.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/state/settings_provider.dart';
import 'package:unit_ledger/ui/sheets/unit_detail_sheet.dart';
import 'package:unit_ledger/ui/widgets/glass.dart';

/// The charges & deductions reports: charges per month, charges by unit,
/// deductions by unit, and the units still missing their meter readings.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LedgerRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<int> unit(String code, String name, {DateTime? startedOn}) =>
      repo.createUnit(UnitsCompanion.insert(
          code: code,
          tenantName: name,
          monthlyRent: 10000,
          startedOn: Value(startedOn)));

  group('data', () {
    test('charges by unit: per-type split, largest first, months counted',
        () async {
      final a = await unit('A-01', 'Asha');
      final b = await unit('B-01', 'Bina');
      await unit('C-01', 'Chandra'); // never billed
      await repo.setCharges(a, 2082, 2, electricity: 1000, water: 200);
      await repo.setCharges(a, 2082, 3, electricity: 1200);
      await repo.setCharges(b, 2082, 2, electricity: 3000, service: 500);

      final s = await repo.periodSummarySpan(
          const BsMonth(2082, 1), const BsMonth(2082, 3));
      expect([for (final c in s.chargesByUnit) c.unit.code], ['B-01', 'A-01']);
      final asha = s.chargesByUnit[1];
      expect((asha.electricity, asha.water, asha.service, asha.months),
          (2200, 200, 0, 2));
      expect(s.chargesByUnit.fold<int>(0, (t, c) => t + c.total),
          s.chargesExpected,
          reason: 'reconciles with the card total');
      expect([for (final u in s.missingCharges) u.code], ['C-01']);
    });

    test('per-month charges and deductions add up to the period totals',
        () async {
      final a = await unit('A-01', 'Asha');
      await repo.setCharges(a, 2082, 1, electricity: 800);
      await repo.setCharges(a, 2082, 3, electricity: 1500, water: 100);
      await repo.setDeduction(a, 2082, 3, amount: 700, note: 'rice');

      final s = await repo.periodSummarySpan(
          const BsMonth(2082, 1), const BsMonth(2082, 3));
      expect([for (final m in s.months) m.charges], [800, 0, 1600]);
      expect([for (final m in s.months) m.deductions], [0, 0, 700]);
      expect(s.months.fold<int>(0, (t, m) => t + m.charges),
          s.chargesExpected);
      expect(s.months.fold<int>(0, (t, m) => t + m.deductions), s.deductions);
    });

    test('months before a tenant started count nowhere', () async {
      // Started in Asar 2082 (month 3).
      final a = await unit('A-01', 'Asha', startedOn: DateTime(2025, 6, 25));
      await repo.setCharges(a, 2082, 2, electricity: 999); // before start
      final s = await repo.periodSummarySpan(
          const BsMonth(2082, 2), const BsMonth(2082, 3));
      expect(s.chargesByUnit, isEmpty);
      expect(s.months.first.charges, 0);
      expect([for (final u in s.missingCharges) u.code], ['A-01'],
          reason: 'started in the period, no charges for a started month');

      final before = await repo.periodSummarySpan(
          const BsMonth(2082, 2), const BsMonth(2082, 2));
      expect(before.missingCharges, isEmpty,
          reason: 'not a tenant yet, so nothing is missing');
    });

    test('vacated units are left out', () async {
      final a = await unit('A-01', 'Asha');
      await repo.setCharges(a, 2082, 2, electricity: 500);
      final u = (await repo.allUnits()).single;
      await repo.updateUnit(u.copyWith(isActive: false));
      final s = await repo.periodSummarySpan(
          const BsMonth(2082, 2), const BsMonth(2082, 2));
      expect(s.chargesByUnit, isEmpty);
      expect(s.missingCharges, isEmpty);
    });
  });

  group('screen', () {
    late AuthProvider auth;
    late SettingsProvider settings;
    late SharedPreferences prefs;
    final now = bsYearMonth(DateTime.now());

    setUp(() async {
      SharedPreferences.setMockInitialValues({'annual_raise_pct': 0.0});
      prefs = await SharedPreferences.getInstance();
      auth = AuthProvider.forTest(prefs, (pin, salt, i) async => 'h:$pin');
      settings = SettingsProvider(prefs);
      final a = await unit('A-01', 'Asha');
      final b = await unit('B-01', 'Bina');
      await unit('C-01', 'Chandra');
      await unit('D-01', 'Dawa');
      await repo.setCharges(a, now.year, now.month,
          electricity: 2500, water: 400);
      await repo.setCharges(b, now.year, now.month, electricity: 1500);
      await repo.setDeduction(b, now.year, now.month,
          amount: 1000, note: '2 sacks rice');
    });

    Future<void> settle(WidgetTester t, [int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
    }

    Future<void> openReports(WidgetTester t) async {
      t.view.physicalSize = const Size(412, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(UnitLedgerApp(
          auth: auth, settings: settings, repo: repo, prefs: prefs));
      await t.pump();
      auth.enterGuestMode();
      await settle(t, 20);
      await t.tap(find.text('Reports').last);
      await settle(t);
    }

    Finder inList(String text) => find.text(text, skipOffstage: false);
    // The tenants are also listed under Outstanding; look inside the card.
    Finder inMissing(String name) => find.descendant(
        of: find.byType(Well), matching: find.text(name));

    Future<void> reveal(WidgetTester t, Finder f) => t.scrollUntilVisible(
        f, 300,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);

    testWidgets('month: charges by unit, deductions by unit, missing readings',
        (t) async {
      await openReports(t);

      // Missing readings: a count, expandable to the two units.
      final line = find.text('Charges entered for 2 of 4 units');
      expect(line, findsOneWidget);
      await t.tap(find.text('Show missing'));
      await settle(t);
      expect(find.text('No charges entered'), findsNWidgets(2));
      expect(inMissing('Chandra'), findsOneWidget);
      expect(inMissing('Dawa'), findsOneWidget);
      expect(inMissing('Asha'), findsNothing);

      // Charges by unit, largest first, with the split.
      await reveal(t, inList('Charges by unit (2)'));
      expect(
          find.textContaining('Electricity\u00A0Rs\u00A02,500 · Water\u00A0Rs\u00A0400'),
          findsOneWidget);
      expect(t.getTopLeft(find.text('Asha').last).dy,
          lessThan(t.getTopLeft(find.text('Bina').at(1)).dy));

      // Deductions by unit: grouped, tap to see the entry.
      await reveal(t, inList('Deductions by unit (1)'));
      expect(find.textContaining('1 deduction · 2 sacks rice'), findsOneWidget);
      await t.ensureVisible(find.textContaining('1 deduction · 2 sacks rice'));
      await settle(t);
      await t.tap(find.textContaining('1 deduction · 2 sacks rice'));
      await settle(t);
      expect(find.textContaining('— 2 sacks rice'), findsOneWidget);

      // Per-month trend is for quarter / year only.
      expect(inList('Charges per month'), findsNothing);
    });

    testWidgets('tapping a missing unit opens it on the report month',
        (t) async {
      await openReports(t);
      await t.tap(find.text('Show missing'));
      await settle(t);
      await t.tap(inMissing('Chandra'));
      await settle(t);
      expect(find.byType(UnitDetailSheet), findsOneWidget);
    });

    testWidgets('year: charges per month appears', (t) async {
      await openReports(t);
      await t.tap(find.text('Year'));
      await settle(t);
      await reveal(t, inList('Charges per month'));
      expect(find.text('Charges per month'), findsOneWidget);
      expect(find.text('− Rs 1,000 deducted'), findsOneWidget);
      // The missing-readings line belongs to the month view only.
      expect(inList('Show missing'), findsNothing);
    });
  });
}
