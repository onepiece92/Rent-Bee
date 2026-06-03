import 'package:go_router/go_router.dart';

import '../state/auth_provider.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/reports_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/units_screen.dart';
import '../ui/widgets/scaffold_with_navbar.dart';

/// go_router config. A [StatefulShellRoute] hosts the four footer tabs
/// (Ledger / Reports / Units / Settings) inside a shared shell with the glass
/// nav bar; the center "Add Unit" action lives in the shell, not a route.
/// An auth redirect gates everything behind the PIN unlock.
GoRouter buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';
      if (!auth.unlocked) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
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
