import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/bs_calendar.dart';

/// App-wide preferences, persisted so they survive restarts:
///   • the calendar the UI labels dates in (BS vs AD), and
///   • the annual lease escalation rate applied automatically on each
///     unit's anniversary (0 = off).
class SettingsProvider extends ChangeNotifier {
  static const _kCalendar = 'calendar_mode';
  // Stored as a double (`_pct`); a separate key from the old whole-percent int
  // so reading never hits a SharedPreferences type clash.
  static const _kRaisePercent = 'annual_raise_pct';

  /// Default automatic yearly lease escalation, applied on each unit's anniversary.
  static const double _defaultRaisePercent = 5;

  /// Upper bound to guard against runaway typos; effectively "any" rate.
  static const double _maxRaisePercent = 1000;

  final SharedPreferences _prefs;
  CalendarMode _calendar;
  double _annualRaisePercent;

  /// Mirrors a settings change (calendar mode + escalation rate) to the cloud
  /// for the signed-in owner. Set while a sync session is live (see main's
  /// `_syncLifecycle`), null when local-only — so a guest/PIN-only user never
  /// pushes. [applyRemoteSettings] is the matching inbound path (it does NOT
  /// call this, avoiding echo loops).
  void Function()? cloudPush;

  SettingsProvider(this._prefs)
      : _calendar = _prefs.getString(_kCalendar) == CalendarMode.ad.name
            ? CalendarMode.ad
            : CalendarMode.bs,
        _annualRaisePercent =
            _prefs.getDouble(_kRaisePercent) ?? _defaultRaisePercent;

  CalendarMode get calendar => _calendar;
  bool get isAd => _calendar == CalendarMode.ad;

  /// Yearly lease escalation as a percentage (may be fractional, e.g. 7.5). 0 disables
  /// the automatic raise.
  double get annualRaisePercent => _annualRaisePercent;

  Future<void> setCalendar(CalendarMode mode) async {
    if (mode == _calendar) return;
    _calendar = mode;
    await _prefs.setString(_kCalendar, mode.name);
    notifyListeners();
    cloudPush?.call(); // mirror the change to other devices on this login
  }

  /// Applies owner settings arriving from the cloud (same login, another
  /// device, or the sign-in pull). Persists + notifies but never re-pushes, so
  /// it can't echo back. Unknown/absent fields are ignored.
  void applyRemoteSettings({String? calendarMode, num? rate}) {
    var changed = false;
    if (calendarMode == CalendarMode.bs.name ||
        calendarMode == CalendarMode.ad.name) {
      final mode = calendarMode == CalendarMode.ad.name
          ? CalendarMode.ad
          : CalendarMode.bs;
      if (mode != _calendar) {
        _calendar = mode;
        _prefs.setString(_kCalendar, mode.name);
        changed = true;
      }
    }
    if (rate != null) {
      final p = rate.toDouble().clamp(0, _maxRaisePercent).toDouble();
      if (p != _annualRaisePercent) {
        _annualRaisePercent = p;
        _prefs.setDouble(_kRaisePercent, p);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> setAnnualRaisePercent(double percent) async {
    final p = percent.clamp(0, _maxRaisePercent).toDouble();
    if (p == _annualRaisePercent) return;
    _annualRaisePercent = p;
    await _prefs.setDouble(_kRaisePercent, p);
    notifyListeners();
    cloudPush?.call(); // mirror the change to other devices on this login
  }
}
