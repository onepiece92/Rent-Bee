import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/test_accounts.dart';

/// Single-owner local lock with a one-time phone identity.
///
/// Onboarding is two staged steps: a phone number is verified once via Firebase
/// OTP ([recordPhoneVerification]), then a PIN is set ([setPin]). After that the
/// app is offline-first — every later launch unlocks with the local PIN alone
/// and never touches Firebase.
///
/// The PIN is stretched with PBKDF2-HMAC-SHA256; the salt + derived hash + work
/// factor are kept in shared_preferences as one record. No platform keychain
/// is used — avoiding it keeps local/dev builds prompt-free on every platform.
/// Derivation runs off the UI thread via [compute].
///
/// Guessing at the lock screen is rate-limited: after [freeAttempts] wrong
/// PINs each further miss locks the screen for a growing time (see
/// [lockoutFor]), persisted across restarts. A forgotten PIN is reset by
/// re-verifying the *same* phone number ([startPinReset]).
///
/// Scope: this gates the *UI*, not the data. The ledger DB is a local,
/// unencrypted SQLite file.
class AuthProvider extends ChangeNotifier {
  /// The PIN material as one value — `{"i": iterations, "s": salt, "h": hash}`
  /// — so it is replaced in a single write. (It used to be three keys written
  /// one after another; an interruption between them left a salt and a hash
  /// that no PIN could ever match.)
  static const _kRecord = 'pin_record';
  // The three legacy keys: still read, removed once the record is written.
  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';
  static const _kIterations = 'pin_iterations';
  static const _kPhone = 'phone_number';
  static const _kUid = 'phone_uid';
  // "<wrong attempts>:<locked until, ms since epoch>", one write.
  static const _kLockout = 'pin_lockout';

  /// PBKDF2 work factor. A 4-digit PIN has 10,000 values, so no work factor
  /// makes a copied hash expensive to search — and the ledger file next to it
  /// is not encrypted anyway. What stops guessing is the attempt limit; the
  /// work factor only needs to keep the stored value from being a plain
  /// lookup. 20k keeps unlock near-instant on slow phones (100k of pure-Dart
  /// HMAC took a noticeable pause on every unlock). Stored per-credential: a
  /// record made with another count is re-hashed after its next unlock.
  static const _iterations = 20000;

  /// Wrong PINs allowed before the lock screen starts timing out.
  static const freeAttempts = 5;

  /// How long the lock screen refuses input after [failures] wrong PINs in a
  /// row: nothing for the first [freeAttempts] - 1, then 30 s, 1 min, 5 min,
  /// 15 min and 1 hour for each miss after that.
  static Duration lockoutFor(int failures) {
    const steps = [
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(hours: 1),
    ];
    if (failures < freeAttempts) return Duration.zero;
    return steps[min(failures - freeAttempts, steps.length - 1)];
  }

  /// Sentinel meaning "legacy single-round SHA-256" — a hash from an older
  /// build that wrote `sha256('$salt:$pin')` with no stored iteration count.
  static const _legacyMarker = 0;

  final SharedPreferences _prefs;

  /// PBKDF2 derivation, injectable so tests can substitute a fast or failing
  /// implementation without spawning a real isolate. Defaults to [_computeDerive].
  final Future<String> Function(String pin, String salt, int iterations) _derive;

  // Cached at load() so hasPin/phoneVerified stay synchronous for routing/build.
  String? _hash;
  String? _salt;
  int _storedIterations = _iterations;
  String? _phone;
  String? _uid;
  bool _unlocked = false;
  bool _guest = false;
  bool _resettingPin = false;
  int _failures = 0;
  DateTime? _lockedUntil;

  /// The clock, replaceable in tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  AuthProvider._(this._prefs, this._derive);

  /// Builds an instance with state set directly, for widget/unit tests. [derive]
  /// lets a test force success, a wrong hash, or a thrown error.
  @visibleForTesting
  factory AuthProvider.forTest(
    SharedPreferences prefs,
    Future<String> Function(String, String, int) derive, {
    String? hash,
    String? salt,
    int iterations = _iterations,
    String? phone,
  }) {
    final auth = AuthProvider._(prefs, derive);
    auth._hash = hash;
    auth._salt = salt;
    auth._storedIterations = iterations;
    auth._phone = phone;
    return auth;
  }

