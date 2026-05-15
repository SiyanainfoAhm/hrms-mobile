import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens.dart';

/// Main app shell: Material 3 bottom navigation + preserved tab state.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = <({String label, IconData icon, IconData selected})>[
    (label: 'Home', icon: Icons.home_outlined, selected: Icons.home_rounded),
    (label: 'Attendance', icon: Icons.event_available_outlined, selected: Icons.event_available_rounded),
    (label: 'Leave', icon: Icons.beach_access_outlined, selected: Icons.beach_access_rounded),
    (label: 'Payslips', icon: Icons.payments_outlined, selected: Icons.payments_rounded),
    (label: 'Profile', icon: Icons.person_outline_rounded, selected: Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(
          key: ValueKey<int>(navigationShell.currentIndex),
          child: navigationShell,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) {
          navigationShell.goBranch(
            i,
            initialLocation: i == navigationShell.currentIndex,
          );
        },
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: Icon(_tabs[i].icon),
              selectedIcon: Icon(_tabs[i].selected, color: HrmsTokens.primary),
              label: _tabs[i].label,
            ),
        ],
      ),
    );
  }
}
