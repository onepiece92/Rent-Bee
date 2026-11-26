import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/email.dart';
import '../firebase_options.dart';
import 'phone_auth_service.dart';

/// A sign-in that failed, with a message fit to show the owner. [cancelled]
/// marks the owner backing out of a system sheet — nothing to report.
class AccountAuthException implements Exception {
  final String message;
  final bool cancelled;
  const AccountAuthException(this.message, {this.cancelled = false});

  @override
  String toString() => message;
}

/// The signed-in Firebase account: its uid and the identity it is recorded
/// under on this device (a lower-cased email).
typedef SignedInAccount = ({String uid, String identity});

/// The email-based sign-ins: Google, Apple, and a 6-digit code sent by email.
///
/// One Firebase account per email, so several people who can use the same
/// Google account or read the same inbox land on the same ledger. The emailed
/// code is issued and checked by two Cloud Functions (`functions/index.js`),
/// which hand back a custom token for the account that owns the address.
class AccountAuthService {
  /// Where the callable functions are deployed (see `functions/index.js`).
  static const functionsRegion = 'asia-south1';

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: functionsRegion);

  /// Google sign-in is offered where the native SDK is set up.
  static bool get googleAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Needs the Apple provider enabled in Firebase and the Sign in with Apple
  /// capability on the App ID; the button fails without both.
  static const appleSignInReady = true;

  /// Apple requires Sign in with Apple wherever Google sign-in is offered.
  static bool get appleAvailable =>
      appleSignInReady &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Off until the two Cloud Functions in `functions/` are deployed; without
  /// them the emailed code can never be sent.
  static const emailCodeReady = false;

  static bool _googleReady = false;

  Future<SignedInAccount> signInWithGoogle() async {
    await PhoneAuthService.ensureInitialized();
    try {
      final google = GoogleSignIn.instance;
      if (!_googleReady) {
        await google.initialize(
          clientId: DefaultFirebaseOptions.currentPlatform.iosClientId,
        );
        _googleReady = true;
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AccountAuthException('Google did not return a sign-in.');
      }
      final cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return _account(cred.user, fallbackEmail: account.email);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AccountAuthException('Cancelled', cancelled: true);
      }
      throw AccountAuthException(
        'Google sign-in failed. ${e.description ?? 'Please try again.'}',
      );
    } on FirebaseAuthException catch (e) {
      throw AccountAuthException(_firebaseMessage(e));
    }
  }

  /// The authorization code from the latest Sign in with Apple, kept so an
  /// account deletion right after it can revoke the Apple token.
  static String? lastAppleAuthorizationCode;

  /// Revokes the owner's Sign in with Apple token (required by Apple when an
  /// account is deleted). Needs the code from a sign-in just made.
  Future<void> revokeAppleToken(String authorizationCode) =>
      _auth.revokeTokenWithAuthorizationCode(authorizationCode);

  Future<SignedInAccount> signInWithApple() async {
    await PhoneAuthService.ensureInitialized();
    try {
      final provider = AppleAuthProvider()..addScope('email');
      final cred = await _auth.signInWithProvider(provider);
      lastAppleAuthorizationCode = cred.additionalUserInfo?.authorizationCode;
      return _account(cred.user);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'web-context-canceled') {
        throw const AccountAuthException('Cancelled', cancelled: true);
      }
      throw AccountAuthException(_firebaseMessage(e));
    }
  }

  /// Emails a 6-digit code to [email]. Throws when the server refuses to send
  /// (too many requests for this address, or sending is unavailable).
  Future<void> requestEmailCode(String email) async {
    await PhoneAuthService.ensureInitialized();
    try {
      await _functions.httpsCallable('requestEmailCode').call<Object?>({
        'email': normalizeEmail(email),
      });
    } on FirebaseFunctionsException catch (e) {
      throw AccountAuthException(_functionsMessage(e));
    }
  }

  /// Checks the emailed [code] and signs in as the account that owns [email].
  Future<SignedInAccount> confirmEmailCode(String email, String code) async {
    await PhoneAuthService.ensureInitialized();
    final address = normalizeEmail(email);
    try {
      final res = await _functions
          .httpsCallable('verifyEmailCode')
          .call<Map<Object?, Object?>>({'email': address, 'code': code});
      final token = res.data['token'] as String?;
      if (token == null) {
        throw const AccountAuthException('Sign-in failed. Please try again.');
      }
      final cred = await _auth.signInWithCustomToken(token);
      return _account(cred.user, fallbackEmail: address);
    } on FirebaseFunctionsException catch (e) {
      throw AccountAuthException(_functionsMessage(e));
    } on FirebaseAuthException catch (e) {
      throw AccountAuthException(_firebaseMessage(e));
    }
  }

  SignedInAccount _account(User? user, {String? fallbackEmail}) {
    final email = user?.email ?? fallbackEmail;
    if (user == null || email == null || email.isEmpty) {
      throw const AccountAuthException(
        'This sign-in did not share an email address, which Rent Bee needs '
        'to find your ledger.',
      );
    }
    return (uid: user.uid, identity: normalizeEmail(email));
  }

  static String _firebaseMessage(FirebaseAuthException e) => switch (e.code) {
    'network-request-failed' => 'Network error. Check your connection.',
    'account-exists-with-different-credential' =>
      'This email already signs in another way. Use the emailed code '
          'instead.',
    'user-disabled' => 'This account has been disabled.',
    _ => 'Sign-in failed (${e.code}). Please try again.',
  };

  // The functions answer with a message written for the owner (wrong code,
  // expired, too many tries); anything else is a generic failure.
  static String _functionsMessage(FirebaseFunctionsException e) =>
      switch (e.code) {
        'invalid-argument' ||
        'failed-precondition' ||
        'resource-exhausted' ||
        'permission-denied' ||
        'deadline-exceeded' when (e.message ?? '').isNotEmpty => e.message!,
        'unavailable' => 'Network error. Check your connection.',
        'not-found' =>
          'Email sign-in is not available yet. Please try again later.',
        _ => 'Something went wrong. Please try again.',
      };
}
