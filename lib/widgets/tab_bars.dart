import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'sheets.dart';

class EpNavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? compactLabel;
  final bool selected;
  final VoidCallback onPressed;

  const EpNavigationItem({
    super.key,
    required this.icon,
    required this.label,
    this.compactLabel,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.epColors.ink : context.epColors.mute;
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
          focusColor: context.epColors.accent.withValues(alpha: .2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 66, minWidth: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 24,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: selected ? Ep.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 6),
                Icon(icon, size: 19, color: color),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final visualLabel =
                        compactLabel != null && constraints.maxWidth < 82
                        ? compactLabel!
                        : label;
                    return Text(
                      visualLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.epCaption.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: color,
                      ),
                    );
                  },
                ),
              ],
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
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: context.epColors.tabBarBackground,
          border: Border(top: BorderSide(color: borderColor)),
        ),
        padding: EdgeInsets.only(bottom: bottomPad),
        child: SizedBox(
          height: 66 + (textScale - 1).clamp(0, 1) * 14,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [for (final item in items) Expanded(child: item)],
            ),
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
    final bandCount = app.authed ? app.myBands.length : 0;
    final hasSwitchableIdentity =
        bandCount > 0 || app.myOrganizations.isNotEmpty;
    final switcherLabel = hasSwitchableIdentity ? 'SWITCH' : 'CREATE';
    return _TabBarShell(
      borderColor: context.epColors.border,
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
          icon: Icons.person_outline,
          label: 'PROFILE',
          selected: scr == Screen.myGigs,
          onPressed: app.openMyGigsTab,
        ),
        EpNavigationItem(
          icon: Icons.groups_outlined,
          label: switcherLabel,
          compactLabel: switcherLabel,
          selected: false,
          onPressed: () {
            if (app.authed && !app.membershipsLoaded) return;
            showSwitcherSheet(context);
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
      borderColor: context.epColors.border,
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

class OrganizerTabBar extends StatelessWidget {
  const OrganizerTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scr = app.current.screen;
    final canManage = app.canManageOrganization(app.organizationId);
    return _TabBarShell(
      borderColor: context.epColors.border,
      items: [
        EpNavigationItem(
          key: const Key('organizer-tab-dash'),
          icon: Icons.grid_view_rounded,
          label: 'DASH',
          selected: scr == Screen.orgDash,
          onPressed: () => app.resetTo(Screen.orgDash),
        ),
        if (canManage)
          EpNavigationItem(
            key: const Key('organizer-tab-opportunities'),
            icon: Icons.campaign_outlined,
            label: 'OPPORTUNITIES',
            selected: scr == Screen.orgOpportunities,
            onPressed: () => app.resetTo(Screen.orgOpportunities),
          ),
        EpNavigationItem(
          key: const Key('organizer-tab-venues'),
          icon: Icons.storefront_outlined,
          label: 'VENUES',
          selected: scr == Screen.orgVenues,
          onPressed: () => app.resetTo(Screen.orgVenues),
        ),
        if (canManage)
          EpNavigationItem(
            key: const Key('organizer-tab-team'),
            icon: Icons.group_outlined,
            label: 'TEAM',
            selected: scr == Screen.orgTeam,
            onPressed: () => app.resetTo(Screen.orgTeam),
          ),
        if (canManage)
          EpNavigationItem(
            key: const Key('organizer-tab-settings'),
            icon: Icons.settings_outlined,
            label: 'SETTINGS',
            selected: scr == Screen.orgSettings,
            onPressed: () => app.resetTo(Screen.orgSettings),
          ),
      ],
    );
  }
}
