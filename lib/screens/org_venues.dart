import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../host_request_groups.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

class OrgVenuesScreen extends StatefulWidget {
  const OrgVenuesScreen({super.key});

  @override
  State<OrgVenuesScreen> createState() => _OrgVenuesScreenState();
}

class _OrgVenuesScreenState extends State<OrgVenuesScreen> {
  OrganizationDashboard? _dashboard;
  List<VenueConsentRow> _consents = const [];
  Object? _error;
  bool _loading = true;
  String? _loadedOrganizationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    unawaited(app.refreshOpportunities(organizationId));
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await app.repository.organizationDashboard(
        organizationId,
      );
      final consents = await app.repository.venueConsentsForOrganization(
        organizationId,
      );
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _dashboard = dashboard;
        _consents = consents;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Widget _venueRequestCard(AppState app, VenueConsentRow consent) {
    final startsAt = consent.startsAt.toLocal();
    final endsAt = consent.endsAt?.toLocal();
    final message = consent.message?.trim();
    return EpCard(
      key: Key('venue-request-${consent.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            consent.opportunityTitle,
            style: Theme.of(context).textTheme.epSectionHeading,
          ),
          const SizedBox(height: 6),
          Text(consent.requestingOrganizationName),
          const SizedBox(height: 4),
          Text(
            '${dateLabel(startsAt)} · ${timeLabel(TimeOfDay.fromDateTime(startsAt))}'
            '${endsAt == null ? '' : ' – ${dateLabel(endsAt)} · ${timeLabel(TimeOfDay.fromDateTime(endsAt))}'}',
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 4),
          Text(consent.venueName),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: switch (consent.status) {
                VenueConsentStatus.pending => 'PENDING APPROVAL',
                VenueConsentStatus.granted => 'APPROVED',
                VenueConsentStatus.declined => 'DECLINED',
                VenueConsentStatus.withdrawn => 'WITHDRAWN',
                VenueConsentStatus.revoked => 'REVOKED',
                VenueConsentStatus.unknown => 'UNKNOWN',
              },
              tone: switch (consent.status) {
                VenueConsentStatus.granted => EpStatusPillTone.success,
                VenueConsentStatus.pending => EpStatusPillTone.warning,
                _ => EpStatusPillTone.neutral,
              },
            ),
          ),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(message),
          ],
          if (app.canManageOrganization(app.organizationId)) ...[
            if (consent.status == VenueConsentStatus.pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: EpButton(
                      'APPROVE',
                      key: Key('venue-request-approve-${consent.id}'),
                      onTap: () async {
                        final approved = await app.decideVenueApproval(
                          consent.id,
                          granted: true,
                        );
                        if (approved) await _refresh();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: EpButton(
                      'DECLINE',
                      key: Key('venue-request-decline-${consent.id}'),
                      kind: EpButtonKind.outline,
                      onTap: () => _showDecisionSheet(app, consent),
                    ),
                  ),
                ],
              ),
            ] else if (consent.status == VenueConsentStatus.granted) ...[
              const SizedBox(height: 12),
              EpButton(
                'REVOKE',
                key: Key('venue-request-revoke-${consent.id}'),
                kind: EpButtonKind.outline,
                onTap: () => _showDecisionSheet(app, consent),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _showDecisionSheet(AppState app, VenueConsentRow consent) {
    showEpSheet(
      context,
      (_) => _VenueConsentNoteSheet(
        app: app,
        consentId: consent.id,
        revoke: consent.status == VenueConsentStatus.granted,
        onDecided: _refresh,
      ),
    );
  }

  void _onAddVenue() =>
      context.read<AppState>().go(Screen.orgVenueEdit, 'new');

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final venues = _dashboard?.venues ?? const <Venue>[];
    final canManage = app.canManageOrganization(app.organizationId);
    final upcomingByVenue = _upcomingByVenue(
      app.opportunitiesFor(app.organizationId),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        headerTopPad(context),
        EpLayout.gutter,
        tabBarClearance,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: const EpDisplay(
                  'Venues',
                  key: Key('org-venues-title'),
                  size: 44,
                  maxLines: 1,
                ),
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: 12),
              EpPill(
                key: const Key('org-venues-add'),
                label: '+ Add venue',
                variant: EpPillVariant.outline,
                size: EpPillSize.chip,
                onPressed: _onAddVenue,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _LoadError(onRetry: _refresh)
        else ...[
          if (_consents.isNotEmpty) ...[
            const SectionBar(label: 'VENUE REQUESTS'),
            for (final consent in _consents) ...[
              _venueRequestCard(app, consent),
              const SizedBox(height: 12),
            ],
          ],
          if (venues.isEmpty)
            EmptyNote(
              message: 'No venues yet — add one.',
              actionLabel: canManage ? 'Add venue' : null,
              onAction: canManage ? _onAddVenue : null,
            )
          else
            for (final venue in venues) ...[
              _venueCard(
                venue,
                upcoming: upcomingByVenue[venue.id] ?? 0,
                // No default-venue concept exists yet; the first venue in the
                // organization's ordered list stands in for it.
                isDefault: identical(venue, venues.first),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 8),
          EpMonoText(
            'Venues you run. Opportunities pick from this list.',
            key: const Key('org-venues-hint'),
            keepCase: true,
            color: context.epColors.muted,
          ),
        ],
      ],
    );
  }

  Widget _venueCard(
    Venue venue, {
    required int upcoming,
    required bool isDefault,
  }) {
    final secondary = context.epColors.contentSecondary;
    final capacity = venue.capacityPublic;
    return EpCard(
      key: ValueKey('org-venue-${venue.id}'),
      onTap: () => context.read<AppState>().go(Screen.orgVenueEdit, venue.id),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EpDisplay(venue.name, size: 20, maxLines: 2),
                const SizedBox(height: 4),
                EpMonoText(
                  venue.approx.label,
                  keepCase: true,
                  color: secondary,
                ),
                const SizedBox(height: 4),
                EpMonoText(
                  '${capacity == null ? '' : 'CAP $capacity · '}'
                  '$upcoming UPCOMING',
                  color: secondary,
                ),
                if (isDefault || !venue.verified) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      if (isDefault)
                        StatusPill(
                          key: Key('org-venue-default-${venue.id}'),
                          label: 'Default',
                          tone: EpStatusPillTone.selected,
                        ),
                      if (!venue.verified)
                        const StatusPill(
                          label: 'Suspended',
                          tone: EpStatusPillTone.attention,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_right, size: 16, color: context.epColors.muted),
        ],
      ),
    );
  }
}

