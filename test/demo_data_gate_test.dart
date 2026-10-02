import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/app/theme.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/firestore_sync_service.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/data/otp_quota_service.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/domain/test_accounts.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/state/ledger_provider.dart';
import 'package:unit_ledger/state/settings_provider.dart';
import 'package:unit_ledger/state/sync_status.dart';
import 'package:unit_ledger/ui/screens/settings_screen.dart';

/// "Generate demo data" replaces the whole ledger (and the cloud copy), so a
/// real owner's logged-in account must never be offered it. Only the
/// store-review test login and the debug guest session are.
void main() {
  Future<String> derive(String pin, String salt, int iters) async => 'h:$pin';
  const realOwner = '+9779801234501';
  final testLogin = reviewTestNumbers.first;

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('AuthProvider.canGenerateDemoData', () {
    test('a real owner account cannot', () {
      final auth = AuthProvider.forTest(prefs, derive, phone: realOwner);
      expect(auth.isTestAccount, isFalse);
      expect(auth.canGenerateDemoData, isFalse);
    });

    test('the store-review test login can', () {
      final auth = AuthProvider.forTest(prefs, derive, phone: testLogin);
      expect(auth.isTestAccount, isTrue);
      expect(auth.canGenerateDemoData, isTrue);
    });

    test('the debug guest session can', () {
      final auth = AuthProvider.forTest(prefs, derive)..enterGuestMode();
      expect(auth.isTestAccount, isFalse);
      expect(auth.canGenerateDemoData, isTrue);
    });

    test('a session with no identity cannot', () {
      expect(AuthProvider.forTest(prefs, derive).canGenerateDemoData, isFalse);
    });

    test('the test logins are the OTP-exempt review numbers (one list)', () {
      expect(OtpQuotaService.exemptNumbers, same(reviewTestNumbers));
    });
  });

  group('Settings › Data', () {
    Future<void> pumpSettings(WidgetTester t, AuthProvider auth,
        {bool synced = false}) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LedgerRepository(db);
      if (synced) {
        // A live cloud mirror, backed by an in-memory Firestore.
        repo.sync = FirestoreSyncService(
            uid: 'u1',
            repo: repo,
            prefs: prefs,
            firestore: FakeFirebaseFirestore());
      }
      t.view.physicalSize = const Size(412, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
          ChangeNotifierProvider(
              create: (_) =>
                  LedgerProvider(repo, initialMonth: const BsMonth(2082, 2))),
          ChangeNotifierProvider(create: (_) => SyncStatusController()),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ));
      await t.pump();
      // Jump to the end of the list, where the Data section lives.
      await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await t.pump(const Duration(milliseconds: 300));
      // Proof we reached the Data section, whichever account this is.
      expect(find.text('Erase all data'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
    }

    testWidgets('a real owner account is not offered demo data', (t) async {
      await pumpSettings(t, AuthProvider.forTest(prefs, derive, phone: realOwner));
      expect(find.text('Generate demo data'), findsNothing);
    });

    testWidgets('the store-review test login is', (t) async {
      await pumpSettings(t, AuthProvider.forTest(prefs, derive, phone: testLogin));
      expect(find.text('Generate demo data'), findsOneWidget);
    });

    testWidgets('the debug guest session is', (t) async {
      await pumpSettings(
          t, AuthProvider.forTest(prefs, derive)..enterGuestMode());
      expect(find.text('Generate demo data'), findsOneWidget);
      // No cloud mirror → erasing is described as local only.
      expect(find.text('Delete every unit and payment'), findsOneWidget);
    });

    testWidgets(
        'with cloud sync on, even an empty ledger needs REPLACE typed',
        (t) async {
      // The local ledger being empty proves nothing when a cloud copy exists
      // (it may not have been pulled yet) — and generation replaces that too.
      await pumpSettings(
          t, AuthProvider.forTest(prefs, derive, phone: testLogin),
          synced: true);
      expect(find.text('Delete every unit and payment, on all your devices'),
          findsOneWidget);

      await t.tap(find.text('Generate demo data'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Type REPLACE to confirm.'), findsOneWidget);
      expect(find.textContaining('deletes everything in this account'),
          findsOneWidget);
      expect(find.textContaining('every other device'), findsOneWidget);

      await t.tap(find.text('Cancel'));
      await t.pump(const Duration(milliseconds: 400));
    });
  });
}
