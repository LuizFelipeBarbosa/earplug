import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../host_request_groups.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_states.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/opportunity_labels.dart';
import '../widgets/readiness_module.dart';

/// The organizer's GIGS home: the next confirmed event as the hero, the
/// readiness module while something is still to do, every live opportunity
/// with its fill state, and the past collapsed into one row. Hosts keep
/// their REQUESTS list at the same route.
class OrgGigsScreen extends StatefulWidget {
  const OrgGigsScreen({super.key});

  @override
  State<OrgGigsScreen> createState() => _OrgGigsScreenState();
}

class _OrgGigsScreenState extends State<OrgGigsScreen> {
  String? _loadedOrganizationId;
  bool _pastExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    if (organizationId.isEmpty) return;
    unawaited(app.refreshOpportunities(organizationId));
    unawaited(app.refreshOrganizationDashboard(organizationId));
    unawaited(app.refreshOrganizationStripeStatus());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final organizationId = app.organizationId;
    final canManage = app.canManageOrganization(organizationId);
    final status = app.opportunitiesStatus(organizationId);
    final groups = HostRequestGroups.from(
      app.opportunitiesFor(organizationId),
      now: DateTime.now(),
    );
    // Confirmed events keep their card so every listing shows its fill state;
    // the soonest one is also the hero.
    final listed = [...groups.confirmed, ...groups.active];

    // The module renders nothing while its sources load or once every step
    // is done, so the section header only makes room when it shows.
    final readinessFailed =
        canManage && app.organizationDashboardFailedFor(organizationId);
    final showReadiness =
        readinessFailed ||
        (canManage &&
            !(app
                    .readinessSnapshotFor(orgReadinessScope(organizationId))
                    ?.complete ??
                true));

    return RefreshIndicator(
      onRefresh: () => app.refreshOpportunities(organizationId),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          EpLayout.gutter,
          headerTopPad(context),
          EpLayout.gutter,
          tabBarClearance,
        ),
        children: [
          _Header(app: app, canManage: canManage),
          const SizedBox(height: 16),
          if (status == DataStatus.connecting)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (status == DataStatus.error)
            EpInlineRetry(
              message: 'Could not load opportunities. Please retry.',
              retryKey: const Key('org-gigs-retry'),
              topGap: 16,
              onRetry: () => app.refreshOpportunities(organizationId),
            )
          else ...[
            _UpNext(
              app: app,
              opportunity: groups.nextEvent,
              canManage: canManage,
            ),
            const SizedBox(height: 16),
            if (canManage) ...[
              ReadinessModule(scopeKey: orgReadinessScope(organizationId)),
              if (readinessFailed)
                ReadinessRetry(
                  retryKey: const Key('org-gigs-readiness-retry'),
                  onRetry: () =>
                      app.refreshOrganizationDashboard(organizationId),
                ),
            ],
            EpSectionHeader(
              label: 'OPPORTUNITIES · ${listed.length}',
              padding: EdgeInsets.only(top: showReadiness ? 24 : 0, bottom: 4),
            ),
            if (listed.isEmpty)
              EmptyNote(
                message: 'No open opportunities — post one.',
                actionLabel: canManage ? 'New opportunity' : null,
                onAction: canManage ? app.openOpportunityEditor : null,
              )
            else
              for (final opportunity in listed)
                _OpportunityCard(
                  app: app,
                  opportunity: opportunity,
                  confirmed: groups.confirmed.contains(opportunity),
                ),
            const SizedBox(height: 24),
            EpEntityRow(
              key: const Key('org-gigs-past-toggle'),
              title: 'PAST · ${groups.past.length}',
              sub: groups.cancelledCount > 0
                  ? 'Incl. ${groups.cancelledCount} cancelled'
                  : null,
              trailing: Icon(
                _pastExpanded ? Icons.expand_less : Icons.expand_more,
                color: context.epColors.contentSecondary,
              ),
              onTap: () => setState(() => _pastExpanded = !_pastExpanded),
            ),
            if (_pastExpanded)
              Column(
                key: const Key('org-gigs-past-body'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final opportunity in groups.past)
                    EpEntityRow(
                      key: ValueKey('org-gigs-past-${opportunity.id}'),
                      title: opportunity.title,
                      sub: _dateAndVenue(opportunity),
                      trailing: EpBadge(
                        label: opportunityStatusLabel(opportunity.status),
                        tone: EpBadgeTone.neutral,
                      ),
                      onTap: () => app.openOrgOpportunity(opportunity.id),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.app, required this.canManage});

  final AppState app;
  final bool canManage;

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('org-gigs-header'),
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // The title scales down beside the pill on narrow phones rather than
      // truncating.
      const Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: EpDisplay('Gigs', size: 44, maxLines: 1),
        ),
      ),
      if (canManage) ...[
        const SizedBox(width: 12),
        EpPill(
          key: const Key('org-gigs-new'),
          label: '+ New opportunity',
          variant: EpPillVariant.outline,
          size: EpPillSize.chip,
          onPressed: app.openOpportunityEditor,
        ),
      ],
    ],
  );
}

