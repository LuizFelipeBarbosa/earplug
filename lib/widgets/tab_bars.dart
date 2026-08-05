import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : Ep.inkA(.4);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: epText(
                  size: 9,
                  weight: FontWeight.w800,
                  letterSpacing: .8,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBarShell extends StatelessWidget {
  final List<Widget> items;
  final Color borderColor;

  const _TabBarShell({required this.items, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    final bottomPad = math.max(MediaQuery.paddingOf(context).bottom, 22.0);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.fromLTRB(10, 8, 10, bottomPad),
          decoration: BoxDecoration(
            color: Ep.bg.withValues(alpha: .92),
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: Row(children: items),
        ),
      ),
    );
  }
}

class FanTabBar extends StatelessWidget {
  const FanTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scr = app.current.screen;
    return _TabBarShell(
      borderColor: Ep.whiteA(.1),
      items: [
        _TabItem(
          icon: Icons.home_outlined,
          label: 'GIGS',
          active: scr == Screen.home,
          onTap: () => app.resetTo(Screen.home),
        ),
        _TabItem(
          icon: Icons.search,
          label: 'EXPLORE',
          active: scr == Screen.explore,
          onTap: () => app.resetTo(Screen.explore),
        ),
        _TabItem(
          icon: Icons.confirmation_number_outlined,
          label: 'MY GIGS',
          active: scr == Screen.myGigs,
          onTap: app.openMyGigsTab,
        ),
      ],
    );
  }
}

class BandTabBar extends StatelessWidget {
  const BandTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scr = app.current.screen;
    return _TabBarShell(
      borderColor: Ep.blue.withValues(alpha: .5),
      items: [
        _TabItem(
          icon: Icons.grid_view_rounded,
          label: 'DASH',
          active: scr == Screen.bandDash,
          onTap: () => app.resetTo(Screen.bandDash),
        ),
        _TabItem(
          icon: Icons.radio_button_checked,
          label: 'PROFILE',
          active: scr == Screen.bandEdit,
          onTap: () => app.resetTo(Screen.bandEdit),
        ),
        _TabItem(
          icon: Icons.table_rows_outlined,
          label: 'GIGS',
          active: scr == Screen.gigMgr,
          onTap: () => app.resetTo(Screen.gigMgr),
        ),
        _TabItem(
          icon: Icons.insert_chart_outlined_rounded,
          label: 'INSIGHTS',
          active: scr == Screen.analytics,
          onTap: () => app.resetTo(Screen.analytics),
        ),
      ],
    );
  }
}
