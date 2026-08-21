@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/services.dart' show FontLoader;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/main.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/state/settings_provider.dart';

/// Generates the raw App Store / Play screenshots straight from the real widget
/// tree, at each store's exact pixel size, with no device frame and no drawn
/// status bar. App Review rejected build 2 under guideline 2.3.10 because the
/// uploaded shots were phone mockups wearing a painted status bar — including
/// the iPad set, which showed an iPhone. These are genuine renders instead.
///
/// Run (writes PNGs under store/raw/<device>/):
///
///     flutter test --update-goldens --tags screenshots test/store_screenshots_test.dart
///
/// Skipped in normal runs: goldens here are marketing output, not assertions,
/// so a deliberate UI change must never fail the suite.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final enabled = Platform.environment['RENTBEE_SHOTS'] == '1';

  // `flutter test` maps every font family to the blank test font, so without
  // this every glyph — text and Material icons alike — renders as a box.
  setUpAll(() async {
    Future<void> load(String family, String path) async {
      final bytes = await File(path).readAsBytes();
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }

    // .../bin/cache/dart-sdk/bin/dart(.exe) → four levels up is the SDK root.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable)
            .parent
            .parent
            .parent
            .parent
            .parent
            .path;

    await load('Fraunces', 'assets/fonts/Fraunces.ttf');
    await load('HankenGrotesk', 'assets/fonts/HankenGrotesk.ttf');
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
    // Pin the escalation off so seeded rents don't drift with the real clock.
    SharedPreferences.setMockInitialValues({'annual_raise_pct': 0.0});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    auth = AuthProvider.forTest(prefs, fastDerive);
    settings = SettingsProvider(prefs);
  });
  tearDown(() => db.close());

  /// Demo ledger: a believable mix of paid and pending across five units, so
  /// the summary card, the filter chips and both card states all have content.
  Future<void> seed() async {
    Future<void> add(String code, String tenant, String business, int rent,
        int deposit, bool paid) async {
      final id = await repo.createUnit(UnitsCompanion.insert(
        code: code,
        tenantName: tenant,
        businessType: Value(business),
        monthlyRent: rent,
        depositAmount: Value(deposit),
        startedOn: Value(DateTime(2024, 6, 15)),
      ));
      if (!paid) return;
      final unit =
          await (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();
      // Jestha 2082 is the app's default month (see main.dart).
      await repo.markPaid(unit, 2082, 2, paidOn: DateTime(2025, 5, 28));
    }

    // Eight units so the list fills an iPad canvas as well as a phone.
    await add('A-01', 'Maya Tamang', 'Grocery', 15000, 30000, true);
    await add('A-02', 'Sushant Regmi', 'Home', 22000, 44000, true);
    await add('A-03', 'Nabin Karki', 'Mobile repair', 14000, 28000, true);
    await add('B-01', 'Bikash Shrestha', 'Tailor', 12500, 25000, false);
    await add('B-02', 'Anita Gurung', 'Salon', 18000, 36000, false);
    await add('B-03', 'Sabina Rai', 'Boutique', 16500, 33000, true);
    await add('C-01', 'Ramesh Thapa', 'Cafe', 26000, 52000, true);
    await add('C-02', 'Deepak Magar', 'Hardware', 20000, 40000, true);
  }

  // The shell runs a forever background animation + a carousel timer, so
  // pumpAndSettle would spin forever. Advance a fixed number of frames.
  Future<void> settle(WidgetTester t, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  /// Pumps the real app at [pixels] with [dpr], i.e. at the store's exact
  /// canvas size, and unlocks past onboarding.
  Future<void> boot(WidgetTester t, Size pixels, double dpr) async {
    t.view.physicalSize = pixels;
    t.view.devicePixelRatio = dpr;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(UnitLedgerApp(
        auth: auth, settings: settings, repo: repo, prefs: prefs));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    auth.enterGuestMode();
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String device, String name) async {
    await expectLater(
      find.byType(UnitLedgerApp),
      matchesGoldenFile('../store/raw/$device/$name.png'),
    );
  }

  /// Store canvases: logical size is pixels / dpr, which is what the app lays
  /// out against — so these render exactly as the device would.
  const devices = <String, (Size, double)>{
    // iPhone 16 Pro Max class — the 6.9"/6.7" App Store slot.
    'ios_iphone_6.7': (Size(1290, 2796), 3.0),
    // iPhone 14 Plus class — the 6.5" slot.
    'ios_iphone_6.5': (Size(1284, 2778), 3.0),
    // iPad Pro 12.9" / 13" slot — a real iPad canvas, not a phone mockup.
    'ios_ipad_12.9': (Size(2048, 2732), 2.0),
  };

  devices.forEach((device, spec) {
    final (pixels, dpr) = spec;

    group(device, () {
      testWidgets('01 ledger', (t) async {
        await seed();
        await boot(t, pixels, dpr);
        await shot(t, device, '01_ledger');
      }, skip: !enabled);

      testWidgets('02 unit detail', (t) async {
        await seed();
        await boot(t, pixels, dpr);
        // Tapping a ledger card opens UnitDetailSheet (deposit, charges,
        // payment history) — see home_screen.dart.
        await t.tap(find.text('Maya Tamang'));
        await settle(t, 16);
        await shot(t, device, '02_unit_detail');
      }, skip: !enabled);

      testWidgets('03 reports', (t) async {
        await seed();
        await boot(t, pixels, dpr);
        await t.tap(find.text('Reports'));
        await settle(t);
        await shot(t, device, '03_reports');
      }, skip: !enabled);

      testWidgets('04 add unit', (t) async {
        await seed();
        await boot(t, pixels, dpr);
        // Centre FAB in the nav bar; at this point 'Add Unit' is unambiguous
        // (the sheet's save button with the same label isn't mounted yet).
        await t.tap(find.text('Add Unit'));
        await settle(t, 16);
        await shot(t, device, '04_add_unit');
      }, skip: !enabled);

      testWidgets('05 settings', (t) async {
        await seed();
        await boot(t, pixels, dpr);
        await t.tap(find.text('Settings'));
        await settle(t);
        await shot(t, device, '05_settings');
      }, skip: !enabled);
    });
  });
}
