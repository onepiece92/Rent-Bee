import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/account_deletion.dart';
import 'package:unit_ledger/data/database.dart';
import 'package:unit_ledger/data/firestore_sync_service.dart';
import 'package:unit_ledger/data/ledger_repository.dart';
import 'package:unit_ledger/main.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/state/settings_provider.dart';
import 'package:unit_ledger/ui/screens/phone_login_screen.dart';
import 'package:unit_ledger/ui/screens/settings_screen.dart';

/// Delete account (App Store guideline 5.1.1(v)): removes the cloud ledger,
/// the sign-in account and the ledger on this device — and only after the
/// owner has typed DELETE and signed in again as themselves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const owner = '+9779811111111';
  late AppDatabase db;
  late LedgerRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  group('AccountDeletion', () {
    late FakeFirebaseFirestore fs;
    Future<int> count(String uid, String col) async =>
        (await fs.collection('users').doc(uid).collection(col).get())
            .docs
            .length;

    setUp(() async {
      fs = FakeFirebaseFirestore();
      for (final uid in ['me', 'someone-else']) {
        final root = fs.collection('users').doc(uid);
        await root.set({'calendarMode': 'bs'});
        // More than one batch's worth, to cover paging.
        for (var i = 0; i < 450; i++) {
          await root.collection('units').doc('u$i').set({'code': 'A-$i'});
        }
        await root.collection('payments').doc('p1').set({'amount': 1});
        await root.collection('charges').doc('c1').set({'electricity': 1});
      }
      await repo.createUnit(UnitsCompanion.insert(
          code: 'A-01', tenantName: 'Asha', monthlyRent: 10000));
    });

    test('deletes the cloud ledger, then the account, then this device',
        () async {
      SharedPreferences.setMockInitialValues({});
      repo.sync = FirestoreSyncService(
          uid: 'me',
          repo: repo,
          prefs: await SharedPreferences.getInstance(),
          firestore: fs);
      final steps = <String>[];
      await AccountDeletion(
        repo: repo,
        firestore: fs,
        deleteUser: () async {
          // The account goes only once its data is already gone.
          steps.add('user (units left: ${await count('me', 'units')})');
        },
        revokeApple: () async => steps.add('apple'),
      ).run('me');

      expect(steps, ['apple', 'user (units left: 0)']);
      for (final c in AccountDeletion.ledgerCollections) {
        expect(await count('me', c), 0, reason: c);
      }
      expect((await fs.collection('users').doc('me').get()).exists, isFalse);
      expect(repo.sync, isNull, reason: 'sync stopped');
      expect(await repo.allUnits(), isEmpty, reason: 'this device wiped');

      // Nobody else's data is touched.
      expect(await count('someone-else', 'units'), 450);
      expect(await count('someone-else', 'payments'), 1);
    });

    test('if the account cannot be deleted, this device keeps its ledger',
        () async {
      await expectLater(
        AccountDeletion(
          repo: repo,
          firestore: fs,
          deleteUser: () async => throw FirebaseException(
              plugin: 'auth', code: 'requires-recent-login'),
        ).run('me'),
        throwsA(isA<FirebaseException>()),
      );
      expect(await repo.allUnits(), hasLength(1),
          reason: 'nothing local is lost; the owner can back up or retry');
    });

    test('a failed Apple revoke does not stop the deletion', () async {
      var deleted = false;
      await AccountDeletion(
        repo: repo,
        firestore: fs,
        deleteUser: () async => deleted = true,
        revokeApple: () async => throw StateError('network'),
      ).run('me');
      expect(deleted, isTrue);
    });
  });

  group('AuthProvider', () {
    late SharedPreferences prefs;
    Future<String> derive(String p, String s, int i) async => 'h:$p';
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('only a signed-in owner can delete; guests cannot', () {
      final guest = AuthProvider.forTest(prefs, derive)..enterGuestMode();
      expect(guest.canDeleteAccount, isFalse);
      guest.startAccountDeletion();
      expect(guest.deletingAccount, isFalse);

      final fresh = AuthProvider.forTest(prefs, derive);
      expect(fresh.canDeleteAccount, isFalse);
    });

    test('start, cancel, identity check, finish', () async {
      final auth = AuthProvider.forTest(prefs, derive, phone: owner);
      await auth.setPin('1234');
      auth.startAccountDeletion();
      expect(auth.deletingAccount, isTrue);
      expect(auth.reverifying, isTrue);
      auth.cancelAccountDeletion();
      expect(auth.deletingAccount, isFalse);
      expect(auth.hasPin, isTrue);

      expect(auth.isOwnIdentity(owner), isTrue);
      expect(auth.isOwnIdentity('+9779800000001'), isFalse);

      auth.startAccountDeletion();
      await auth.finishAccountDeletion();
      expect(auth.deletingAccount, isFalse);
      expect(auth.phoneVerified, isFalse);
      expect(auth.hasPin, isFalse);
    });

    test('locking the app abandons a deletion', () {
      final auth = AuthProvider.forTest(prefs, derive, phone: owner);
      auth.startAccountDeletion();
      auth.lock();
      expect(auth.deletingAccount, isFalse);
    });
  });

  group('Settings', () {
    late SharedPreferences prefs;
    late AuthProvider auth;
    setUp(() async {
      SharedPreferences.setMockInitialValues({'annual_raise_pct': 0.0});
      prefs = await SharedPreferences.getInstance();
    });

    Future<void> settle(WidgetTester t, [int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
    }

    Future<void> openSettings(WidgetTester t, AuthProvider a) async {
      auth = a;
      t.view.physicalSize = const Size(412, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(UnitLedgerApp(
          auth: auth,
          settings: SettingsProvider(prefs),
          repo: repo,
          prefs: prefs));
      await settle(t, 20);
      await t.tap(find.text('Settings').last);
      await settle(t);
    }

    testWidgets('guest sessions have no Delete account', (t) async {
      await openSettings(
          t,
          AuthProvider.forTest(prefs, (p, s, i) async => 'h:$p')
            ..enterGuestMode());
      expect(find.text('Delete account', skipOffstage: false), findsNothing);
    });

    testWidgets('typing DELETE leads to sign-in; cancelling changes nothing',
        (t) async {
      final a =
          AuthProvider.forTest(prefs, (p, s, i) async => 'h:$p', phone: owner);
      await a.setPin('1234'); // unlocks
      await openSettings(t, a);

      final list = find
          .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable))
          .first;
      await t.scrollUntilVisible(find.text('Delete account'), 200,
          scrollable: list);
      // Clear the floating tab bar.
      await t.drag(list, const Offset(0, -250));
      await settle(t);
      await t.tap(find.text('Delete account'));
      await settle(t);
      expect(find.text('Delete your account?'), findsOneWidget);

      TextButton action(String label) => t.widget<TextButton>(find.ancestor(
          of: find.text(label), matching: find.byType(TextButton)));
      expect(action('Continue').onPressed, isNull, reason: 'not typed yet');
      await t.enterText(find.byType(TextField).last, 'delete');
      await t.pump();
      await t.tap(find.text('Continue'));
      await settle(t, 20);

      // The sign-in screen, fixed to this owner, explains why.
      expect(find.byType(PhoneLoginScreen), findsOneWidget);
      expect(find.textContaining('To delete your account'), findsOneWidget);
      expect(find.text('Continue as guest (debug)'), findsNothing);

      await t.tap(find.text('Cancel, keep my account'));
      await settle(t, 20);
      expect(find.byType(PhoneLoginScreen), findsNothing);
      expect(auth.deletingAccount, isFalse);
      expect(auth.phoneVerified, isTrue);
      expect(auth.hasPin, isTrue);
      await t.pump(const Duration(seconds: 3));
    });
  });
}
