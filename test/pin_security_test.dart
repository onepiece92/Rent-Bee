import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/app/router.dart';
import 'package:unit_ledger/data/phone_auth_service.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/ui/screens/login_screen.dart';

/// The lock screen: guessing is rate-limited and survives a restart (B09),
/// a forgotten PIN can be reset only by the number the device was set up
/// with (B09), the PIN material is one value (B30) at a work factor that
/// does not make every unlock wait (S5), and a failed Firebase start is
/// retried (B29).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phone = '+9779811111111';
  late SharedPreferences prefs;
  var derives = 0;

  // Instant stand-in for PBKDF2 that still depends on pin, salt and rounds.
  Future<String> derive(String pin, String salt, int iters) async {
    derives++;
    return 'h($pin,$salt,$iters)';
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    derives = 0;
  });

  /// An onboarded owner with PIN 1234, loaded the way the app loads it.
  Future<AuthProvider> owner() async {
    await prefs.setString('phone_number', phone);
    await prefs.setString('phone_uid', 'uid-1');
    final setup = await AuthProvider.load(prefs, derive: derive);
    await setup.setPin('1234');
    return AuthProvider.load(prefs, derive: derive);
  }

  group('attempt limit (B09)', () {
    test('the timeout schedule', () {
      expect(AuthProvider.lockoutFor(0), Duration.zero);
      expect(AuthProvider.lockoutFor(4), Duration.zero);
      expect(AuthProvider.lockoutFor(5), const Duration(seconds: 30));
      expect(AuthProvider.lockoutFor(6), const Duration(minutes: 1));
      expect(AuthProvider.lockoutFor(7), const Duration(minutes: 5));
      expect(AuthProvider.lockoutFor(8), const Duration(minutes: 15));
      expect(AuthProvider.lockoutFor(9), const Duration(hours: 1));
      expect(AuthProvider.lockoutFor(500), const Duration(hours: 1));
    });

    test('five wrong PINs lock the screen; the right PIN is refused meanwhile',
        () async {
      final auth = await owner();
      var clock = DateTime(2026, 10, 2, 12);
      auth.now = () => clock;

      for (var i = 0; i < 4; i++) {
        expect(await auth.unlock('0000'), isFalse);
        expect(auth.lockoutRemaining, Duration.zero);
      }
      expect(await auth.unlock('0000'), isFalse);
      expect(auth.failedAttempts, 5);
      expect(auth.lockoutRemaining, const Duration(seconds: 30));

      // Locked out: nothing is even checked, right PIN or wrong.
      final before = derives;
      expect(await auth.unlock('1234'), isFalse);
      expect(await auth.unlock('0000'), isFalse);
      expect(derives, before);
      expect(auth.failedAttempts, 5, reason: 'refused tries are not counted');
      expect(auth.unlocked, isFalse);

      clock = clock.add(const Duration(seconds: 31));
      expect(auth.lockoutRemaining, Duration.zero);
      // The next miss waits longer…
      expect(await auth.unlock('0000'), isFalse);
      expect(auth.lockoutRemaining, const Duration(minutes: 1));
      clock = clock.add(const Duration(minutes: 2));
      // …and the right PIN clears the count.
      expect(await auth.unlock('1234'), isTrue);
      expect(auth.failedAttempts, 0);
      expect(prefs.containsKey('pin_lockout'), isFalse);
    });

    test('quitting the app does not reset the count or the timeout',
        () async {
      final auth = await owner();
      final clock = DateTime(2026, 10, 2, 12);
      auth.now = () => clock;
      for (var i = 0; i < 6; i++) {
        await auth.unlock('0000');
        // (walk past the first timeout to reach the sixth miss)
        if (i == 4) auth.now = () => clock.add(const Duration(seconds: 31));
      }
      expect(auth.failedAttempts, 6);

      final relaunched = await AuthProvider.load(prefs, derive: derive);
      relaunched.now = () => clock.add(const Duration(seconds: 40));
      expect(relaunched.failedAttempts, 6);
      expect(relaunched.lockoutRemaining, const Duration(seconds: 51));
      expect(await relaunched.unlock('1234'), isFalse);
    });

    test('setting the clock back cannot stretch a timeout', () async {
      final auth = await owner();
      var clock = DateTime(2026, 10, 2, 12);
      auth.now = () => clock;
      for (var i = 0; i < 5; i++) {
        await auth.unlock('0000');
      }
      clock = DateTime(2020); // years earlier
      expect(auth.lockoutRemaining, const Duration(seconds: 30));
    });
  });

  group('forgot PIN (B09)', () {
    test('only the recorded number clears the PIN', () async {
      final auth = await owner();
      expect(auth.canResetPin, isTrue);
      auth.startPinReset();
      expect(auth.resettingPin, isTrue);

      // Someone verifies a different number: nothing changes.
      expect(await auth.completePinReset('+9779800000001', 'uid-x'), isFalse);
      expect(auth.hasPin, isTrue);
      expect(auth.resettingPin, isTrue);
      expect(auth.uid, 'uid-1');

      expect(await auth.completePinReset(phone, 'uid-1'), isTrue);
      expect(auth.hasPin, isFalse, reason: 'the owner now sets a new PIN');
      expect(auth.resettingPin, isFalse);
      expect(auth.phone, phone, reason: 'identity (and so the ledger) kept');
      expect(auth.unlocked, isFalse);

      await auth.setPin('4321');
      final relaunched = await AuthProvider.load(prefs, derive: derive);
      expect(await relaunched.unlock('1234'), isFalse);
      expect(await relaunched.unlock('4321'), isTrue);
    });

    test('a reset that was never started cannot be completed', () async {
      final auth = await owner();
      expect(await auth.completePinReset(phone, 'uid-1'), isFalse);
      expect(auth.hasPin, isTrue);
    });

    test('cancelling returns to the lock screen with the PIN intact; a '
        'successful reset also clears a running timeout', () async {
      final auth = await owner();
      auth.now = () => DateTime(2026, 10, 2, 12);
      for (var i = 0; i < 5; i++) {
        await auth.unlock('0000');
      }
      auth.startPinReset();
      auth.cancelPinReset();
      expect(auth.resettingPin, isFalse);
      expect(auth.hasPin, isTrue);
      expect(auth.lockoutRemaining, const Duration(seconds: 30));

      auth.startPinReset();
      expect(await auth.completePinReset(phone, 'uid-1'), isTrue);
      expect(auth.lockoutRemaining, Duration.zero);
      expect(auth.failedAttempts, 0);
    });

    test('the guest session and a device with no PIN have nothing to reset',
        () async {
      final fresh = await AuthProvider.load(prefs, derive: derive);
      expect(fresh.canResetPin, isFalse);
      fresh.enterGuestMode();
      expect(fresh.canResetPin, isFalse);
      fresh.startPinReset();
      expect(fresh.resettingPin, isFalse);
    });

    testWidgets('lock screen → Forgot PIN → verification → back',
        (tester) async {
      final auth = await owner();
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp.router(routerConfig: buildRouter(auth)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Enter your PIN to continue'), findsOneWidget);

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      expect(find.textContaining(phone), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Verification, fixed to the recorded number.
      expect(find.textContaining('Forgot your PIN?'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, phone);
      expect(field.readOnly, isTrue);
      expect(find.text('Continue as guest (debug)'), findsNothing);

      await tester.tap(find.text('Back to PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your PIN to continue'), findsOneWidget);
      expect(auth.hasPin, isTrue);
    });
  });

  group('lock screen countdown (B09)', () {
    testWidgets('warns before the limit, then counts down and re-enables',
        (tester) async {
      final auth = await owner();
      var clock = DateTime(2026, 10, 2, 12);
      auth.now = () => clock;
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: LoginScreen()),
      ));

      FilledButton unlockButton() => tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Unlock'));
      Future<void> wrong() async {
        await tester.enterText(find.byType(TextField), '0000');
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      await wrong();
      expect(find.text('Incorrect PIN'), findsOneWidget);
      await wrong();
      await wrong();
      expect(find.text('Incorrect PIN · 2 tries left'), findsOneWidget);
      await wrong();
      expect(find.text('Incorrect PIN · 1 try left'), findsOneWidget);
      await wrong();
      expect(find.text('Too many wrong PINs. Try again in 0:30.'),
          findsOneWidget);
      expect(unlockButton().onPressed, isNull);

      clock = clock.add(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Too many wrong PINs. Try again in 0:18.'),
          findsOneWidget);

      clock = clock.add(const Duration(seconds: 19));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Too many wrong PINs'), findsNothing);
      expect(unlockButton().onPressed, isNotNull);
      // The ticker stopped: nothing is left pending at teardown.
    });
  });

  group('PIN storage (B30, S5)', () {
    test('the PIN is one stored value, replaced in one write', () async {
      final auth = await owner();
      expect(prefs.containsKey('pin_hash'), isFalse);
      expect(prefs.containsKey('pin_salt'), isFalse);
      expect(prefs.containsKey('pin_iterations'), isFalse);
      final record = jsonDecode(prefs.getString('pin_record')!) as Map;
      expect(record.keys.toSet(), {'i', 's', 'h'});
      expect(record['i'], 20000);
      expect(AuthProvider.hasExistingInstall(prefs), isTrue);
      expect(await auth.unlock('1234'), isTrue);
    });

    test('a PIN from an older build (three keys, 100k rounds) still unlocks, '
        'and is rewritten as one record at the current rounds', () async {
      SharedPreferences.setMockInitialValues({
        'phone_number': phone,
        'pin_salt': 'oldsalt',
        'pin_hash': 'h(1234,oldsalt,100000)',
        'pin_iterations': 100000,
      });
      prefs = await SharedPreferences.getInstance();
      expect(AuthProvider.hasExistingInstall(prefs), isTrue);
      final auth = await AuthProvider.load(prefs, derive: derive);
      expect(auth.hasPin, isTrue);

      expect(await auth.unlock('9999'), isFalse);
      expect(prefs.containsKey('pin_record'), isFalse, reason: 'no PIN known');
      expect(await auth.unlock('1234'), isTrue);
      await Future<void>.delayed(Duration.zero); // the background rewrite

      final record = jsonDecode(prefs.getString('pin_record')!) as Map;
      expect(record['i'], 20000);
      expect(prefs.containsKey('pin_hash'), isFalse);
      final relaunched = await AuthProvider.load(prefs, derive: derive);
      expect(await relaunched.unlock('1234'), isTrue);
      expect(await relaunched.unlock('9999'), isFalse);
    });

    test('a half-written legacy PIN next to a record: the record wins',
        () async {
      await owner();
      // Leftovers an interrupted older build could have left behind.
      await prefs.setString('pin_salt', 'stray');
      final auth = await AuthProvider.load(prefs, derive: derive);
      expect(await auth.unlock('1234'), isTrue);
    });

    test('sign-out removes every trace', () async {
      final auth = await owner();
      await auth.unlock('0000');
      await auth.resetIdentity();
      expect(prefs.getKeys().where((k) => k.startsWith('pin_')), isEmpty);
      expect(auth.hasPin, isFalse);
      expect(auth.failedAttempts, 0);
    });

    test('the real derivation: right PIN in, wrong PIN out', () async {
      final setup = await AuthProvider.load(prefs); // real PBKDF2, in an isolate
      final sw = Stopwatch()..start();
      await setup.setPin('2468');
      final auth = await AuthProvider.load(prefs);
      expect(await auth.unlock('2469'), isFalse);
      expect(await auth.unlock('2468'), isTrue);
      // ignore: avoid_print
      print('3 real derivations: ${sw.elapsedMilliseconds} ms');
    });
  });

  group('Firebase start (B29)', () {
    test('a failed start is retried; a successful one runs once', () async {
      var calls = 0;
      var online = false;
      final init = RetryableOnce(() async {
        calls++;
        if (!online) throw StateError('no network');
      });

      await expectLater(init(), throwsStateError);
      await expectLater(init(), throwsStateError);
      expect(calls, 2, reason: 'the failure used to be cached forever');

      online = true;
      await init();
      await init();
      expect(calls, 3);
    });

    test('callers during one attempt share it', () async {
      var calls = 0;
      final init = RetryableOnce(() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await Future.wait([init(), init(), init()]);
      expect(calls, 1);
    });
  });
}
