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

/// Default starting BS month (matches the spec's example header, Jestha 2082).
const _initialMonth = BsMonth(2082, 2);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Firebase is NOT initialized here — it's loaded lazily only when phone
    // onboarding actually runs (see PhoneAuthService.ensureInitialized), so a
    // returning owner who unlocks with the local PIN keeps a fast cold start.
    final prefs = await SharedPreferences.getInstance();
    final auth = await AuthProvider.load(prefs);
    final settings = SettingsProvider(prefs);
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
        backgroundColor: const Color(0xFF0E1830),
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

  const UnitLedgerApp({
    super.key,
    required this.auth,
    required this.settings,
    required this.repo,
    required this.prefs,
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
      LedgerProvider(widget.repo, initialMonth: _initialMonth)
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
    _syncLifecycle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_syncLifecycle);
    super.dispose();
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
      final service = await startSync(
        repo: repo,
        prefs: widget.prefs,
        auth: _auth,
        onApply: () => _ledger.refresh(),
        status: _syncStatus,
        onRemoteSettings: (mode, rate) =>
            _settings.applyRemoteSettings(calendarMode: mode, rate: rate),
        localCalendarMode: _settings.calendar.name,
        localRate: _settings.annualRaisePercent,
      );
      // Mirror future settings changes (calendar + rate) to the cloud.
      if (service != null) {
        _settings.cloudPush = () => service.pushSettings(
              _settings.calendar.name,
              _settings.annualRaisePercent,
            );
      }
      _syncStarting = false;
    }
    // Stop: signed out (identity cleared) while a session was live.
    if (!_auth.phoneVerified && repo.sync != null) {
      await stopSync(repo, status: _syncStatus);
      _settings.cloudPush = null;
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
      child: MaterialApp.router(
        title: 'Rent Bee',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: _router,
      ),
    );
  }
}
