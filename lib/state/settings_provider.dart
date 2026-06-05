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
  }

  Future<void> setAnnualRaisePercent(double percent) async {
    final p = percent.clamp(0, _maxRaisePercent).toDouble();
    if (p == _annualRaisePercent) return;
    _annualRaisePercent = p;
    await _prefs.setDouble(_kRaisePercent, p);
    notifyListeners();
  }
}
