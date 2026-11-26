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
import 'package:unit_ledger/domain/bs_calendar.dart';
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
/// Family name the loaded SF file is registered under (see `setUpAll`).
const shotFontFamily = 'SF';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final enabled = Platform.environment['RENTBEE_SHOTS'] == '1';
  // RENTBEE_SHOTS_MARKET=us renders the US storefront set: US Dollars, AD
  // dates and US-scale rents, written to store/raw_us/ instead of store/raw/.
  final us = Platform.environment['RENTBEE_SHOTS_MARKET'] == 'us';
  final rawDir = us ? 'raw_us' : 'raw';

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

    // The app uses the platform's system font (SF). The renders load the
    // Mac's own San Francisco file under the family the app is told to use,
    // so store shots show the real typeface an iPhone would.
    await load(shotFontFamily, '/System/Library/Fonts/SFNS.ttf');
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
    SharedPreferences.setMockInitialValues({
      'annual_raise_pct': 0.0,
      if (us) 'currency': 'usd',
      if (us) 'calendar_mode': 'ad',
    });
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
    // Utility charges for the current month (electricity, water, other), so
    // the unit sheet and the Reports "Charges & deductions" card have content.
    final charges = us
        ? const <String, (int, int, int)>{
            'A-01': (86, 40, 0),
            'A-02': (112, 40, 25),
            'A-03': (64, 40, 0),
            'B-02': (138, 40, 0),
            'C-01': (205, 60, 25),
          }
        : const <String, (int, int, int)>{
            'A-01': (1850, 300, 0),
            'A-02': (2400, 300, 500),
            'A-03': (1200, 300, 0),
            'B-02': (3100, 300, 0),
            'C-01': (4650, 600, 500),
          };
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
      final m0 = bsYearMonth(DateTime.now());
      final c = charges[code];
      if (c != null) {
        await repo.setCharges(id, m0.year, m0.month,
            electricity: c.$1, water: c.$2, service: c.$3);
      }
      if (code == 'A-01') {
        await repo.setDeduction(id, m0.year, m0.month,
            amount: us ? 120 : 1500,
            note: us ? 'Supplies for the building' : '2 sacks rice');
      }
      if (!paid) return;
      final unit =
          await (db.select(db.units)..where((u) => u.id.equals(id))).getSingle();
      // The app opens on the current BS month (see main.dart), so seed the
      // paid rows there.
      final m = bsYearMonth(DateTime.now());
      await repo.markPaid(unit, m.year, m.month, paidOn: DateTime.now());
    }

    // Eight units so the list fills an iPad canvas as well as a phone.
    if (us) {
      await add('A-01', 'Maria Alvarez', 'Grocery', 1450, 2900, true);
      await add('A-02', 'James Carter', 'Apartment', 1900, 1900, true);
      await add('A-03', 'Emily Nguyen', 'Studio', 1250, 1250, true);
      await add('B-01', 'David Kim', 'Barber shop', 2100, 4200, false);
      await add('B-02', 'Sarah Johnson', 'Salon', 2400, 4800, false);
      await add('B-03', 'Olivia Brown', 'Boutique', 2250, 4500, true);
      await add('C-01', 'Michael Davis', 'Cafe', 3200, 6400, true);
      await add('C-02', 'Daniel Wilson', 'Duplex', 2750, 2750, true);
    } else {
      await add('A-01', 'Maya Tamang', 'Grocery', 15000, 30000, true);
      await add('A-02', 'Sushant Regmi', 'Home', 22000, 44000, true);
      await add('A-03', 'Nabin Karki', 'Mobile repair', 14000, 28000, true);
      await add('B-01', 'Bikash Shrestha', 'Tailor', 12500, 25000, false);
      await add('B-02', 'Anita Gurung', 'Salon', 18000, 36000, false);
      await add('B-03', 'Sabina Rai', 'Boutique', 16500, 33000, true);
      await add('C-01', 'Ramesh Thapa', 'Cafe', 26000, 52000, true);
      await add('C-02', 'Deepak Magar', 'Hardware', 20000, 40000, true);
    }
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
        auth: auth,
        settings: settings,
        repo: repo,
        prefs: prefs,
        fontFamily: shotFontFamily));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    // A believable identity for the Settings shot instead of the guest label.
    auth.enterGuestMode(label: 'you@example.com');
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String device, String name) async {
    await expectLater(
      find.byType(UnitLedgerApp),
      matchesGoldenFile('../store/$rawDir/$device/$name.png'),
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
        await t.tap(find.text(us ? 'Maria Alvarez' : 'Maya Tamang'));
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
        // The Ledger header's 'Add Unit' action; at this point the label is
        // unambiguous (the sheet's save button with the same label isn't
        // mounted yet).
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
