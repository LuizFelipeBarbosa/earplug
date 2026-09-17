import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../host_request_groups.dart';
import '../initials.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/opportunity_labels.dart';
import '../widgets/readiness_module.dart';
import '../widgets/sheets.dart';

const _sectionGap = 28.0;

/// The organizer dash: identity header, the readiness module while something
/// is still to do, the next confirmed event as the hero, the MANAGE menu and,
/// for hosts, a note on where requests go.
class OrgDashScreen extends StatefulWidget {
  const OrgDashScreen({super.key});

  @override
  State<OrgDashScreen> createState() => _OrgDashScreenState();
}

class _OrgDashScreenState extends State<OrgDashScreen> {
  String? _loadedOrganizationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    if (organizationId.isEmpty) return;
    app.refreshOrganizationDashboard(organizationId);
    app.refreshOrganizationStripeStatus();
    app.refreshOpportunities(organizationId);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final organizationId = app.organizationId;
    final dashboard = app.organizationDashboardFor(organizationId);
    final organization =
        dashboard?.organization ?? app.currentOrganization?.organization;
    final canManage = app.canManageOrganization(organizationId);
    final isHost = app.currentIsHost;
    final nextEvent = HostRequestGroups.from(
      app.opportunitiesFor(organizationId),
      now: DateTime.now(),
    ).nextEvent;

    // Only managers can act on readiness; the module renders nothing while
    // its sources load or once every step is done, so the gap follows it.
    final showReadiness =
        canManage &&
        !(app
                .readinessSnapshotFor(orgReadinessScope(organizationId))
                ?.complete ??
            true);
    final readinessFailed =
        canManage &&
        dashboard == null &&
        !app.organizationDashboardLoadingFor(organizationId);

    final readiness = [
      if (canManage) ...[
        ReadinessModule(scopeKey: orgReadinessScope(organizationId)),
        if (readinessFailed)
          ReadinessRetry(
            retryKey: const Key('org-dash-readiness-retry'),
            onRetry: () => app.refreshOrganizationDashboard(organizationId),
          ),
      ],
    ];
    final hero = _NextEvent(
      app: app,
      opportunity: nextEvent,
      isHost: isHost,
      canManage: canManage,
    );
    final manage = [
      const EpEyebrow('Manage'),
      const SizedBox(height: 4),
      _MenuRows(app: app, canManage: canManage, isHost: isHost),
      if (isHost) ...[
        const SizedBox(height: 20),
        EpMonoText(
          'Requests reach artists directly — they never appear on the public '
          "map, and there's no ticketing.",
          key: const Key('org-dash-footer-note'),
          color: context.epColors.muted,
          keepCase: true,
        ),
      ],
    ];

