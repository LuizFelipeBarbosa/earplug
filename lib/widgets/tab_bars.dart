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
    final color = selected ? context.epColors.accent : context.epColors.muted;
    if (vertical) {
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onPressed,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: Theme.of(
                        context,
                      ).textTheme.epLabel.copyWith(fontSize: 12, color: color),
                    ),
                  ),
                ],
              ),
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
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          focusColor: context.epColors.accent.withValues(alpha: .2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final visualLabel =
                      compactLabel != null && constraints.maxWidth < 82
                      ? compactLabel!
                      : label;
                  return Text(
                    visualLabel.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.epChipLabel.copyWith(color: color),
                  );
                },
              ),
            ],
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
          height: EpLayout.tabBarHeight + (textScale - 1).clamp(0, 1) * 14,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
      borderColor: context.epColors.line,
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
          icon: Icons.confirmation_number_outlined,
          label: 'YOU',
          selected:
              scr == Screen.myGigs ||
              scr == Screen.myTickets ||
              scr == Screen.ticket,
          onPressed: app.openMyGigsTab,
        ),
        EpNavigationItem(
          vertical: vertical,
          icon: switcherLabel == 'SWITCH' ? Icons.mic_none : Icons.add,
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
      borderColor: context.epColors.line,
      items: [
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.home_outlined,
          label: 'DASH',
          selected: scr == Screen.bandDash,
          onPressed: () => app.resetTo(Screen.bandDash),
        ),
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.mic_none,
          label: 'PROFILE',
          selected: scr == Screen.bandEdit,
          onPressed: () => app.resetTo(Screen.bandEdit),
        ),
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.list,
          label: 'GIGS',
          selected: scr == Screen.gigMgr,
          onPressed: () => app.resetTo(Screen.gigMgr),
        ),
        EpNavigationItem(
          vertical: vertical,
          icon: Icons.bar_chart,
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
      borderColor: context.epColors.line,
      items: [
        EpNavigationItem(
          vertical: vertical,
          key: const Key('organizer-tab-dash'),
          icon: Icons.home_outlined,
          label: 'DASH',
          selected: scr == Screen.orgDash,
          onPressed: () => app.resetTo(Screen.orgDash),
        ),
        if (app.currentIsHost || canManage)
          EpNavigationItem(
            vertical: vertical,
            key: const Key('organizer-tab-opportunities'),
            icon: Icons.sensors,
            label: app.currentIsHost ? 'REQUESTS' : 'GIGS',
            selected: scr == Screen.orgOpportunities,
            onPressed: () => app.resetTo(Screen.orgOpportunities),
          ),
        if (!app.currentIsHost && canManage)
          EpNavigationItem(
            vertical: vertical,
            key: const Key('organizer-tab-team'),
            icon: Icons.people_outline,
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
    return Container(
      width: EpLayout.railWidth,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: context.epColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: EpLogo.full(width: 113, height: 32),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      label.toUpperCase(),
                      style: Theme.of(context).textTheme.epSection,
                    ),
                    const SizedBox(height: 16),
                    navigation,
                    const Spacer(),
                    if (label == 'DISCOVER') ...[
                      Text(
                        'GOOD MUSIC.\nCLOSER TO HOME.',
                        style: Theme.of(context).textTheme.epDisplayAt(24),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Find a show. Support the scene.',
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          color: context.epColors.muted,
                        ),
                      ),
                    ] else
                      OutlinedButton(
                        onPressed: () => showSwitcherSheet(context),
                        child: const Text('BACK TO DISCOVER'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
