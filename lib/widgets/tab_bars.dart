import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'sheets.dart';

class EpNavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const EpNavigationItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Ep.contentSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          focusColor: Ep.accent.withValues(alpha: .2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 32,
                    height: 3,
                    decoration: BoxDecoration(
                      color: selected ? Ep.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(icon, size: 19, color: color),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.epCaption.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
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
            color: Ep.background.withValues(alpha: .96),
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [for (final item in items) Expanded(child: item)],
          ),
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
      borderColor: Ep.border,
      items: [
        EpNavigationItem(
          icon: Icons.home_outlined,
          label: 'GIGS',
          selected: scr == Screen.home,
          onPressed: () => app.resetTo(Screen.home),
        ),
        EpNavigationItem(
          icon: Icons.search,
          label: 'EXPLORE',
          selected: scr == Screen.explore,
          onPressed: () => app.resetTo(Screen.explore),
        ),
        EpNavigationItem(
          icon: Icons.confirmation_number_outlined,
          label: 'MY GIGS',
          selected: scr == Screen.myGigs,
          onPressed: app.openMyGigsTab,
        ),
        EpNavigationItem(
          icon: Icons.groups_outlined,
          label: bandEntryLabel(app.myBands.length).toUpperCase(),
          selected: false,
          onPressed: () {
            if (app.myBands.isEmpty) {
              app.requestStartBand();
            } else if (app.myBands.length == 1) {
              app.switchToBand(app.myBands.single);
            } else {
              showSwitcherSheet(context);
            }
          },
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
      borderColor: Ep.border,
      items: [
        EpNavigationItem(
          icon: Icons.grid_view_rounded,
          label: 'DASH',
          selected: scr == Screen.bandDash,
          onPressed: () => app.resetTo(Screen.bandDash),
        ),
        EpNavigationItem(
          icon: Icons.person_outline,
          label: 'PROFILE',
          selected: scr == Screen.bandEdit,
          onPressed: () => app.resetTo(Screen.bandEdit),
        ),
        EpNavigationItem(
          icon: Icons.table_rows_outlined,
          label: 'GIGS',
          selected: scr == Screen.gigMgr,
          onPressed: () => app.resetTo(Screen.gigMgr),
        ),
        EpNavigationItem(
          icon: Icons.insert_chart_outlined_rounded,
          label: 'INSIGHTS',
          selected: scr == Screen.analytics,
          onPressed: () => app.resetTo(Screen.analytics),
        ),
      ],
    );
  }
}
