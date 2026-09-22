import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import 'glass.dart';

/// App shell: the grouped page background, the four tab branches, and a
/// floating Liquid Glass tab bar (HIG, Tab bars): navigation only, never
/// actions; always visible; an icon *and* a one-word label; the current tab's
/// icon filled. A scroll edge effect sits behind it instead of a solid bar,
/// and content scrolls underneath (each screen pads its end to clear it).
class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  /// Height the tab bar occupies above the safe area — screens pad their
  /// scroll views by at least this much at the bottom.
  static const double barHeight = 56 + 2 * 6 + 8;

  void _go(int index) => navigationShell.goBranch(
        index,
        // tapping the active tab pops it to its initial route
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Status-bar glyphs contrast with the page in either appearance.
      value: sys.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: sys.bg,
        body: PageBackground(
          child: Stack(
            children: [
              Positioned.fill(child: navigationShell),
              const Positioned(
                  left: 0, right: 0, bottom: 0, child: ScrollEdge.bottom()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _TabBar(
                    currentIndex: navigationShell.currentIndex, onSelect: _go),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavDest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int branch;
  const _NavDest(this.icon, this.selectedIcon, this.label, this.branch);
}

class _TabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  const _TabBar({required this.currentIndex, required this.onSelect});

  static const _dests = [
    _NavDest(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Ledger', 0),
    _NavDest(Icons.insights_outlined, Icons.insights_rounded, 'Reports', 1),
    _NavDest(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Units', 2),
    _NavDest(Icons.settings_outlined, Icons.settings_rounded, 'Settings', 3),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      // Floating capsule: 16 pt side gutters, 8 pt off the bottom edge (or the
      // home indicator's safe area, whichever is larger).
      padding: EdgeInsets.fromLTRB(
          Sys.gutter, 0, Sys.gutter, bottomInset > 8 ? bottomInset : 8),
      child: Glass(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (final d in _dests)
              _TabItem(
                dest: d,
                selected: currentIndex == d.branch,
                onTap: () => onSelect(d.branch),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final _NavDest dest;
  final bool selected;
  final VoidCallback onTap;
  const _TabItem(
      {required this.dest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final color = selected ? sys.tintText : sys.secondaryLabel;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: SizedBox(
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selected ? dest.selectedIcon : dest.icon,
                      size: 24, color: color),
                  const SizedBox(height: 3),
                  Text(dest.label,
                      style: Type.caption2.semibold.colored(color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
