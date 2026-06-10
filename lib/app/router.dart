import 'package:go_router/go_router.dart';

import '../state/auth_provider.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/phone_login_screen.dart';
import '../ui/screens/reports_screen.dart';
import '../ui/screens/set_pin_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/units_screen.dart';
import '../ui/widgets/scaffold_with_navbar.dart';

/// go_router config. A [StatefulShellRoute] hosts the four footer tabs
/// (Ledger / Reports / Units / Settings) inside a shared shell with the glass
/// nav bar; the center "Add Unit" action lives in the shell, not a route.
///
/// The redirect enforces a staged onboarding gate: phone OTP verification once,
/// then a PIN is set, then every later launch unlocks offline with that PIN.
GoRouter buildRouter(AuthProvider auth) {
  const onboardPhone = '/onboarding/phone';
  const onboardPin = '/onboarding/pin';
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final atGate = loc == '/login' || loc == onboardPhone || loc == onboardPin;
      if (auth.unlocked) return atGate ? '/' : null;
      // Not unlocked — route to the earliest incomplete onboarding step.
      if (!auth.phoneVerified) return loc == onboardPhone ? null : onboardPhone;
      if (!auth.hasPin) return loc == onboardPin ? null : onboardPin;
      return loc == '/login' ? null : '/login';
    },
    routes: [
      GoRoute(
        path: onboardPhone,
        name: 'onboardPhone',
        builder: (context, state) => const PhoneLoginScreen(),
      ),
      GoRoute(
        path: onboardPin,
        name: 'onboardPin',
        builder: (context, state) => const SetPinScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/reports',
              name: 'reports',
              builder: (context, state) => const ReportsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/units',
              name: 'units',
              builder: (context, state) => const UnitsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
}
