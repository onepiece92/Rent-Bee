import 'package:firebase_auth/firebase_auth.dart';

/// Thin wrapper around Firebase phone authentication.
///
/// All `firebase_auth` usage is isolated here so the rest of the app stays
/// PIN-based and offline. Firebase is only ever exercised during the one-time
/// onboarding verification — see [AuthProvider.recordPhoneVerification].
class PhoneAuthService {
  final FirebaseAuth _auth;
  PhoneAuthService([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  /// Starts verification for [phoneE164] (must be E.164, e.g. `+9779801234501`).
  ///
  /// On Android the SMS code may be auto-retrieved or the number instantly
  /// verified, in which case [onAutoVerified] fires with a ready-to-use [User]
  /// and the manual code step can be skipped. Otherwise [onCodeSent] delivers a
  /// `verificationId` to pair with the code the user types — pass both to
  /// [confirmOtp].
  Future<void> verifyPhoneNumber({
    required String phoneE164,
    required void Function(String verificationId) onCodeSent,
    required void Function(User user) onAutoVerified,
    required void Function(String message) onError,
    void Function(String verificationId)? onTimeout,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final cred = await _auth.signInWithCredential(credential);
          final user = cred.user;
          if (user != null) onAutoVerified(user);
        } on FirebaseAuthException catch (e) {
          onError(_message(e));
        }
      },
      verificationFailed: (FirebaseAuthException e) => onError(_message(e)),
      codeSent: (String verificationId, int? _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (String verificationId) =>
          onTimeout?.call(verificationId),
    );
  }

  /// Confirms the SMS [smsCode] the user typed against the [verificationId] from
  /// [verifyPhoneNumber]'s `onCodeSent`, signing them in. Returns the [User].
  /// Throws [FirebaseAuthException] (e.g. `invalid-verification-code`).
  Future<User> confirmOtp(String verificationId, String smsCode) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final cred = await _auth.signInWithCredential(credential);
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'Sign-in succeeded but returned no user.',
      );
    }
    return user;
  }

  /// Maps a [FirebaseAuthException] to a short, user-facing message.
  static String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That phone number looks invalid.';
      case 'invalid-verification-code':
        return 'Incorrect code. Check the SMS and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'session-expired':
        return 'The code expired. Request a new one.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return e.message ?? 'Verification failed (${e.code}).';
    }
  }
}
