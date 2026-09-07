import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'branding.dart';
import 'sheets.dart';

class EpNavigationItem extends StatelessWidget {
  final bool vertical;
  final IconData icon;
  final String label;
  final String? compactLabel;
  final bool selected;
  final VoidCallback onPressed;

  const EpNavigationItem({
    super.key,
    this.vertical = false,
    required this.icon,
    required this.label,
    this.compactLabel,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.epColors.ink : context.epColors.mute;
    if (vertical) {
      return Semantics(
        selected: selected,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextButton.icon(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(double.infinity, 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              backgroundColor: selected
                  ? context.epColors.surfaceSelected
                  : null,
              foregroundColor: selected
                  ? context.epColors.accent
                  : context.epColors.contentSecondary,
            ),
            icon: Icon(icon, size: 21),
            label: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(label, style: const TextStyle(letterSpacing: .6)),
            ),
          ),
        ),
      );
    }
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
  final bool vertical;
  final List<Widget> items;
  final Color borderColor;

  const _TabBarShell({
    required this.items,
    required this.borderColor,
    required this.vertical,
  });

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      );
    }
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
  const FanTabBar({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scr = app.current.screen;
    final bandCount = app.authed ? app.myBands.length : 0;
    final hasSwitchableIdentity =
        bandCount > 0 || app.myOrganizations.isNotEmpty;
    final switcherLabel = hasSwitchableIdentity ? 'SWITCH' : 'CREATE';
    return _TabBarShell(
      vertical: vertical,
      borderColor: context.epColors.border,
      items: [
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.home_outlined,
          label: 'GIGS',
          selected: scr == Screen.home,
          onPressed: () => app.resetTo(Screen.home),
        ),
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.search,
          label: 'EXPLORE',
          selected: scr == Screen.explore,
          onPressed: () => app.resetTo(Screen.explore),
        ),
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.person_outline,
          label: 'PROFILE',
          selected:
              scr == Screen.myGigs ||
              scr == Screen.myTickets ||
              scr == Screen.ticket,
          onPressed: app.openMyGigsTab,
        ),
        EpNavigationItem(
          vertical: vertical,
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
  const BandTabBar({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scr = app.current.screen;
    return _TabBarShell(
      vertical: vertical,
      borderColor: context.epColors.border,
      items: [
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.grid_view_rounded,
          label: 'DASH',
          selected: scr == Screen.bandDash,
          onPressed: () => app.resetTo(Screen.bandDash),
        ),
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.person_outline,
          label: 'PROFILE',
          selected: scr == Screen.bandEdit,
          onPressed: () => app.resetTo(Screen.bandEdit),
        ),
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.table_rows_outlined,
          label: 'GIGS',
          selected: scr == Screen.gigMgr,
          onPressed: () => app.resetTo(Screen.gigMgr),
        ),
        EpNavigationItem(
          vertical: vertical,
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
  const OrganizerTabBar({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scr = app.current.screen;
    final canManage = app.canManageOrganization(app.organizationId);
    return _TabBarShell(
      vertical: vertical,
      borderColor: context.epColors.border,
      items: [
        EpNavigationItem(
          vertical: vertical,
          key: const Key('organizer-tab-dash'),
          icon: Icons.grid_view_rounded,
          label: 'DASH',
          selected: scr == Screen.orgDash,
          onPressed: () => app.resetTo(Screen.orgDash),
        ),
        if (app.currentIsHost || canManage)
          EpNavigationItem(
            vertical: vertical,
            key: const Key('organizer-tab-opportunities'),
            icon: Icons.campaign_outlined,
            label: app.currentIsHost ? 'REQUESTS' : 'GIGS',
            selected: scr == Screen.orgOpportunities,
            onPressed: () => app.resetTo(Screen.orgOpportunities),
          ),
        if (!app.currentIsHost && canManage)
          EpNavigationItem(
            vertical: vertical,
            key: const Key('organizer-tab-team'),
            icon: Icons.group_outlined,
            label: 'TEAM',
            selected: scr == Screen.orgTeam,
            onPressed: () => app.resetTo(Screen.orgTeam),
          ),
        if (app.currentIsHost || canManage)
          EpNavigationItem(
            vertical: vertical,
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

/// Persistent navigation for the wider web workspace.
class EpDesktopSidebar extends StatelessWidget {
  const EpDesktopSidebar({
    super.key,
    required this.navigation,
    required this.label,
  });

  final Widget navigation;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 224,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.epBody,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 28, 8, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const EpLogo.compact(height: 42),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'EARPLUG',
                          style: epDisplay(
                            size: 23,
                            color: context.epColors.contentPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'YOUR LOCAL MUSIC SCENE',
                  style: Theme.of(
                    context,
                  ).textTheme.epMeta.copyWith(letterSpacing: 1),
                ),
                const SizedBox(height: 44),
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 16),
                  child: Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.epMeta.copyWith(letterSpacing: 1.5),
                  ),
                ),
                navigation,
                const SizedBox(height: 40),
                Divider(color: context.epColors.border),
                const SizedBox(height: 24),
                Text(
                  'Good music.\nCloser to home.',
                  style: Theme.of(
                    context,
                  ).textTheme.epSectionHeading.copyWith(height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Find a show. Support the scene.',
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
