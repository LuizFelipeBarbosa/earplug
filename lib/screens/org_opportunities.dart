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
import '../widgets/ep_sheet.dart';
import '../widgets/ep_states.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/opportunity_labels.dart';
import '../widgets/sheets.dart';
import 'door_mode.dart';

class OrgOpportunitiesScreen extends StatefulWidget {
  const OrgOpportunitiesScreen({super.key});

  @override
  State<OrgOpportunitiesScreen> createState() => _OrgOpportunitiesScreenState();
}

class _OrgOpportunitiesScreenState extends State<OrgOpportunitiesScreen> {
  String? _loadedOrganizationId;
  final _pendingSales = <String>{};
  int _tab = 0;
  bool _pastExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_loadedOrganizationId == app.organizationId) return;
    _loadedOrganizationId = app.organizationId;
    unawaited(app.refreshOpportunities(app.organizationId));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final status = app.opportunitiesStatus(app.organizationId);
    final opportunities = app.opportunitiesFor(app.organizationId);
    final salesByOpportunity = <String, TicketSales?>{};
    for (final opportunity in opportunities) {
      if (opportunity.ticketing != OpportunityTicketing.paid) continue;
      final gig = _publishedGig(app, opportunity);
      if (gig == null) continue;
      final sales = app.salesFor(gig.id);
      salesByOpportunity[opportunity.id] = sales;
      if (sales != null || !_pendingSales.add(gig.id)) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || app.organizationId != opportunity.organizationId) {
          _pendingSales.remove(gig.id);
          return;
        }
        unawaited(
          app.loadTicketSales(gig.id).whenComplete(() {
            _pendingSales.remove(gig.id);
          }),
        );
      });
    }
    final groups = HostRequestGroups.from(opportunities, now: DateTime.now());
    final isHost = app.currentIsHost;
    final noun = isHost ? 'request' : 'opportunity';
    final canManage = app.canManageOrganization(app.organizationId);

    Widget card(Opportunity opportunity, _RequestGroup group) =>
        _OpportunityCard(
          opportunity: opportunity,
          group: group,
          sales: salesByOpportunity[opportunity.id],
          onActions: () => _showActions(app, opportunity),
        );

    List<Widget> activeView() => [
      if (groups.confirmed.isNotEmpty) ...[
        EpSectionHeader(
          label: 'CONFIRMED · ${groups.confirmed.length}',
          padding: const EdgeInsets.only(top: 16, bottom: 4),
        ),
        for (final opportunity in groups.confirmed)
          card(opportunity, _RequestGroup.confirmed),
      ],
      if (groups.active.isNotEmpty) ...[
        EpSectionHeader(
          label: 'ACTIVE · ${groups.active.length}',
          padding: EdgeInsets.only(
            top: groups.confirmed.isEmpty ? 16 : 24,
            bottom: 4,
          ),
        ),
        for (final opportunity in groups.active)
          card(opportunity, _RequestGroup.active),
      ] else if (groups.confirmed.isEmpty)
        EmptyNote(
          message: opportunities.isEmpty
              ? 'No ${noun}s yet — post one.'
              : 'No open ${noun}s — post one.',
          actionLabel: canManage ? 'New $noun' : null,
          onAction: canManage ? app.openOpportunityEditor : null,
        ),
      const SizedBox(height: 24),
      EpEntityRow(
        key: const Key('org-opps-past-toggle'),
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
          key: const Key('org-opps-past-body'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            for (final opportunity in groups.past)
              card(opportunity, _RequestGroup.past),
          ],
        ),
    ];

    List<Widget> confirmedView() => [
      if (groups.confirmed.isEmpty)
        EmptyNote(message: 'No confirmed ${noun}s yet.')
      else ...[
        const SizedBox(height: 16),
        for (final opportunity in groups.confirmed)
          card(opportunity, _RequestGroup.confirmed),
      ],
    ];

    List<Widget> pastView() => [
      if (groups.past.isEmpty)
        EmptyNote(message: 'No past ${noun}s.')
      else ...[
        const SizedBox(height: 16),
        for (final opportunity in groups.past)
          card(opportunity, _RequestGroup.past),
      ],
    ];

    return RefreshIndicator(
      onRefresh: () => app.refreshOpportunities(app.organizationId),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          EpLayout.gutter,
          headerTopPad(context),
          EpLayout.gutter,
          tabBarClearance,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The title scales down beside the pill on narrow phones
                    // rather than truncating, as segment labels do.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: EpDisplay(
                        isHost ? 'Requests' : 'Opportunities',
                        key: const Key('org-opps-title'),
                        size: 44,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    EpMonoText(
                      isHost
                          ? 'Post a request. Find your artist.'
                          : 'Post a slot. Find your next artist.',
                      keepCase: true,
                      color: context.epColors.contentSecondary,
                    ),
                  ],
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 12),
                EpPill(
                  key: const Key('org-opps-new'),
                  label: isHost ? '+ New request' : '+ New opportunity',
                  variant: EpPillVariant.outline,
                  size: EpPillSize.chip,
                  onPressed: app.openOpportunityEditor,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          EpSegmentTabs(
            key: const Key('org-opps-tabs'),
            labels: const ['Active', 'Confirmed', 'Past'],
            selected: _tab,
            onSelect: (index) => setState(() => _tab = index),
          ),
          if (status == DataStatus.connecting)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (status == DataStatus.error)
            EpInlineRetry(
              message: 'Could not load ${noun}s. Please retry.',
              topGap: 16,
              onRetry: () => app.refreshOpportunities(app.organizationId),
            )
          else
            ...switch (_tab) {
              0 => activeView(),
              1 => confirmedView(),
              _ => pastView(),
            },
        ],
      ),
    );
  }

  void _showActions(AppState app, Opportunity opportunity) {
    final gig = _publishedGig(app, opportunity);
    unawaited(
      showEpActionSheet(
        context,
        header: opportunity.title,
        items: [
          if (gig != null)
            EpActionSheetItem(
              label: 'Door',
              icon: Icons.sensor_door_outlined,
              onPressed: () => unawaited(
                showOrganizerDoorMode(
                  context,
                  gigId: gig.id,
                  gigTitle: opportunity.title,
                  venueName:
                      opportunity.venue?.name ??
                      (opportunity.privateEvent ||
                              opportunity.mode == OpportunityMode.privateBooking
                          ? 'Private event'
                          : 'Venue TBD'),
                  doorsTime: gig.doorsAt != null
                      ? TimeOfDay.fromDateTime(
                          gig.doorsAt!.toLocal(),
                        ).format(context)
                      : gig.time.split('/').first.trim(),
                ),
              ),
            ),
          EpActionSheetItem(
            label: 'Edit',
            icon: Icons.edit,
            onPressed: () => app.openOpportunityEditor(opportunity.id),
          ),
          if (opportunity.status != OpportunityStatus.draft)
            EpActionSheetItem(
              label: 'View applicants',
              icon: Icons.people_outline,
              onPressed: () => app.openOpportunityApplicants(opportunity.id),
            ),
          EpActionSheetItem(
            label: 'Duplicate',
            icon: Icons.copy,
            onPressed: () => unawaited(
              _runAction(app, opportunity, _OpportunityAction.duplicate),
            ),
          ),
          if (opportunity.status == OpportunityStatus.open)
            EpActionSheetItem(
              label: 'Close applications',
              icon: Icons.lock_outline,
              onPressed: () => unawaited(
                _runAction(app, opportunity, _OpportunityAction.close),
              ),
            ),
          if (opportunity.status == OpportunityStatus.applicationsClosed ||
              opportunity.status == OpportunityStatus.booking)
            EpActionSheetItem(
              label: 'Reopen',
              icon: Icons.lock_open,
              onPressed: () => unawaited(
                _runAction(app, opportunity, _OpportunityAction.reopen),
              ),
            ),
          if (opportunity.status != OpportunityStatus.cancelled &&
              opportunity.status != OpportunityStatus.completed)
            EpActionSheetItem(
              label: 'Cancel…',
              icon: Icons.block,
              onPressed: () => unawaited(
                _runAction(app, opportunity, _OpportunityAction.cancel),
              ),
            ),
          if (opportunity.status == OpportunityStatus.draft)
            EpActionSheetItem(
              label: 'Delete draft',
              icon: Icons.delete_outline,
              destructive: true,
              onPressed: () => unawaited(
                _runAction(app, opportunity, _OpportunityAction.delete),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _runAction(
    AppState app,
    Opportunity opportunity,
    _OpportunityAction action,
  ) async {
    try {
      final String message;
      switch (action) {
        case _OpportunityAction.duplicate:
          await app.repository.duplicateOpportunity(opportunity.id);
          message = 'Opportunity duplicated.';
        case _OpportunityAction.close:
          await app.repository.closeOpportunityApplications(opportunity.id);
          message = 'Applications closed.';
        case _OpportunityAction.reopen:
          final now = DateTime.now();
          if (DateUtils.dateOnly(
            opportunity.startsAt,
          ).isBefore(DateUtils.dateOnly(now))) {
            app.say('This opportunity has already started.');
            return;
          }
          final date = await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: now,
            lastDate: opportunity.startsAt,
          );
          if (date == null || !mounted) return;
          await app.repository.reopenOpportunity(
            opportunityId: opportunity.id,
            applicationsCloseAt: date,
          );
          message = 'Opportunity reopened.';
        case _OpportunityAction.cancel:
          final confirmed = await epConfirm(
            context,
            title: 'Cancel opportunity?',
            body:
                'Active applications will be declined and the opportunity will be cancelled.',
          );
          if (!confirmed || !mounted) return;
          await app.repository.cancelOpportunity(opportunity.id);
          message = 'Opportunity cancelled.';
        case _OpportunityAction.delete:
          await app.repository.deleteOpportunityDraft(opportunity.id);
          message = 'Draft deleted.';
      }
      await app.refreshOpportunities(app.organizationId);
      if (mounted) app.say(message);
    } catch (error) {
      if (mounted) app.say('Could not complete that action. Please retry.');
      return;
    }
  }
}

enum _RequestGroup { active, confirmed, past }

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.opportunity,
    required this.group,
    required this.onActions,
    this.sales,
  });

  final Opportunity opportunity;
  final _RequestGroup group;
  final VoidCallback onActions;
  final TicketSales? sales;

  @override
  Widget build(BuildContext context) {
    final secondary = context.epColors.contentSecondary;
    final venueApproval = _venueApprovalStatus(opportunity.venueConsentStatus);
    final ticketSales = sales;
    final isPrivate =
        opportunity.privateEvent ||
        opportunity.mode == OpportunityMode.privateBooking;
    final location = isPrivate
        ? 'Private event · '
              '${opportunity.venue?.neighborhood ?? opportunity.area}'
        : '${opportunity.venue?.name ?? 'Venue TBD'} · '
              '${opportunity.venue?.area ?? opportunity.area}';

    return EpCard(
      key: ValueKey('org-opp-${opportunity.id}'),
      onTap: onActions,
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
                EpMonoText(location, keepCase: true, color: secondary),
                const SizedBox(height: 4),
                EpMonoText(
                  group == _RequestGroup.active
                      ? _activeSlotLine(opportunity)
                      : bookedSlotLine(opportunity, countExtraRoles: true),
                  keepCase: true,
                  color: secondary,
                ),
                if (ticketSales != null) ...[
                  const SizedBox(height: 4),
                  EpMonoText(
                    '${ticketSales.sold}/${ticketSales.capacity} sold · '
                    '${ticketSales.net.label} net',
                    key: Key('org-opp-sales-${opportunity.id}'),
                    keepCase: true,
                    color: secondary,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    ..._statusPills(),
                    if (venueApproval != null)
                      EpBadge(
                        key: Key('org-opp-venue-consent-${opportunity.id}'),
                        label: venueApproval.label,
                        tone: venueApproval.tone,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          EpIconPill(
            key: Key('org-opp-actions-${opportunity.id}'),
            icon: Icons.more_horiz,
            semanticLabel: 'Actions',
            onPressed: onActions,
          ),
        ],
      ),
    );
  }

  List<Widget> _statusPills() => switch (group) {
    _RequestGroup.confirmed => const [
      EpBadge(label: 'Confirmed', tone: EpBadgeTone.success),
    ],
    _RequestGroup.past => [
      EpBadge(
        label: opportunityStatusLabel(opportunity.status),
        tone: EpBadgeTone.neutral,
      ),
    ],
    _RequestGroup.active => [
      switch (opportunity.status) {
        OpportunityStatus.draft => const EpBadge(
          label: 'Draft',
          tone: EpBadgeTone.neutral,
        ),
        OpportunityStatus.applicationsClosed => const EpBadge(
          label: 'Closed',
          tone: EpBadgeTone.neutral,
        ),
        OpportunityStatus.booking => const EpBadge(
          label: 'Booking',
          tone: EpBadgeTone.neutral,
        ),
        _ => null,
      },
      EpBadge(
        key: Key('org-opp-applied-${opportunity.id}'),
        label: '${opportunity.applicationCount} applied',
        tone: opportunity.applicationCount > 0
            ? EpBadgeTone.selected
            : EpBadgeTone.neutral,
      ),
    ].nonNulls.toList(),
  };
}

/// "Headliner, Support · 2 slots · closes Sep 21".
String _activeSlotLine(Opportunity opportunity) {
  final slots = opportunity.orderedSlots;
  final roles = <String>{for (final slot in slots) slotRoleLabel(slot.role)};
  final count = slots.length;
  final closing =
      opportunity.status == OpportunityStatus.open ||
          opportunity.status == OpportunityStatus.draft
      ? 'closes ${shortDateLabel(opportunity.applicationsCloseAt)}'
      : 'applications closed';
  return [
    if (roles.isNotEmpty) roles.join(', '),
    '$count ${count == 1 ? 'slot' : 'slots'}',
    closing,
  ].join(' · ');
}

({String label, EpBadgeTone tone})? _venueApprovalStatus(
  VenueConsentStatus? status,
) => switch (status) {
  VenueConsentStatus.pending => (
    label: 'Pending approval',
    tone: EpBadgeTone.warning,
  ),
  VenueConsentStatus.granted => (label: 'Approved', tone: EpBadgeTone.success),
  VenueConsentStatus.declined => (label: 'Declined', tone: EpBadgeTone.warning),
  VenueConsentStatus.withdrawn => (
    label: 'Withdrawn',
    tone: EpBadgeTone.neutral,
  ),
  VenueConsentStatus.revoked => (label: 'Revoked', tone: EpBadgeTone.warning),
  null || VenueConsentStatus.unknown => null,
};

enum _OpportunityAction { duplicate, close, reopen, cancel, delete }

Gig? _publishedGig(AppState app, Opportunity opportunity) =>
    app.allGigs.where((gig) => gig.opportunityId == opportunity.id).firstOrNull;