  bool get unlocked => _unlocked;
  bool get hasPin => _hash != null;

  /// True when this device has completed PIN setup at least once before.
  /// PIN setup is mandatory onboarding (every user, guest or
  /// phone-verified, calls [setPin]), so its absence reliably means a
  /// genuinely fresh install — used to decide new-install-only defaults
  /// (see SettingsProvider's calendar-mode default) without disturbing
  /// existing users who never touched the setting in question. Checked
  /// directly against prefs (not the loaded instance) so it reflects state
  /// from *before* this app process ever ran, at the one point ([main])
  /// where that distinction still matters.
  static bool hasExistingInstall(SharedPreferences prefs) =>
      prefs.containsKey(_kRecord) || prefs.containsKey(_kHash);

  /// Wrong PINs entered in a row since the last successful unlock.
  int get failedAttempts => _failures;

  /// How long the lock screen still refuses input; zero when it accepts a
  /// PIN. Never more than the full timeout for the current miss count, so a
  /// device clock set backwards cannot stretch a lockout.
  Duration get lockoutRemaining {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(now());
    if (left <= Duration.zero) return Duration.zero;
    final full = lockoutFor(_failures);
    return left > full ? full : left;
  }

  /// True while a forgotten PIN is being reset: the lock screen is replaced
  /// by phone verification for the number already on this device.
  bool get resettingPin => _resettingPin;

  /// Whether a forgotten PIN can be reset — only for a phone-verified owner
  /// (the debug guest session has no number to verify).
  bool get canResetPin => _phone != null && !_guest && hasPin;

  /// True during a transient guest test session (see [enterGuestMode]).
  bool get isGuest => _guest;

  /// True when signed in as a store-review test login (see
  /// [reviewTestNumbers]).
  bool get isTestAccount => isReviewTestNumber(_phone);

  /// Whether this session may replace the ledger with demo data. Only the
  /// review test login and the debug guest session can: generating demo data
  /// wipes the ledger and, with sync on, the cloud copy on every signed-in
  /// device, so a real owner's account never offers it.
  bool get canGenerateDemoData => _guest || isTestAccount;

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
  static Future<AuthProvider> load(
    SharedPreferences prefs, {
    Future<String> Function(String, String, int)? derive,
  }) async {
    final auth = AuthProvider._(prefs, derive ?? _computeDerive);
    if (!auth._loadRecord()) {
      auth._hash = prefs.getString(_kHash);
      auth._salt = prefs.getString(_kSalt);
      final iters = prefs.getInt(_kIterations);
      auth._storedIterations = (auth._hash != null && iters == null)
          ? _legacyMarker
          : (iters ?? _iterations);
    }
    auth._phone = prefs.getString(_kPhone);
    auth._uid = prefs.getString(_kUid);
    auth._loadLockout();
    return auth;
  }

  /// Reads the single-value PIN record; false when there is none (or it is
  /// unreadable), so the caller falls back to the legacy keys.
  bool _loadRecord() {
    final raw = _prefs.getString(_kRecord);
    if (raw == null) return false;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final hash = m['h'] as String, salt = m['s'] as String;
      final iterations = m['i'] as int;
      _hash = hash;
      _salt = salt;
      _storedIterations = iterations;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Replaces the PIN material in one write, then drops the legacy keys.
  Future<void> _storeRecord(String salt, String hash, int iterations) async {
    await _prefs.setString(
        _kRecord, jsonEncode({'i': iterations, 's': salt, 'h': hash}));
    _salt = salt;
    _hash = hash;
    _storedIterations = iterations;
    for (final k in const [_kSalt, _kHash, _kIterations]) {
      if (_prefs.containsKey(k)) await _prefs.remove(k);
    }
  }

  void _loadLockout() {
    final parts = (_prefs.getString(_kLockout) ?? '').split(':');
    if (parts.length != 2) return;
    _failures = int.tryParse(parts[0]) ?? 0;
    final until = int.tryParse(parts[1]) ?? 0;
    _lockedUntil =
        until > 0 ? DateTime.fromMillisecondsSinceEpoch(until) : null;
  }

  Future<void> _recordFailure() async {
    _failures++;
    final wait = lockoutFor(_failures);
    _lockedUntil = wait > Duration.zero ? now().add(wait) : null;
    await _prefs.setString(_kLockout,
        '$_failures:${_lockedUntil?.millisecondsSinceEpoch ?? 0}');
  }

  Future<void> _clearFailures() async {
    if (_failures == 0 && _lockedUntil == null) return;
    _failures = 0;
    _lockedUntil = null;
    await _prefs.remove(_kLockout);
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
    await _removePin();
    _phone = null;
    _uid = null;
    _unlocked = false;
    _guest = false;
    _resettingPin = false;
    notifyListeners();
  }

  Future<void> _removePin() async {
    for (final k in const [_kRecord, _kHash, _kSalt, _kIterations, _kLockout]) {
      await _prefs.remove(k);
    }
    _hash = null;
    _salt = null;
    _storedIterations = _iterations;
    _failures = 0;
    _lockedUntil = null;
  }

  /// First-run (or change-PIN): derive and store fresh PBKDF2 material.
  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    final hash = await _derive(pin, salt, _iterations);
    await _storeRecord(salt, hash, _iterations);
    await _clearFailures();
    _unlocked = true;
    notifyListeners();
  }

