import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single-owner local lock with a one-time phone identity.
///
/// Onboarding is two staged steps: a phone number is verified once via Firebase
/// OTP ([recordPhoneVerification]), then a PIN is set ([setPin]). After that the
/// app is offline-first — every later launch unlocks with the local PIN alone
/// and never touches Firebase.
///
/// The PIN is stretched with PBKDF2-HMAC-SHA256; the salt + derived hash + work
/// factor are kept in shared_preferences. No platform keychain is used — the
/// stored hash is not a secret (PBKDF2 makes brute-forcing a leaked hash
/// expensive), and avoiding the keychain keeps local/dev builds prompt-free on
/// every platform. Derivation runs off the UI thread via [compute].
///
/// Scope: this gates the *UI*, not the data. The ledger DB is a local,
/// unencrypted SQLite file.
class AuthProvider extends ChangeNotifier {
  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';
  static const _kIterations = 'pin_iterations';
  static const _kPhone = 'phone_number';
  static const _kUid = 'phone_uid';

  /// PBKDF2 work factor. Pure-Dart HMAC caps how high this can go before unlock
  /// feels sluggish; 100k keeps a single derive well under ~300ms on a phone
  /// while making offline brute-force of a 4–6 digit PIN materially expensive.
  /// Stored per-credential so it can be raised later with a transparent rehash.
  static const _iterations = 100000;

  /// Sentinel meaning "legacy single-round SHA-256" — a hash from an older
  /// build that wrote `sha256('$salt:$pin')` with no stored iteration count.
  static const _legacyMarker = 0;

  final SharedPreferences _prefs;

  // Cached at load() so hasPin/phoneVerified stay synchronous for routing/build.
  String? _hash;
  String? _salt;
  int _storedIterations = _iterations;
  String? _phone;
  String? _uid;
  bool _unlocked = false;
  bool _guest = false;

  AuthProvider._(this._prefs);

  bool get unlocked => _unlocked;
  bool get hasPin => _hash != null;

  /// True during a transient guest test session (see [enterGuestMode]).
  bool get isGuest => _guest;

  /// True once the owner's phone number has been verified via Firebase OTP.
  bool get phoneVerified => _phone != null;

  /// The verified phone number in E.164 form (e.g. `+9779801234501`), or null.
  String? get phone => _phone;

  /// The Firebase uid captured at verification, or null. Retained for a future
  /// cloud-sync/backup feature; day-to-day unlock does not use it.
  String? get uid => _uid;

  /// Loads PIN material from shared_preferences. A pre-PBKDF2 hash (present but
  /// with no stored iteration count) is treated as legacy single-round SHA-256
  /// and transparently re-hashed on the next successful [unlock].
  static Future<AuthProvider> load(SharedPreferences prefs) async {
    final auth = AuthProvider._(prefs);
    auth._hash = prefs.getString(_kHash);
    auth._salt = prefs.getString(_kSalt);
    final iters = prefs.getInt(_kIterations);
    auth._storedIterations =
        (auth._hash != null && iters == null) ? _legacyMarker : (iters ?? _iterations);
    auth._phone = prefs.getString(_kPhone);
    auth._uid = prefs.getString(_kUid);
    return auth;
  }

  /// Onboarding step 1: persist the phone identity captured from a successful
  /// Firebase OTP verification. Deliberately does **not** unlock — the owner
  /// still sets a PIN ([setPin]) before reaching the app.
  Future<void> recordPhoneVerification(String phoneE164, String uid) async {
    await _prefs.setString(_kPhone, phoneE164);
    await _prefs.setString(_kUid, uid);
    _phone = phoneE164;
    _uid = uid;
    notifyListeners();
  }

  /// Full sign-out / re-onboard: clears the phone identity and the PIN, then
  /// locks. The next launch starts again at phone verification.
  Future<void> resetIdentity() async {
    await _prefs.remove(_kPhone);
    await _prefs.remove(_kUid);
    await _prefs.remove(_kHash);
    await _prefs.remove(_kSalt);
    await _prefs.remove(_kIterations);
    _phone = null;
    _uid = null;
    _hash = null;
    _salt = null;
    _storedIterations = _iterations;
    _unlocked = false;
    _guest = false;
    notifyListeners();
  }

  /// First-run (or change-PIN): derive and store fresh PBKDF2 material.
  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    final hash = await _derive(pin, salt, _iterations);
    await _prefs.setString(_kSalt, salt);
    await _prefs.setString(_kHash, hash);
    await _prefs.setInt(_kIterations, _iterations);
    _salt = salt;
    _hash = hash;
    _storedIterations = _iterations;
    _unlocked = true;
    notifyListeners();
  }

  /// Returns true if the PIN matches and unlocks the app. A correct legacy PIN
  /// is transparently upgraded to PBKDF2.
  Future<bool> unlock(String pin) async {
    final salt = _salt;
    final hash = _hash;
    if (salt == null || hash == null) return false;

    if (_storedIterations == _legacyMarker) {
      if (_legacyHash(pin, salt) != hash) return false;
      await setPin(pin); // upgrade in place (setPin unlocks + notifies).
      return true;
    }

    if (await _derive(pin, salt, _storedIterations) != hash) return false;
    _unlocked = true;
    notifyListeners();
    return true;
  }

  void lock() {
    _unlocked = false;
    notifyListeners();
  }

  /// Transient guest session for local testing — bypasses phone OTP and the PIN
  /// and unlocks straight into the app. Intentionally **not persisted**: a cold
  /// start drops back to phone onboarding. Only ever invoked from a debug-gated
  /// button (see [PhoneLoginScreen]).
  void enterGuestMode() {
    _guest = true;
    _phone = 'Guest (test)';
    _unlocked = true;
    notifyListeners();
  }

  static String _legacyHash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _newSalt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// Stretch the PIN off the UI thread; returns the base64 derived key.
  static Future<String> _derive(String pin, String salt, int iterations) {
    return compute(_pbkdf2Worker, <String, Object>{
      'pin': pin,
      'salt': salt,
      'iterations': iterations,
    });
  }
}

/// Isolate entry point for [compute]. Args carry only primitives.
String _pbkdf2Worker(Map<String, Object> args) {
  final pin = args['pin'] as String;
  final salt = base64Url.decode(args['salt'] as String);
  final iterations = args['iterations'] as int;
  return base64.encode(_pbkdf2(utf8.encode(pin), salt, iterations, 32));
}

/// PBKDF2-HMAC-SHA256 (RFC 2898). `dkLen` in bytes.
List<int> _pbkdf2(List<int> password, List<int> salt, int iterations, int dkLen) {
  final prf = Hmac(sha256, password);
  final out = <int>[];
  var block = 1;
  while (out.length < dkLen) {
    final msg = <int>[
      ...salt,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ];
    var u = prf.convert(msg).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = prf.convert(u).bytes;
      for (var k = 0; k < t.length; k++) {
        t[k] ^= u[k];
      }
    }
    out.addAll(t);
    block++;
  }
  return out.sublist(0, dkLen);
}
