import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of attempting to reserve one OTP send against the global daily cap.
class OtpQuota {
  /// Whether this send is permitted.
  final bool allowed;

  /// Sends still available in the current 24h window (0 when blocked).
  final int remaining;

  /// When the current window resets and sends become available again.
  /// Null only on the very first send of a fresh window.
  final DateTime? resetAt;

  const OtpQuota({
    required this.allowed,
    required this.remaining,
    this.resetAt,
  });
}

/// Enforces a **global** cap on phone/OTP verifications — [dailyLimit] total
/// across every user and device per rolling [window], to stay within Firebase's
/// free phone-auth allowance.
///
/// The counter is a single shared Firestore doc (`meta/otpQuota`) guarded by a
/// transaction so concurrent sign-ins can't overshoot the cap. Because a slot is
/// reserved *before* the SMS is requested, once the 10th slot is taken nobody —
/// the same person or ten different people — can trigger another OTP until the
/// window elapses. Security rules mirror this math so a modified client can't
/// bypass it (see firestore.rules → match /meta/otpQuota).
///
/// This runs during onboarding while the user is still **unauthenticated**, so
/// the doc is deliberately world-readable and increment-only under the rules.
class OtpQuotaService {
  final FirebaseFirestore _fs;
  OtpQuotaService([FirebaseFirestore? fs])
    : _fs = fs ?? FirebaseFirestore.instance;

  /// Maximum OTP sends allowed per [window], across all users/devices.
  static const int dailyLimit = 10;

  /// Rolling window that begins with the first send after a reset.
  static const Duration window = Duration(hours: 24);

  /// Numbers exempt from the cap — the store-review test numbers registered in
  /// Firebase Auth ("Phone numbers for testing"). Keep this in sync with the
  /// console so reviewers are never blocked and never consume a real slot.
  static const Set<String> exemptNumbers = {
    '+9779800000000', // Play/App Store review test number (fixed OTP in console)
  };

  DocumentReference<Map<String, dynamic>> get _doc =>
      _fs.collection('meta').doc('otpQuota');

  /// Atomically reserves one send for [phoneE164]. Returns an [OtpQuota] whose
  /// [OtpQuota.allowed] is false when the global cap is exhausted — callers must
  /// not request an OTP in that case.
  Future<OtpQuota> tryReserve(String phoneE164) async {
    // Review/test numbers skip the cap entirely (no real SMS is sent for them).
    if (exemptNumbers.contains(phoneE164)) {
      return const OtpQuota(allowed: true, remaining: dailyLimit);
    }

    return _fs.runTransaction<OtpQuota>((tx) async {
      final snap = await tx.get(_doc);
      final data = snap.data();
      final windowStart = (data?['windowStart'] as Timestamp?)?.toDate();
      final count = (data?['count'] as num?)?.toInt() ?? 0;
      final now = DateTime.now();

      final expired =
          windowStart == null || now.isAfter(windowStart.add(window));

      if (expired) {
        // Open a fresh window; this reservation is its first send.
        tx.set(_doc, {'count': 1, 'windowStart': FieldValue.serverTimestamp()});
        return const OtpQuota(allowed: true, remaining: dailyLimit - 1);
      }

      final resetAt = windowStart.add(window);

      if (count >= dailyLimit) {
        return OtpQuota(allowed: false, remaining: 0, resetAt: resetAt);
      }

      tx.update(_doc, {'count': count + 1});
      return OtpQuota(
        allowed: true,
        remaining: dailyLimit - (count + 1),
        resetAt: resetAt,
      );
    });
  }
}
