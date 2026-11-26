import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks for a store rating at a moment the owner has just got value from the
/// app: after recording a payment, once they have recorded enough of them.
///
/// The OS shows its own rating sheet and enforces its own cap (iOS: three
/// times a year, and never when the user has turned ratings prompts off), so
/// this only decides *when to ask* — it never knows whether a sheet appeared.
class ReviewPrompter {
  static const _kCount = 'review_payments_recorded';
  static const _kAskedAtCount = 'review_asked_at_count';
  static const _kAskedAtMs = 'review_asked_at_ms';

  /// First ask after this many recorded payments.
  static const firstAskAfter = 5;

  /// Later asks need this many further payments *and* [minGap] since the last.
  static const repeatEvery = 30;
  static const minGap = Duration(days: 120);

  final SharedPreferences _prefs;
  final Future<void> Function() _request;
  final DateTime Function() _now;

  ReviewPrompter(
    this._prefs, {
    Future<void> Function()? request,
    DateTime Function()? now,
  })  : _request = request ?? _storeRequest,
        _now = now ?? DateTime.now;

  static Future<void> _storeRequest() async {
    final review = InAppReview.instance;
    if (await review.isAvailable()) await review.requestReview();
  }

  /// Counts one recorded payment and asks for a rating when it is due.
  /// Never throws: a failed ask must not disturb recording rent.
  Future<void> paymentRecorded() async {
    try {
      final count = (_prefs.getInt(_kCount) ?? 0) + 1;
      await _prefs.setInt(_kCount, count);
      if (!_due(count)) return;
      await _prefs.setInt(_kAskedAtCount, count);
      await _prefs.setInt(_kAskedAtMs, _now().millisecondsSinceEpoch);
      await _request();
    } catch (_) {}
  }

  bool _due(int count) {
    final askedAt = _prefs.getInt(_kAskedAtCount);
    if (askedAt == null) return count >= firstAskAfter;
    if (count - askedAt < repeatEvery) return false;
    final last =
        DateTime.fromMillisecondsSinceEpoch(_prefs.getInt(_kAskedAtMs) ?? 0);
    return _now().difference(last) >= minGap;
  }
}