/// Live, not-yet-started opportunities per venue: open, closed-to-applications,
/// booking, or confirmed. Drafts and anything completed, cancelled, or started
/// before today are left out.
Map<String, int> _upcomingByVenue(List<Opportunity> opportunities) {
  final groups = HostRequestGroups.from(opportunities, now: DateTime.now());
  final counts = <String, int>{};
  for (final opportunity in groups.confirmed.followedBy(groups.active)) {
    if (opportunity.status == OpportunityStatus.draft) continue;
    final venueId = opportunity.venueId;
    if (venueId == null) continue;
    counts[venueId] = (counts[venueId] ?? 0) + 1;
  }
  return counts;
}

class _VenueConsentNoteSheet extends StatefulWidget {
  const _VenueConsentNoteSheet({
    required this.app,
    required this.consentId,
    required this.revoke,
    required this.onDecided,
  });

  final AppState app;
  final String consentId;
  final bool revoke;
  final VoidCallback onDecided;

  @override
  State<_VenueConsentNoteSheet> createState() => _VenueConsentNoteSheetState();
}

class _VenueConsentNoteSheetState extends State<_VenueConsentNoteSheet> {
  final _note = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final note = _note.text.trim();
    final succeeded = widget.revoke
        ? await widget.app.revokeVenueApproval(
            widget.consentId,
            note: note.isEmpty ? null : note,
          )
        : await widget.app.decideVenueApproval(
            widget.consentId,
            granted: false,
            note: note.isEmpty ? null : note,
          );
    if (succeeded) {
      if (mounted) Navigator.pop(context);
      widget.onDecided();
    } else if (mounted) {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EpFormSheet(
      title: widget.revoke ? 'Revoke approval' : 'Decline request',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.revoke) ...[
            const Text(
              'Revoking cancels the event if it is already open. After a confirmed booking, contact EarPlug support.',
            ),
            const SizedBox(height: 14),
          ],
          EpLabeledField(
            label: 'NOTE (OPTIONAL)',
            hint: 'Add a note for the organizer',
            fieldKey: const Key('venue-request-note'),
            controller: _note,
            enabled: !_submitting,
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          EpButton(
            widget.revoke ? 'REVOKE' : 'DECLINE',
            key: const Key('venue-request-note-submit'),
            onTap: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 56),
        const Text('Could not load venues.'),
        const SizedBox(height: 12),
        EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
      ],
    );
  }
}
