import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
    final sections = <String, List<Opportunity>>{
      'DRAFTS': [],
      'OPEN': [],
      'CLOSED': [],
      'CONFIRMED': [],
      'PAST': [],
      'CANCELLED': [],
    };
    for (final opportunity in opportunities) {
      final section = switch (opportunity.status) {
        OpportunityStatus.draft => 'DRAFTS',
        OpportunityStatus.open => 'OPEN',
        OpportunityStatus.applicationsClosed ||
        OpportunityStatus.booking => 'CLOSED',
        OpportunityStatus.confirmed => 'CONFIRMED',
        OpportunityStatus.completed => 'PAST',
        OpportunityStatus.cancelled => 'CANCELLED',
      };
      sections[section]!.add(opportunity);
    }

    return RefreshIndicator(
      onRefresh: () => app.refreshOpportunities(app.organizationId),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          headerTopPad(context),
          16,
          tabBarClearance,
        ),
        children: [
          EpPageHeading(
            title: app.currentIsHost ? 'REQUESTS' : 'OPPORTUNITIES',
            description: app.currentIsHost
                ? 'Post a request. Find your artist.'
                : 'Post a slot. Find your next artist.',
            action: app.canManageOrganization(app.organizationId)
                ? FilledButton.icon(
                    key: const Key('org-opps-new'),
                    onPressed: app.openOpportunityEditor,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      app.currentIsHost ? 'NEW REQUEST' : 'NEW OPPORTUNITY',
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 18),
          if (status == DataStatus.connecting)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (status == DataStatus.error)
            Column(
              children: [
                const Text('Could not load opportunities. Please retry.'),
                TextButton(
                  onPressed: () => app.refreshOpportunities(app.organizationId),
                  child: const Text('RETRY'),
                ),
              ],
            )
          else if (opportunities.isEmpty)
            DashedBox(
              child: Text(
                'No opportunities yet. Post one to start booking artists.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.epCaption,
              ),
            )
          else
            for (final section in sections.entries)
              if (section.value.isNotEmpty)
                Column(
                  key: ValueKey('org-opps-section-${section.key}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionBar(label: section.key, count: section.value.length),
                    for (final opportunity in section.value) ...[
                      _OpportunityCard(
                        opportunity: opportunity,
                        sales: salesByOpportunity[opportunity.id],
                        onActions: () => _showActions(app, opportunity),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
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
              label: 'DOOR',
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
            label: 'EDIT',
            icon: Icons.edit,
            onPressed: () => app.openOpportunityEditor(opportunity.id),
          ),
          if (opportunity.status != OpportunityStatus.draft)
            EpActionSheetItem(
              label: 'VIEW APPLICANTS',
              icon: Icons.people_outline,
              onPressed: () => app.openOpportunityApplicants(opportunity.id),
            ),
          EpActionSheetItem(
            label: 'DUPLICATE',
            icon: Icons.copy,
            onPressed: () => unawaited(
              _runAction(app, opportunity, _OpportunityAction.duplicate),
            ),
          ),
          if (opportunity.status == OpportunityStatus.open)
            EpActionSheetItem(
              label: 'CLOSE APPLICATIONS',
              icon: Icons.lock_outline,
              onPressed: () => unawaited(
                _runAction(app, opportunity, _OpportunityAction.close),
              ),
            ),
          if (opportunity.status == OpportunityStatus.applicationsClosed ||
              opportunity.status == OpportunityStatus.booking)
            EpActionSheetItem(
              label: 'REOPEN',
              icon: Icons.lock_open,
              onPressed: () => unawaited(
                _runAction(app, opportunity, _OpportunityAction.reopen),
              ),
            ),
          if (opportunity.status != OpportunityStatus.cancelled &&
              opportunity.status != OpportunityStatus.completed)
            EpActionSheetItem(
              label: 'CANCEL…',
              icon: Icons.block,
              onPressed: () => unawaited(
                _runAction(app, opportunity, _OpportunityAction.cancel),
              ),
            ),
          if (opportunity.status == OpportunityStatus.draft)
            EpActionSheetItem(
              label: 'DELETE DRAFT',
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
          final confirmed = await _confirm(
            context,
            'Cancel opportunity?',
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

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.opportunity,
    required this.onActions,
    this.sales,
  });

  final Opportunity opportunity;
  final VoidCallback onActions;
  final TicketSales? sales;

  @override
  Widget build(BuildContext context) {
    final slots = [...opportunity.slots]
      ..sort((a, b) => a.order.compareTo(b.order));
    final slotSummary = slots
        .map(
          (slot) =>
              '${slotRoleLabel(slot.role)} '
              '${Money(slot.guaranteeMinor, opportunity.currency).label}',
        )
        .join(' · ');
    final textTheme = Theme.of(context).textTheme;
    final venueApproval = _venueApprovalStatus(opportunity.venueConsentStatus);
    final ticketSales = sales;
    final venueLabel =
        opportunity.privateEvent ||
            opportunity.mode == OpportunityMode.privateBooking
        ? 'Private event'
        : opportunity.venue?.name ?? 'Venue TBD';

    return EpCard(
      key: ValueKey('org-opp-${opportunity.id}'),
      onTap: onActions,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DateBlock.forDate(opportunity.startsAt, size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(opportunity.title, style: textTheme.epSectionHeading),
                const SizedBox(height: 4),
                Text(
                  '$venueLabel · '
                  '${opportunity.venue?.area ?? opportunity.area}',
                  style: textTheme.epMeta,
                ),
                const SizedBox(height: 4),
                Text(slotSummary, style: textTheme.epMeta),
                if (ticketSales != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${ticketSales.sold}/${ticketSales.capacity} sold · '
                    '${ticketSales.net.label} net',
                    key: Key('org-opp-sales-${opportunity.id}'),
                    style: textTheme.epCaption,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Applications close ${dateLabel(opportunity.applicationsCloseAt)}',
                  style: textTheme.epCaption,
                ),
                if (opportunity.applicationCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${opportunity.applicationCount} applied',
                    style: textTheme.epCaption,
                  ),
                ],
                if (opportunity.status == OpportunityStatus.open ||
                    opportunity.status ==
                        OpportunityStatus.applicationsClosed ||
                    opportunity.status == OpportunityStatus.booking ||
                    opportunity.status == OpportunityStatus.confirmed) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${opportunity.slots.where((slot) => slot.bandId != null).length}/'
                    '${opportunity.slots.length} slots booked',
                    style: textTheme.epCaption,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    StatusPill(
                      label: opportunityStatusLabel(opportunity.status),
                      tone: opportunityStatusTone(opportunity.status),
                    ),
                    if (venueApproval != null)
                      StatusPill(
                        key: Key('org-opp-venue-consent-${opportunity.id}'),
                        label: venueApproval.label,
                        tone: venueApproval.tone,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'More actions for ${opportunity.title}',
            onPressed: onActions,
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
    );
  }
}

({String label, EpStatusPillTone tone})? _venueApprovalStatus(
  VenueConsentStatus? status,
) => switch (status) {
  VenueConsentStatus.pending => (
    label: 'Pending approval',
    tone: EpStatusPillTone.warning,
  ),
  VenueConsentStatus.granted => (
    label: 'Approved',
    tone: EpStatusPillTone.success,
  ),
  VenueConsentStatus.declined => (
    label: 'Declined',
    tone: EpStatusPillTone.warning,
  ),
  VenueConsentStatus.withdrawn => (
    label: 'Withdrawn',
    tone: EpStatusPillTone.neutral,
  ),
  VenueConsentStatus.revoked => (
    label: 'Revoked',
    tone: EpStatusPillTone.warning,
  ),
  null || VenueConsentStatus.unknown => null,
};

enum _OpportunityAction { duplicate, close, reopen, cancel, delete }

Gig? _publishedGig(AppState app, Opportunity opportunity) =>
    app.allGigs.where((gig) => gig.opportunityId == opportunity.id).firstOrNull;

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('KEEP'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(title.replaceAll('?', '')),
          ),
        ],
      ),
    ) ??
    false;
