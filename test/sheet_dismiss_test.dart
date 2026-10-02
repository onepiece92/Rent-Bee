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
import 'package:unit_ledger/ui/sheets/unit_detail_sheet.dart';

/// Every bottom sheet must always be leavable (see `sheet_scaffold.dart`):
/// close button, dimmed-area tap, swipe down, system back — including when the
/// content scrolls and when the keyboard is up, the two cases that used to
/// leave an iPhone user with no way out.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late LedgerRepository repo;
  late AuthProvider auth;
  late SettingsProvider settings;
  late SharedPreferences prefs;
  Future<String> fastDerive(String pin, String salt, int iters) async =>
      'hash:$pin';

  const bothPlatforms = TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.iOS, TargetPlatform.android});

  setUp(() async {
    SharedPreferences.setMockInitialValues({'annual_raise_pct': 0.0});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    auth = AuthProvider.forTest(prefs, fastDerive);
    settings = SettingsProvider(prefs);
    await repo.createUnit(UnitsCompanion.insert(
        code: 'A-01',
        tenantName: 'Maya Tamang',
        monthlyRent: 15000,
        startedOn: Value(DateTime(2024, 6, 15))));
  });
  tearDown(() => db.close());

  // The shell has a carousel timer, so never pumpAndSettle.
  Future<void> settle(WidgetTester t, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  /// iPhone-class canvas (393 × 852) with a 59 pt status-bar inset.
  Future<void> boot(WidgetTester t) async {
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1.0;
    t.view.viewPadding = const FakeViewPadding(top: 59);
    t.view.padding = const FakeViewPadding(top: 59);
    addTearDown(t.view.reset);
    await t.pumpWidget(UnitLedgerApp(
        auth: auth, settings: settings, repo: repo, prefs: prefs));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    auth.enterGuestMode();
    await settle(t);
  }

  Future<void> openDetail(WidgetTester t) async {
    await t.tap(find.text('Maya Tamang'));
    await settle(t, 16);
    expect(find.byType(UnitDetailSheet), findsOneWidget);
  }

  Future<void> openAdd(WidgetTester t) async {
    await t.tap(find.text('Add Unit'));
    await settle(t, 16);
    expect(find.byType(EditUnitSheet), findsOneWidget);
  }

  // The close button sits in the pinned header, so its top is the sheet's top.
  double sheetTop(WidgetTester t) => t.getRect(find.byTooltip('Close').last).top;

  group('unit detail sheet (content scrolls)', () {
    testWidgets('the close button closes it', (t) async {
      await boot(t);
      await openDetail(t);
      await t.tap(find.byTooltip('Close'));
      await settle(t);
      expect(find.byType(UnitDetailSheet), findsNothing);
    });

    testWidgets('a tap on the dimmed area closes it', (t) async {
      await boot(t);
      await openDetail(t);
      await t.tapAt(Offset(196, sheetTop(t) - 10));
      await settle(t);
      expect(find.byType(UnitDetailSheet), findsNothing);
    });

    testWidgets('swiping the header down closes it', (t) async {
      await boot(t);
      await openDetail(t);
      await t.dragFrom(Offset(120, sheetTop(t) + 12), const Offset(0, 500));
      await settle(t, 20);
      expect(find.byType(UnitDetailSheet), findsNothing);
    }, variant: bothPlatforms);

    testWidgets('pulling the content down from the top closes it', (t) async {
      await boot(t);
      await openDetail(t);
      await t.dragFrom(const Offset(196, 500), const Offset(0, 400));
      await settle(t, 20);
      expect(find.byType(UnitDetailSheet), findsNothing);
    }, variant: bothPlatforms);

    testWidgets('scrolling back down within the content does not close it',
        (t) async {
      await boot(t);
      await openDetail(t);
      await t.dragFrom(const Offset(196, 600), const Offset(0, -200));
      await settle(t);
      await t.dragFrom(const Offset(196, 400), const Offset(0, 120));
      await settle(t, 20);
      expect(find.byType(UnitDetailSheet), findsOneWidget);
    }, variant: bothPlatforms);

    testWidgets('one long drag from mid-content past the top does not close it',
        (t) async {
      // Scroll down, then drag all the way back up and beyond in one gesture:
      // that is scrolling, not a dismissal — a half-filled form must survive.
      await boot(t);
      await openDetail(t);
      await t.dragFrom(const Offset(196, 600), const Offset(0, -200));
      await settle(t);
      await t.dragFrom(const Offset(196, 300), const Offset(0, 450));
      await settle(t, 20);
      expect(find.byType(UnitDetailSheet), findsOneWidget);
    }, variant: bothPlatforms);

    testWidgets('system back closes it', (t) async {
      await boot(t);
      await openDetail(t);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.byType(UnitDetailSheet), findsNothing);
    });
  });

  group('add unit sheet with the keyboard up', () {
    Future<void> openWithKeyboard(WidgetTester t) async {
      await boot(t);
      await openAdd(t);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await settle(t, 8);
    }

    testWidgets('stays below the status bar, leaving a tappable strip',
        (t) async {
      await openWithKeyboard(t);
      // 59 pt status bar + a 44 pt strip of dimmed area to tap.
      expect(sheetTop(t), greaterThanOrEqualTo(59 + 44));
      await t.tapAt(Offset(196, sheetTop(t) - 20));
      await settle(t);
      expect(find.byType(EditUnitSheet), findsNothing);
    }, variant: bothPlatforms);

    testWidgets('the close button is still on screen and works', (t) async {
      await openWithKeyboard(t);
      final close = t.getRect(find.byTooltip('Close'));
      expect(close.top, greaterThanOrEqualTo(59));
      expect(close.bottom, lessThanOrEqualTo(852 - 300));
      await t.tap(find.byTooltip('Close'));
      await settle(t);
      expect(find.byType(EditUnitSheet), findsNothing);
    }, variant: bothPlatforms);

    testWidgets('tapping an empty part of the sheet drops the keyboard focus',
        (t) async {
      await openWithKeyboard(t);
      // Any field (the Ledger's search box behind the sheet counts as one of
      // the EditableTexts, so check them all rather than by index).
      bool anyFocused() => t
          .widgetList<EditableText>(find.byType(EditableText))
          .any((e) => e.focusNode.hasFocus);
      await t.tap(find.byType(TextFormField).first);
      await settle(t, 4);
      expect(anyFocused(), isTrue); // fields still take focus on tap
      await t.tap(find.text('New Unit')); // a non-interactive spot
      await settle(t, 4);
      expect(anyFocused(), isFalse);
      expect(find.byType(EditUnitSheet), findsOneWidget); // sheet stays open
    });
  });

  group('stacked sheets', () {
    Future<void> openEditOverDetail(WidgetTester t) async {
      await boot(t);
      await openDetail(t);
      await t.tap(find.byIcon(Icons.edit_outlined).first);
      await settle(t, 16);
      expect(find.byType(EditUnitSheet), findsOneWidget);
    }

    testWidgets('close and Save each dismiss only the top sheet', (t) async {
      await openEditOverDetail(t);
      await t.tap(find.byTooltip('Close').last);
      await settle(t);
      expect(find.byType(EditUnitSheet), findsNothing);
      expect(find.byType(UnitDetailSheet), findsOneWidget);

      await t.tap(find.byIcon(Icons.edit_outlined).first);
      await settle(t, 16);
      await t.tap(find.text('Save changes'));
      await settle(t, 16);
      expect(find.byType(EditUnitSheet), findsNothing);
      expect(find.byType(UnitDetailSheet), findsOneWidget);
      // The save notifies the ledger while the detail sheet is open; its
      // sections must reload without tripping setState's Future check.
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 3)); // let any toast finish
      await settle(t);
    });

    testWidgets('locking the app closes every open sheet', (t) async {
      await openEditOverDetail(t);
      auth.lock();
      await settle(t, 16);
      expect(find.byType(EditUnitSheet), findsNothing);
      expect(find.byType(UnitDetailSheet), findsNothing);
    });
  });
}
