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

class OrgOpportunitiesScreen extends StatefulWidget {
  const OrgOpportunitiesScreen({super.key});

  @override
  State<OrgOpportunitiesScreen> createState() => _OrgOpportunitiesScreenState();
}

class _OrgOpportunitiesScreenState extends State<OrgOpportunitiesScreen> {
  String? _loadedOrganizationId;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  'OPPORTUNITIES',
                  style: Theme.of(context).textTheme.epPageHeading,
                ),
              ),
              if (app.canManageOrganization(app.organizationId)) ...[
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('org-opps-new'),
                  onPressed: app.openOpportunityEditor,
                  child: const Text('NEW OPPORTUNITY'),
                ),
              ],
            ],
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
    unawaited(
      showEpActionSheet(
        context,
        header: opportunity.title,
        items: [
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
  const _OpportunityCard({required this.opportunity, required this.onActions});

  final Opportunity opportunity;
  final VoidCallback onActions;

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
                  '${opportunity.venue?.name ?? 'Venue TBD'} · '
                  '${opportunity.venue?.area ?? opportunity.area}',
                  style: textTheme.epMeta,
                ),
                const SizedBox(height: 4),
                Text(slotSummary, style: textTheme.epMeta),
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
                const SizedBox(height: 8),
                StatusPill(
                  label: opportunityStatusLabel(opportunity.status),
                  tone: opportunityStatusTone(opportunity.status),
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

enum _OpportunityAction { duplicate, close, reopen, cancel, delete }

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
            child: Text('CONFIRM'),
          ),
        ],
      ),
    ) ??
    false;
