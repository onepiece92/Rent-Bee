import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/state/auth_provider.dart';
import 'package:unit_ledger/ui/screens/login_screen.dart';
import 'package:unit_ledger/ui/screens/set_pin_screen.dart';

/// Regression tests for the two unlock/onboarding bugs: an exception thrown by
/// PIN derivation used to leave the submit button spinning forever with no way
/// to retry. These force a derive failure and assert the screen recovers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget host(AuthProvider auth, Widget screen) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(home: screen),
    );
  }

  Future<String> throwingDerive(String pin, String salt, int iters) async =>
      throw StateError('isolate failed');

  Future<String> Function(String, String, int) constDerive(String value) =>
      (pin, salt, iters) async => value;

  group('LoginScreen', () {
    testWidgets('a derive failure shows an error and re-enables Unlock',
        (tester) async {
      // Stored PIN material exists, but deriving the entered PIN throws.
      final auth = AuthProvider.forTest(prefs, throwingDerive,
          hash: 'storedhash', salt: 'salt');

      await tester.pumpWidget(host(auth, const LoginScreen()));
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pump(); // process tap setState (_busy=true)
      await tester.pump(const Duration(milliseconds: 50)); // resolve derive + catch setState

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      // Button is enabled again (not stuck spinning) — tappable callback present.
      final button =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Unlock'));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('a wrong PIN shows "Incorrect PIN" and stays usable',
        (tester) async {
      // Derive returns a value that won't match the stored hash.
      final auth = AuthProvider.forTest(prefs, constDerive('different'),
          hash: 'storedhash', salt: 'salt');

      await tester.pumpWidget(host(auth, const LoginScreen()));
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pump(); // process tap setState (_busy=true)
      await tester.pump(const Duration(milliseconds: 50)); // resolve derive + catch setState

      expect(find.text('Incorrect PIN'), findsOneWidget);
      final button =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Unlock'));
      expect(button.onPressed, isNotNull);
    });
  });

  group('SetPinScreen', () {
    testWidgets('a derive failure shows an error and re-enables Create PIN',
        (tester) async {
      final auth = AuthProvider.forTest(prefs, throwingDerive, phone: '+9779800000000');

      await tester.pumpWidget(host(auth, const SetPinScreen()));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '1234'); // PIN
      await tester.enterText(fields.at(1), '1234'); // Confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Create PIN'));
      await tester.pump(); // process tap setState (_busy=true)
      await tester.pump(const Duration(milliseconds: 50)); // resolve derive + catch setState

      expect(find.text('Could not save your PIN. Please try again.'),
          findsOneWidget);
      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create PIN'));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('mismatched PINs are rejected before any derivation',
        (tester) async {
      // Derive would throw, but validation should short-circuit before it runs.
      final auth = AuthProvider.forTest(prefs, throwingDerive);

      await tester.pumpWidget(host(auth, const SetPinScreen()));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '1234');
      await tester.enterText(fields.at(1), '5678');
      await tester.tap(find.widgetWithText(FilledButton, 'Create PIN'));
      await tester.pump(); // process tap setState (_busy=true)
      await tester.pump(const Duration(milliseconds: 50)); // resolve derive + catch setState

      expect(find.text('PINs do not match'), findsOneWidget);
    });
  });
}
