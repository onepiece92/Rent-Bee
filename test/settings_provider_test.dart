import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/domain/bs_calendar.dart';
import 'package:unit_ledger/domain/money.dart';
import 'package:unit_ledger/state/settings_provider.dart';

/// Covers the cloud-sync seam on SettingsProvider: local changes push, remote
/// changes apply WITHOUT echoing back, and bad/absent remote fields are ignored.
void main() {
  Future<SettingsProvider> make(
      [Map<String, Object> seed = const {}, bool isExistingInstall = true]) async {
    SharedPreferences.setMockInitialValues(seed);
    return SettingsProvider(await SharedPreferences.getInstance(),
        isExistingInstall: isExistingInstall);
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

  group('currency', () {
    test('defaults to NPR regardless of install status', () async {
      expect((await make()).currency, Currency.npr);
      expect((await make(const {}, false)).currency, Currency.npr);
    });

    test('setCurrency persists, notifies, and pushes to the cloud', () async {
      final s = await make();
      var pushed = 0;
      s.cloudPush = () => pushed++;
      var notified = 0;
      s.addListener(() => notified++);
      await s.setCurrency(Currency.usd);
      expect(s.currency, Currency.usd);
      expect(pushed, 1);
      expect(notified, 1);

      // Persisted — a fresh instance over the same prefs reads it back.
      final prefs = await SharedPreferences.getInstance();
      final reloaded = SettingsProvider(prefs);
      expect(reloaded.currency, Currency.usd);
    });

    test('setCurrency to the same value is a no-op', () async {
      final s = await make();
      var notified = 0;
      s.addListener(() => notified++);
      await s.setCurrency(Currency.npr); // already the default
      expect(notified, 0);
    });

    test('applyRemoteSettings applies a valid currency, ignores an unknown one',
        () async {
      final s = await make();
      s.applyRemoteSettings(currency: 'usd');
      expect(s.currency, Currency.usd);
      s.applyRemoteSettings(currency: 'eur'); // unrecognised — ignored
      expect(s.currency, Currency.usd);
    });
  });

  group('calendar default for new installs (isExistingInstall)', () {
    test(
        'no stored value + existing install → BS (today\'s default, '
        'preserved for anyone who never touched the toggle)', () async {
      final s = await make(const {}, true);
      expect(s.calendar, CalendarMode.bs);
    });

    test('no stored value + fresh install → AD (the new default)', () async {
      final s = await make(const {}, false);
      expect(s.calendar, CalendarMode.ad);
    });

    test('an explicitly stored value always wins, either direction', () async {
      final existingOnAd =
          await make({'calendar_mode': 'ad'}, true);
      expect(existingOnAd.calendar, CalendarMode.ad);

      final freshOnBs = await make({'calendar_mode': 'bs'}, false);
      expect(freshOnBs.calendar, CalendarMode.bs);
    });
  });
}
