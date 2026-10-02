import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'data/database.dart';
import 'data/ledger_repository.dart';
import 'data/sync_bootstrap.dart';
import 'domain/bs_calendar.dart';
import 'state/auth_provider.dart';
import 'state/ledger_provider.dart';
import 'state/settings_provider.dart';
import 'state/sync_status.dart';

/// Starting BS month: the month containing today.
BsMonth _initialMonth() {
  final now = bsYearMonth(DateTime.now());
  return BsMonth(now.year, now.month);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Firebase is NOT initialized here — it's loaded lazily only when phone
    // onboarding actually runs (see PhoneAuthService.ensureInitialized), so a
    // returning owner who unlocks with the local PIN keeps a fast cold start.
    final prefs = await SharedPreferences.getInstance();
    final auth = await AuthProvider.load(prefs);
    final settings = SettingsProvider(prefs,
        isExistingInstall: AuthProvider.hasExistingInstall(prefs));
    final db = await openAppDatabase();
    final repo = LedgerRepository(db);

    runApp(UnitLedgerApp(
        auth: auth, settings: settings, repo: repo, prefs: prefs));
  } catch (e, st) {
    // A failure during async startup (prefs or DB open) would otherwise leave
    // the engine up with no UI — a blank black screen. Surface it instead so
    // it is diagnosable on-device.
    runApp(_StartupErrorApp(error: e, stack: st));
  }
}

class _StartupErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stack;
  const _StartupErrorApp({required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Sys.dark.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Startup failed',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text('$error\n\n$stack',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UnitLedgerApp extends StatefulWidget {
  final AuthProvider auth;
  final SettingsProvider settings;
  final LedgerRepository repo;
  final SharedPreferences prefs;

  /// Test-only: a `FontLoader`-registered family for screenshot renders. The
  /// app itself passes nothing and uses the system font.
  final String? fontFamily;

  const UnitLedgerApp({
    super.key,
    required this.auth,
    required this.settings,
    required this.repo,
    required this.prefs,
    this.fontFamily,
  });

  @override
  State<UnitLedgerApp> createState() => _UnitLedgerAppState();
}

class _UnitLedgerAppState extends State<UnitLedgerApp>
    with WidgetsBindingObserver {
  /// Auto-lock the app after it's been in the background at least this long.
  /// The grace window avoids re-prompting for the PIN on quick round-trips
  /// through the file picker / share sheet (CSV import, backup) or the app
  /// switcher; a genuine "put the phone down" still locks.
  static const _autoLockAfter = Duration(seconds: 60);
  DateTime? _backgroundedAt;

  late final AuthProvider _auth = widget.auth;
  late final SettingsProvider _settings = widget.settings;
  late final LedgerProvider _ledger =
      LedgerProvider(widget.repo,
          initialMonth: _initialMonth(),
          raisePercent: () => widget.settings.annualRaisePercent)
        ..init(annualRaisePercent: widget.settings.annualRaisePercent);
  late final _router = buildRouter(_auth);
  final SyncStatusController _syncStatus = SyncStatusController();

  bool _syncStarting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bring cloud sync online once the owner unlocks (and tear it down on
    // sign-out). Driven off the auth state so it never blocks cold start.
    _auth.addListener(_syncLifecycle);
    // Mirror settings changes (calendar + currency + rate) to the cloud
    // whenever a sync session is live. Wired once, here, and resolved at call
    // time: wiring it only after sync had finished starting dropped any
    // change made during that window (buglog B26).
    _lastRate = _settings.annualRaisePercent;
    _settings.addListener(_onSettingsChanged);
    _settings.cloudPush = () => widget.repo.sync?.pushSettings(
          _settings.calendar.name,
          _settings.annualRaisePercent,
          _settings.currency.name,
        );
    _syncLifecycle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_syncLifecycle);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  // Built once: every setting notifies, and two fresh ThemeData per
  // notification made the whole app re-resolve its theme for nothing.
  late final _lightTheme =
      buildTheme(Brightness.light, fontFamily: widget.fontFamily);
  late final _darkTheme =
      buildTheme(Brightness.dark, fontFamily: widget.fontFamily);

  // Read once in initState, before listening. (As a lazy `late` initializer it
  // was first evaluated inside the listener — after the change — so the rate
  // always looked unchanged and the refresh never ran.)
  late double _lastRate;

  /// A past month is priced at the rent in effect then, which depends on the
  /// escalation rate — so a rate change (made here or on another device) must
  /// re-price the month on screen.
  void _onSettingsChanged() {
    final rate = _settings.annualRaisePercent;
    if (rate == _lastRate) return;
    _lastRate = rate;
    _ledger.refresh(keepOrder: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only a PIN-protected, currently-unlocked owner session can auto-lock
    // (guests have no PIN; an already-locked app has nothing to do).
    final canLock = _auth.unlocked && _auth.hasPin && !_auth.isGuest;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (canLock) _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (canLock &&
            since != null &&
            DateTime.now().difference(since) >= _autoLockAfter) {
          _auth.lock(); // go_router redirects to the PIN screen
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _syncLifecycle() async {
    final repo = widget.repo;
    // Start: unlocked, real owner (not guest), not already running/starting.
    if (_auth.unlocked &&
        !_auth.isGuest &&
        repo.sync == null &&
        !_syncStarting) {
      _syncStarting = true;
      try {
        final service = await startSync(
          repo: repo,
          prefs: widget.prefs,
          auth: _auth,
          // A remote change must not reshuffle the list under the finger.
          onApply: () => _ledger.refresh(keepOrder: true),
          status: _syncStatus,
          onRemoteSettings: (mode, rate, currency) => _settings
              .applyRemoteSettings(
                  calendarMode: mode, rate: rate, currency: currency),
          localSettings: () => (
            calendarMode: _settings.calendar.name,
            rate: _settings.annualRaisePercent,
            currency: _settings.currency.name,
          ),
          settingsRevision: () => _settings.localRevision,
        );
        if (service != null && _auth.phoneVerified) {
          // The startup catch-up in LedgerProvider.init ran before sync
          // existed, so its raises were never pushed — and the pull that just
          // finished overwrote them with the cloud's pre-raise rents. Apply
          // them again now that they will be pushed and stick (buglog B02).
          final rate = _settings.annualRaisePercent;
          if (rate > 0) await _ledger.applyDueRaises(rate);
        }
      } catch (e) {
        // A failed start must not wedge `_syncStarting` (that would disable
        // sync for the rest of the session) or escape from a notifier callback.
        debugPrint('Sync: start failed: $e');
        _syncStatus.setError('$e');
      } finally {
        _syncStarting = false;
      }
    }
    // Stop: signed out (identity cleared) while a session was live.
    if (!_auth.phoneVerified && repo.sync != null) {
      await stopSync(repo, status: _syncStatus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _ledger),
        ChangeNotifierProvider.value(value: _syncStatus),
      ],
      // Rebuilds only the MaterialApp when the Appearance setting changes.
      child: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => MaterialApp.router(
          title: 'Rent Bee',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: _settings.appearance,
          routerConfig: _router,
        ),
      ),
    );
  }
}