/// The hero: the soonest fully booked opportunity, or a prompt to post one.
class _UpNext extends StatelessWidget {
  const _UpNext({
    required this.app,
    required this.opportunity,
    required this.canManage,
  });

  final AppState app;
  final Opportunity? opportunity;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final event = opportunity;
    if (event == null) {
      return EpCard(
        key: const Key('org-gigs-next-event-empty'),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EpEyebrow('Nothing confirmed'),
            const SizedBox(height: 12),
            const EpDisplay(
              'No event coming up — post an opportunity',
              size: 24,
              maxLines: 3,
            ),
            if (canManage) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: EpPill(
                  key: const Key('org-gigs-post'),
                  label: 'Post an opportunity',
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

    return EpCard(
      key: const Key('org-gigs-next-event'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: EpEyebrow.accent('Up next')),
              const SizedBox(width: 12),
              Flexible(
                child: EpMonoText(
                  when,
                  key: const Key('org-gigs-next-event-when'),
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
          EpMonoText(_venueAndArea(event), keepCase: true, color: secondary),
          const SizedBox(height: 4),
          EpMonoText(_fillLine(event), keepCase: true, color: secondary),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: EpBadge(label: 'Confirmed', tone: EpBadgeTone.success),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: EpPill(
              key: const Key('org-gigs-next-event-view'),
              label: 'View event',
              variant: EpPillVariant.outline,
              size: EpPillSize.chip,
              onPressed: () => app.openOrgOpportunity(event.id),
            ),
          ),
        ],
      ),
    );
  }
}

/// One live opportunity: date block, title, date · venue, its fill state and
/// either the applied count or CONFIRMED. Drafts open in the composer.
class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.app,
    required this.opportunity,
    required this.confirmed,
  });

  final AppState app;
  final Opportunity opportunity;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final secondary = context.epColors.contentSecondary;
    final isDraft = opportunity.status == OpportunityStatus.draft;
    return EpCard(
      key: ValueKey('org-opp-${opportunity.id}'),
      onTap: () => isDraft
          ? app.openOpportunityEditor(opportunity.id)
          : app.openOrgOpportunity(opportunity.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpDateBlock(date: opportunity.startsAt),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EpDisplay(opportunity.title, size: 20, maxLines: 2),
                const SizedBox(height: 4),
                EpMonoText(
                  _dateAndVenue(opportunity),
                  keepCase: true,
                  color: secondary,
                ),
                const SizedBox(height: 4),
                EpMonoText(
                  _fillLine(opportunity),
                  keepCase: true,
                  color: secondary,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (confirmed)
                      const EpBadge(
                        label: 'Confirmed',
                        tone: EpBadgeTone.success,
                      )
                    else ...[
                      if (isDraft)
                        const EpBadge(
                          label: 'Draft',
                          tone: EpBadgeTone.neutral,
                        ),
                      EpBadge(
                        key: Key('org-opp-applied-${opportunity.id}'),
                        label: '${opportunity.applicationCount} applied',
                        tone: opportunity.applicationCount > 0
                            ? EpBadgeTone.selected
                            : EpBadgeTone.neutral,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "The Foghorn Club · Mission"; private events name no venue.
String _venueAndArea(Opportunity opportunity) {
  final venue = opportunity.venue;
  final isPrivate =
      opportunity.privateEvent ||
      opportunity.mode == OpportunityMode.privateBooking;
  final area = venue?.neighborhood ?? venue?.area ?? opportunity.area;
  return '${isPrivate ? 'Private event' : venue?.name ?? 'Venue TBD'} · $area';
}

/// "Oct 31 · The Foghorn Club".
String _dateAndVenue(Opportunity opportunity) {
  final isPrivate =
      opportunity.privateEvent ||
      opportunity.mode == OpportunityMode.privateBooking;
  final place = isPrivate
      ? 'Private event'
      : opportunity.venue?.name ?? 'Venue TBD';
  return '${shortDateLabel(opportunity.startsAt)} · $place';
}

/// "Headliner + Support · 1/2 slots booked".
String _fillLine(Opportunity opportunity) {
  final slots = opportunity.orderedSlots;
  final roles = <String>{for (final slot in slots) slotRoleLabel(slot.role)};
  final booked = slots.where((slot) => slot.status == SlotStatus.booked).length;
  return [
    if (roles.isNotEmpty) roles.join(' + '),
    '$booked/${slots.length} slots booked',
  ].join(' · ');
}
