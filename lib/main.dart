import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'data/database.dart';
import 'data/ledger_repository.dart';
import 'domain/bs_calendar.dart';
import 'firebase_options.dart';
import 'state/auth_provider.dart';
import 'state/ledger_provider.dart';
import 'state/settings_provider.dart';

/// Default starting BS month (matches the spec's example header, Jestha 2082).
const _initialMonth = BsMonth(2082, 2);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final prefs = await SharedPreferences.getInstance();
    final auth = await AuthProvider.load(prefs);
    final settings = SettingsProvider(prefs);
    final db = await openAppDatabase();
    final repo = LedgerRepository(db);

    runApp(UnitLedgerApp(auth: auth, settings: settings, repo: repo));
  } catch (e, st) {
    // A failure during async startup (secure storage, DB key, SQLCipher) would
    // otherwise leave the engine up with no UI — a blank black screen. Surface
    // it instead so it is diagnosable on-device.
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

  const UnitLedgerApp({
    super.key,
    required this.auth,
    required this.settings,
    required this.repo,
  });

  @override
  State<UnitLedgerApp> createState() => _UnitLedgerAppState();
}

class _UnitLedgerAppState extends State<UnitLedgerApp> {
  late final AuthProvider _auth = widget.auth;
  late final SettingsProvider _settings = widget.settings;
  late final LedgerProvider _ledger =
      LedgerProvider(widget.repo, initialMonth: _initialMonth)
        ..init(annualRaisePercent: widget.settings.annualRaisePercent);
  late final _router = buildRouter(_auth);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _ledger),
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
