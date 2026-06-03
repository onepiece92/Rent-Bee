import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../sheets/edit_unit_sheet.dart';
import 'glass.dart';

/// App shell: shared brand background + the four-tab branches, with a glass
/// footer nav and a docked center "Add Unit" button hovering above it.
class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  void _go(int index) => navigationShell.goBranch(
        index,
        // tapping the active tab pops it to its initial route
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandBackground(
        child: Stack(
          children: [
            Positioned.fill(child: navigationShell),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _GlassNavBar(
                currentIndex: navigationShell.currentIndex,
                onSelect: _go,
                onAdd: () => EditUnitSheet.show(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavDest {
  final IconData icon;
  final String label;
  final int branch;
  const _NavDest(this.icon, this.label, this.branch);
}

class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  const _GlassNavBar({
    required this.currentIndex,
    required this.onSelect,
    required this.onAdd,
  });

  static const _left = [
    _NavDest(Icons.receipt_long_rounded, 'Ledger', 0),
    _NavDest(Icons.insights_rounded, 'Reports', 1),
  ];
  static const _right = [
    _NavDest(Icons.grid_view_rounded, 'Units', 2),
    _NavDest(Icons.settings_rounded, 'Settings', 3),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? bottomInset : 14),
      // 64px bar + 16px headroom so the docked button floats above the bar
      // while staying inside the Stack's bounds — outside-bounds regions are
      // not hit-testable, which previously ate taps on the button's top edge.
      child: SizedBox(
        height: 80,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // the glass bar, pinned to the bottom of the 80px area
            Align(
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Brand.navGlassBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Brand.glassBorder),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66060618),
                          blurRadius: 28,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        for (final d in _left)
                          _NavItem(
                            dest: d,
                            selected: currentIndex == d.branch,
                            onTap: () => onSelect(d.branch),
                          ),
                        const SizedBox(width: 64), // gap for the center button
                        for (final d in _right)
                          _NavItem(
                            dest: d,
                            selected: currentIndex == d.branch,
                            onTap: () => onSelect(d.branch),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // docked center "Add Unit" button, hovering above the bar but
            // fully within the Stack so the whole target is tappable
            Align(
              alignment: Alignment.topCenter,
              child: _CenterAddButton(onTap: onAdd),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _NavDest dest;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(
      {required this.dest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? Brand.orange : Brand.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(dest.icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(dest.label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

class _CenterAddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CenterAddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: Brand.orangeGradient,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: Brand.orange.withValues(alpha: 0.5),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.add, size: 24, color: Colors.white),
          ),
          const SizedBox(height: 2),
          const Text('Add Unit',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Brand.orangeSoft)),
        ],
      ),
    );
  }
}
