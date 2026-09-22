@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/main.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/state/settings_provider.dart';

/// Design-review renders of the real widget tree in BOTH appearances at an
/// iPhone-class logical size (393 × 852 @3x), written under
/// `store/raw/preview_<light|dark>/`. Like the store screenshots these are
/// output, not assertions, so they're skipped unless `RENTBEE_SHOTS=1`:
///
///     RENTBEE_SHOTS=1 flutter test --update-goldens --tags screenshots test/appearance_preview_test.dart
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final enabled = Platform.environment['RENTBEE_SHOTS'] == '1';
  const family = 'SF';

  setUpAll(() async {
    Future<void> load(String name, String path) async {
      final bytes = await File(path).readAsBytes();
      await (FontLoader(name)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }

    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable)
            .parent
            .parent
            .parent
            .parent
            .parent
            .path;
    await load(family, '/System/Library/Fonts/SFNS.ttf');
    await load('MaterialIcons',
        '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  });

  late AppDatabase db;
  late LedgerRepository repo;
  late AuthProvider auth;
  late SettingsProvider settings;
  late SharedPreferences prefs;

  Future<String> fastDerive(String pin, String salt, int iters) async =>
      'hash:$pin';

  setUp(() async {
    SharedPreferences.setMockInitialValues({'annual_raise_pct': 0.0});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    auth = AuthProvider.forTest(prefs, fastDerive);
    settings = SettingsProvider(prefs);
  });
  tearDown(() => db.close());

  Future<void> seed() async {
    Future<void> add(String code, String tenant, String business, int rent,
        int deposit, bool paid,
        {int deduction = 0}) async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: code,
        tenantName: tenant,
        businessType: Value(business),
        monthlyRent: rent,
        depositAmount: Value(deposit),
        startedOn: Value(DateTime(2024, 6, 15)),
      ));
      final m = bsYearMonth(DateTime.now());
      if (deduction > 0) {
        await repo.setDeduction(id, m.year, m.month,
            amount: deduction, note: '2 sacks rice');
      }
      if (!paid) return;
      final unit =
          await (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();
      await repo.markPaid(unit, m.year, m.month, paidOn: DateTime.now());
    }

    await add('A-01', 'Maya Tamang', 'Grocery', 15000, 30000, true,
        deduction: 1500);
    await add('A-02', 'Sushant Regmi', 'Home', 22000, 44000, true);
    await add('A-03', 'Nabin Karki', 'Mobile repair', 14000, 28000, false);
    await add('B-01', 'Bikash Shrestha', 'Tailor', 12500, 25000, false);
    await add('B-02', 'Anita Gurung', 'Salon', 18000, 36000, true);
    await add('C-01', 'Ramesh Thapa', 'Cafe', 26000, 52000, true);
  }

  Future<void> settle(WidgetTester t, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> boot(WidgetTester t, ThemeMode mode,
      {bool unlock = true}) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await settings.setAppearance(mode);
    await t.pumpWidget(UnitLedgerApp(
        auth: auth,
        settings: settings,
        repo: repo,
        prefs: prefs,
        fontFamily: family));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    if (unlock) auth.enterGuestMode();
    await settle(t);
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final dir = 'preview_${mode.name}';
    Future<void> shot(WidgetTester t, String name) => expectLater(
        find.byType(UnitLedgerApp),
        matchesGoldenFile('../store/raw/$dir/$name.png'));

    group(dir, () {
      testWidgets('00 phone login', (t) async {
        await boot(t, mode, unlock: false);
        await shot(t, '00_login');
      }, skip: !enabled);

      testWidgets('01 ledger', (t) async {
        await seed();
        await boot(t, mode);
        await shot(t, '01_ledger');
      }, skip: !enabled);

      testWidgets('02 unit detail', (t) async {
        await seed();
        await boot(t, mode);
        await t.tap(find.text('Maya Tamang'));
        await settle(t, 16);
        await shot(t, '02_unit_detail');
      }, skip: !enabled);

      testWidgets('03 reports', (t) async {
        await seed();
        await boot(t, mode);
        await t.tap(find.text('Reports'));
        await settle(t);
        await shot(t, '03_reports');
      }, skip: !enabled);

      testWidgets('04 add unit', (t) async {
        await seed();
        await boot(t, mode);
        await t.tap(find.text('Add Unit'));
        await settle(t, 16);
        await shot(t, '04_add_unit');
      }, skip: !enabled);

      testWidgets('05 settings', (t) async {
        await seed();
        await boot(t, mode);
        await t.tap(find.text('Settings'));
        await settle(t);
        await shot(t, '05_settings');
      }, skip: !enabled);
    });
  }
}
