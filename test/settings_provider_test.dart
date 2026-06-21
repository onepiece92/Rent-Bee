import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/state/settings_provider.dart';

/// Covers the cloud-sync seam on SettingsProvider: local changes push, remote
/// changes apply WITHOUT echoing back, and bad/absent remote fields are ignored.
void main() {
  Future<SettingsProvider> make([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    return SettingsProvider(await SharedPreferences.getInstance());
  }

  test('local changes push to the cloud hook', () async {
    final s = await make();
    var pushed = 0;
    s.cloudPush = () => pushed++;
    await s.setCalendar(CalendarMode.ad);
    await s.setAnnualRaisePercent(9);
    expect(pushed, 2);
    expect(s.isAd, isTrue);
    expect(s.annualRaisePercent, 9);
  });

  test('applyRemoteSettings updates state but never re-pushes (no echo)',
      () async {
    final s = await make();
    var pushed = 0;
    s.cloudPush = () => pushed++;
    s.applyRemoteSettings(calendarMode: 'ad', rate: 8);
    expect(s.isAd, isTrue);
    expect(s.annualRaisePercent, 8);
    expect(pushed, 0, reason: 'inbound apply must not echo back to the cloud');
  });

  test('applyRemoteSettings ignores unknown mode + null rate, clamps the rate',
      () async {
    final s = await make({'calendar_mode': 'bs', 'annual_raise_pct': 5.0});
    s.applyRemoteSettings(calendarMode: 'gregorian', rate: null); // both ignored
    expect(s.isAd, isFalse);
    expect(s.annualRaisePercent, 5);
    s.applyRemoteSettings(rate: 99999); // clamped to the max guard (1000)
    expect(s.annualRaisePercent, 1000);
  });

  test('a no-op remote apply does not notify listeners', () async {
    final s = await make({'calendar_mode': 'bs', 'annual_raise_pct': 5.0});
    var notified = 0;
    s.addListener(() => notified++);
    s.applyRemoteSettings(calendarMode: 'bs', rate: 5); // same as current
    expect(notified, 0);
  });
}