  /// Returns true if the PIN matches and unlocks the app. A correct legacy PIN
  /// is transparently upgraded to PBKDF2.
  ///
  /// Returns false without checking anything while [lockoutRemaining] is
  /// running; a wrong PIN counts toward the next lockout.
  Future<bool> unlock(String pin) async {
    final salt = _salt;
    final hash = _hash;
    if (salt == null || hash == null) return false;
    if (lockoutRemaining > Duration.zero) return false;

    if (_storedIterations == _legacyMarker) {
      if (_legacyHash(pin, salt) != hash) {
        await _recordFailure();
        return false;
      }
      await setPin(pin); // upgrade in place (setPin unlocks + notifies).
      return true;
    }

    if (await _derive(pin, salt, _storedIterations) != hash) {
      await _recordFailure();
      return false;
    }
    await _clearFailures();
    _unlocked = true;
    notifyListeners();
    // A record in the old three-key layout, or made with another work
    // factor, is rewritten now that the PIN is known — after unlocking, so
    // the owner never waits for it.
    if (_storedIterations != _iterations || !_prefs.containsKey(_kRecord)) {
      unawaited(_rehash(pin));
    }
    return true;
  }

  Future<void> _rehash(String pin) async {
    final from = _hash;
    try {
      final salt = _newSalt();
      final hash = await _derive(pin, salt, _iterations);
      // The PIN may have been changed or removed while this was deriving.
      if (_hash != from) return;
      await _storeRecord(salt, hash, _iterations);
    } catch (e) {
      debugPrint('Auth: PIN re-hash skipped: $e'); // the old record still works
    }
  }

  /// Forgot PIN, step 1: leave the lock screen for phone verification of the
  /// number already recorded on this device. Nothing is changed yet —
  /// [cancelPinReset] returns to the lock screen with the PIN intact.
  void startPinReset() {
    if (!canResetPin || _resettingPin) return;
    _resettingPin = true;
    notifyListeners();
  }

  void cancelPinReset() {
    if (!_resettingPin) return;
    _resettingPin = false;
    notifyListeners();
  }

  /// Forgot PIN, step 2: [verifiedPhone] has just passed OTP verification.
  /// Only the number this device was set up with may clear the PIN — anyone
  /// else holding the phone cannot swap in their own number to get past the
  /// lock. On success the PIN is removed and the owner sets a new one; the
  /// ledger is untouched. Returns false (and changes nothing) otherwise.
  Future<bool> completePinReset(String verifiedPhone, String uid) async {
    if (!_resettingPin || _phone == null || verifiedPhone != _phone) {
      return false;
    }
    await _removePin();
    await _prefs.setString(_kUid, uid);
    _uid = uid;
    _resettingPin = false;
    notifyListeners();
    return true;
  }

  void lock() {
    _unlocked = false;
    _resettingPin = false;
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

  /// Stretch the PIN off the UI thread; returns the base64 derived key. This is
  /// the default [_derive] implementation injected at [load].
  static Future<String> _computeDerive(String pin, String salt, int iterations) {
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