    if (EpLayout.isDesktop(context)) {
      // The rail carries the identity, the switcher and "back to discover",
      // so the content column starts at the hero.
      return ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [hero, const SizedBox(height: 40), ...manage],
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 40),
                Expanded(
                  flex: 10,
                  child: Container(
                    padding: const EdgeInsets.only(left: 40),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: context.epColors.line),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: readiness,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        headerTopPad(context),
        EpLayout.gutter,
        tabBarClearance,
      ),
      children: [
        _Header(
          app: app,
          organization: organization,
          role: app.organizerRoleFor(organizationId) ?? dashboard?.role,
        ),
        const SizedBox(height: _sectionGap),
        ...readiness,
        if (showReadiness || readinessFailed)
          const SizedBox(height: _sectionGap),
        hero,
        const SizedBox(height: _sectionGap),
        ...manage,
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.app,
    required this.organization,
    required this.role,
  });

  final AppState app;
  final Organization? organization;
  final OrganizationRole? role;

  @override
  Widget build(BuildContext context) {
    final name = organization?.name ?? 'Organizer';
    final roleText = role == null ? 'Member' : organizationRoleLabel(role!);
    return Row(
      key: const Key('org-dash-header'),
      children: [
        Expanded(
          child: InkWell(
            onTap: () => showSwitcherSheet(context),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: EpNetworkImage(
                    url: organization?.photoUrls.firstOrNull,
                    cacheWidth: 40,
                    cacheHeight: 40,
                    fallback: EpAvatarTile(
                      initials: initialsFirstWords(
                        name,
                        stripPunctuation: true,
                        fallback: '',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: EpDisplay(name, size: 20, maxLines: 2),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.expand_more,
                            size: 16,
                            color: context.epColors.muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      EpEyebrow('Organizer · $roleText'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        EpPill(
          key: const Key('org-dash-discover'),
          label: 'Discover',
          variant: EpPillVariant.accentOutline,
          size: EpPillSize.chip,
          onPressed: app.toFanView,
        ),
      ],
    );
  }
}

/// The hero: the next fully booked request or opportunity, or a prompt to
/// post one.
class _NextEvent extends StatelessWidget {
  const _NextEvent({
    required this.app,
    required this.opportunity,
    required this.isHost,
    required this.canManage,
  });

  final AppState app;
  final Opportunity? opportunity;
  final bool isHost;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final event = opportunity;
    if (event == null) {
      return EpCard(
        key: const Key('org-dash-next-event-empty'),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EpEyebrow('Nothing confirmed'),
            const SizedBox(height: 12),
            EpDisplay(
              isHost
                  ? 'No event coming up — post a request'
                  : 'No event coming up — post an opportunity',
              size: 24,
              maxLines: 3,
            ),
            if (canManage) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: EpPill(
                  key: const Key('org-dash-post-request'),
                  label: isHost ? 'Post a request' : 'Post an opportunity',
                  variant: EpPillVariant.primary,
                  size: EpPillSize.chip,
                  onPressed: app.openOpportunityEditor,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final secondary = context.epColors.contentSecondary;
    final startsAt = event.startsAt.toLocal();
    final when =
        '${dateLabel(startsAt)} · '
        '${TimeOfDay.fromDateTime(startsAt).format(context)}';
    final isPrivate =
        event.privateEvent || event.mode == OpportunityMode.privateBooking;
    final location = isPrivate
        ? 'Private event · ${event.venue?.neighborhood ?? event.area}'
        : '${event.venue?.name ?? 'Venue TBD'} · '
              '${event.venue?.area ?? event.area}';

    return EpCard(
      key: const Key('org-dash-next-event'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: EpEyebrow.accent('Next event')),
              const SizedBox(width: 12),
              Flexible(
                child: EpMonoText(
                  when,
                  key: const Key('org-dash-next-event-when'),
                  color: secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          EpDisplay(event.title, size: 32, maxLines: 3),
          const SizedBox(height: 12),
          EpMonoText(location, keepCase: true, color: secondary),
          const SizedBox(height: 4),
          EpMonoText(_bookedSlotLine(event), keepCase: true, color: secondary),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: 'Confirmed',
              tone: EpStatusPillTone.success,
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: EpPill(
              key: const Key('org-dash-next-event-view'),
              label: isHost ? 'View request' : 'View opportunity',
              variant: EpPillVariant.outline,
              size: EpPillSize.chip,
              onPressed: () => app.openOpportunityApplicants(event.id),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Headliner · $300.00 · 2/2 slots booked".
String _bookedSlotLine(Opportunity opportunity) {
  final slots = [...opportunity.slots]
    ..sort((a, b) => a.order.compareTo(b.order));
  final booked = slots.where((slot) => slot.status == SlotStatus.booked).length;
  final lead = slots.firstOrNull;
  return [
    if (lead != null) slotRoleLabel(lead.role),
    if (lead != null) Money(lead.guaranteeMinor, opportunity.currency).label,
    '$booked/${slots.length} slots booked',
  ].join(' · ');
}

class _MenuRows extends StatelessWidget {
  const _MenuRows({
    required this.app,
    required this.canManage,
    required this.isHost,
  });

  final AppState app;
  final bool canManage;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final organizationId = app.organizationId;
    final financeEnabled =
        app.organizationStripeStatusFor(organizationId)?.state ==
        StripeAccountState.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canManage)
          EpMenuRow(
            key: const Key('org-dash-command-opportunity'),
            icon: Icons.add,
            label: isHost ? 'New request' : 'New opportunity',
            trailing: Flexible(
              child: EpMonoText(
                'Post a slot for artists',
                color: context.epColors.muted,
              ),
            ),
            onTap: app.openOpportunityEditor,
          ),
        if (isHost)
          EpMenuRow(
            key: const Key('org-dash-locations'),
            icon: Icons.place_outlined,
            label: 'Locations',
            onTap: () => app.go(Screen.privateLocations),
          )
        else if (app.currentIsVenueOperator)
          EpMenuRow(
            key: const Key('org-dash-command-venues'),
            icon: Icons.place_outlined,
            label: 'Venues',
            onTap: () => app.go(Screen.orgVenues),
          ),
        if (canManage && !isHost)
          EpMenuRow(
            key: const Key('org-dash-command-team'),
            icon: Icons.people_outline,
            label: 'Team',
            onTap: () => app.go(Screen.orgTeam),
          ),
        if (app.canSeeFinance(organizationId))
          EpMenuRow(
            key: const Key('org-dash-command-finance'),
            icon: Icons.confirmation_number_outlined,
            label: 'Finance',
            trailing: financeEnabled
                ? null
                : const StatusPill(
                    key: Key('org-dash-finance-badge'),
                    label: 'Set up',
                    tone: EpStatusPillTone.attention,
                  ),
            onTap: app.openFinance,
          ),
        if (canManage)
          EpMenuRow(
            key: const Key('org-dash-command-settings'),
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => app.go(Screen.orgSettings),
          ),
      ],
    );
  }
}
