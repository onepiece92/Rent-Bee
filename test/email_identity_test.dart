import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/domain/email.dart';
import 'package:unit_ledger/state/auth_provider.dart';

void main() {
  test('emails are normalized to one lower-case identity', () {
    expect(normalizeEmail('  Owner@Gmail.COM '), 'owner@gmail.com');
  });

  test('emailError accepts real addresses and rejects malformed ones', () {
    expect(emailError('owner@gmail.com'), isNull);
    expect(emailError(' Owner@Example.co.uk '), isNull);
    expect(emailError(''), 'Enter your email address');
    for (final bad in ['owner', 'owner@', '@gmail.com', 'owner@gmail', 'a b@x.com', 'a@b@c.com']) {
      expect(emailError(bad), 'Enter a valid email address', reason: bad);
    }
  });

  test('an identity is an email only when it has an @', () {
    expect(isEmailIdentity('owner@gmail.com'), isTrue);
    expect(isEmailIdentity('+9779801234501'), isFalse);
    expect(isEmailIdentity(null), isFalse);
  });

  group('an email-signed-in owner', () {
    late SharedPreferences prefs;
    Future<String> derive(String pin, String salt, int iters) async =>
        'hash:$pin';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('is recorded, survives a restart, and reads as an email sign-in',
        () async {
      final auth = await AuthProvider.load(prefs, derive: derive);
      await auth.recordPhoneVerification('owner@gmail.com', 'uid-1');
      expect(auth.phoneVerified, isTrue);
      expect(auth.signedInWithEmail, isTrue);

      final again = await AuthProvider.load(prefs, derive: derive);
      expect(again.phone, 'owner@gmail.com');
      expect(again.uid, 'uid-1');
      expect(again.signedInWithEmail, isTrue);
    });

    test('resets a forgotten PIN only by signing in as the same email',
        () async {
      final auth = await AuthProvider.load(prefs, derive: derive);
      await auth.recordPhoneVerification('owner@gmail.com', 'uid-1');
      await auth.setPin('1234');
      auth.lock();

      auth.startPinReset();
      expect(auth.resettingPin, isTrue);
      expect(await auth.completePinReset('other@gmail.com', 'uid-2'), isFalse);
      expect(auth.hasPin, isTrue, reason: 'a different account changes nothing');

      expect(await auth.completePinReset('owner@gmail.com', 'uid-1'), isTrue);
      expect(auth.hasPin, isFalse);
      expect(auth.phone, 'owner@gmail.com');
    });
  });
}
