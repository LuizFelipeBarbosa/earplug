import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/opportunity_labels.dart';
import '../widgets/send_offer_sheet.dart';

class OpportunityApplicantsScreen extends StatefulWidget {
  const OpportunityApplicantsScreen({super.key, required this.opportunityId});

  final String opportunityId;

  @override
  State<OpportunityApplicantsScreen> createState() =>
      _OpportunityApplicantsScreenState();
}

class _OpportunityApplicantsScreenState
    extends State<OpportunityApplicantsScreen> {
  Opportunity? _opportunity;
  List<ApplicantRow> _applicants = const [];
  String? _selectedSlotId;
  bool _loading = true;
  bool _loadFailed = false;
  bool _reviewing = false;
  Object? _loadToken;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant OpportunityApplicantsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opportunityId == widget.opportunityId) return;
    _opportunity = null;
    _applicants = const [];
    _selectedSlotId = null;
    _reviewing = false;
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    final app = context.read<AppState>();
    unawaited(app.refreshOrganizationBookings());
    final token = Object();
    _loadToken = token;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final (opportunity, applicants) = await (
        app.loadOpportunity(widget.opportunityId, refresh: refresh),
        app.repository.applicantsFor(widget.opportunityId),
      ).wait;
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _opportunity = opportunity;
        _applicants = applicants;
        _loading = false;
        _loadFailed = opportunity == null;
        if (opportunity != null &&
            !opportunity.slots.any((slot) => slot.id == _selectedSlotId)) {
          _selectedSlotId = null;
        }
      });
    } catch (error) {
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _review(
    ApplicantRow row,
    ArtistApplicationReviewAction action,
  ) async {
    final app = context.read<AppState>();
    if (_reviewing || !app.canManageOrganization(app.organizationId)) return;
    final opportunityId = widget.opportunityId;
    setState(() => _reviewing = true);
    try {
      if (action == ArtistApplicationReviewAction.declined) {
        final confirmed = await _confirm(
          context,
          'Decline this applicant?',
          'The application will be declined and removed from the active applicant count.',
        );
        if (!confirmed || !mounted) return;
      }
      if (widget.opportunityId != opportunityId) return;
      await app.repository.reviewApplication(
        applicationId: row.application.id,
        action: action,
      );
      if (!mounted || widget.opportunityId != opportunityId) return;
      await _load(refresh: true);
    } catch (error) {
      if (mounted) {
        app.say('Could not update that application. Please retry.');
      }
      return;
    } finally {
      if (mounted && widget.opportunityId == opportunityId) {
        setState(() => _reviewing = false);
      }
    }
  }

  Future<void> _sendOffer(ApplicantRow row, OpportunitySlot slot) async {
    if (_reviewing) return;
    final opportunityId = widget.opportunityId;
    final bookingId = await showSendOfferSheet(context, row: row, slot: slot);
    if (bookingId == null ||
        !mounted ||
        widget.opportunityId != opportunityId) {
      return;
    }
    context.read<AppState>().say('Offer sent');
    await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final opportunity = _opportunity;
    final slots = [...?opportunity?.slots]
      ..sort((a, b) => a.order.compareTo(b.order));
    final applicants = _applicants
        .where(
          (row) =>
              _selectedSlotId == null ||
              row.application.slotId == _selectedSlotId,
        )
        .toList();
    final canManage = app.canManageOrganization(app.organizationId);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        if (opportunity != null) ...[
          Text(
            opportunity.title,
            style: Theme.of(context).textTheme.epPageHeading,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label: opportunityStatusLabel(opportunity.status),
                tone: opportunityStatusTone(opportunity.status),
              ),
              Text(
                '${opportunity.applicationCount} applicants',
                style: Theme.of(context).textTheme.epCaption,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              EpChip(
                key: const Key('applicants-slot-all'),
                label: 'ALL',
                active: _selectedSlotId == null,
                onTap: () => setState(() => _selectedSlotId = null),
              ),
              for (final slot in slots)
                EpChip(
                  key: ValueKey('applicants-slot-${slot.id}'),
                  label: slotRoleLabel(slot.role),
                  active: _selectedSlotId == slot.id,
                  onTap: () => setState(() => _selectedSlotId = slot.id),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadFailed)
          Column(
            children: [
              const Text('Could not load applicants. Please retry.'),
              TextButton(
                onPressed: () => unawaited(_load(refresh: true)),
                child: const Text('RETRY'),
              ),
            ],
          )
        else if (applicants.isEmpty)
          DashedBox(
            child: Text(
              _selectedSlotId == null
                  ? 'No applicants yet.'
                  : 'No applicants for this slot yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.epCaption,
            ),
          )
        else if (opportunity != null)
          for (final row in applicants) ...[
            _ApplicantCard(
              row: row,
              opportunity: opportunity,
              canManage: canManage,
              reviewing: _reviewing,
              onReview: (action) => unawaited(_review(row, action)),
              onSendOffer: (slot) => unawaited(_sendOffer(row, slot)),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({
    required this.row,
    required this.opportunity,
    required this.canManage,
    required this.reviewing,
    required this.onReview,
    required this.onSendOffer,
  });

  final ApplicantRow row;
  final Opportunity opportunity;
  final bool canManage;
  final bool reviewing;
  final ValueChanged<ArtistApplicationReviewAction> onReview;
  final ValueChanged<OpportunitySlot> onSendOffer;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final application = row.application;
    final slot = opportunity.slots.firstWhere(
      (slot) => slot.id == application.slotId,
    );
    final guarantee = Money(slot.guaranteeMinor, opportunity.currency).label;
    final textTheme = Theme.of(context).textTheme;
    final booking = app.organizationBookings
        .where((booking) => booking.applicationId == application.id)
        .firstOrNull;

    return EpCard(
      key: ValueKey('applicant-${application.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BandAvatar(row.band),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => app.openBand(row.band.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          row.band.name,
                          style: textTheme.epSectionHeading,
                        ),
                      ),
                    ),
                    Text(row.band.genreLine, style: textTheme.epMeta),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            application.askMinor == null
                ? 'Slot $guarantee'
                : 'Asks ${Money(application.askMinor!, opportunity.currency).label} · slot $guarantee',
            style: textTheme.epMeta,
          ),
          if (application.availabilityNote != null) ...[
            const SizedBox(height: 8),
            Text(application.availabilityNote!, style: textTheme.epCaption),
          ],
          const SizedBox(height: 8),
          Text(application.message, style: textTheme.epBody),
          const SizedBox(height: 10),
          StatusPill(
            label: applicationStatusLabel(application.status),
            tone: applicationStatusTone(application.status),
          ),
          if (row.contactEmail != null) ...[
            const SizedBox(height: 8),
            Text(row.contactEmail!, style: textTheme.epCaption),
          ],
          if (canManage &&
              (application.status.isActive ||
                  application.status == ArtistApplicationStatus.booked)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (application.status == ArtistApplicationStatus.submitted)
                  TextButton(
                    key: ValueKey('applicant-${application.id}-review'),
                    onPressed: reviewing
                        ? null
                        : () => onReview(
                            ArtistApplicationReviewAction.underReview,
                          ),
                    child: const Text('START REVIEW'),
                  ),
                if (application.status == ArtistApplicationStatus.submitted ||
                    application.status == ArtistApplicationStatus.underReview)
                  TextButton(
                    key: ValueKey('applicant-${application.id}-shortlist'),
                    onPressed: reviewing
                        ? null
                        : () => onReview(
                            ArtistApplicationReviewAction.shortlisted,
                          ),
                    child: const Text('SHORTLIST'),
                  ),
                if (application.status == ArtistApplicationStatus.shortlisted)
                  FilledButton(
                    key: ValueKey('applicant-${application.id}-offer'),
                    onPressed: reviewing ? null : () => onSendOffer(slot),
                    child: const Text('SEND OFFER'),
                  ),
                if (application.status.isActive &&
                    application.status != ArtistApplicationStatus.offered)
                  TextButton(
                    key: ValueKey('applicant-${application.id}-decline'),
                    onPressed: reviewing
                        ? null
                        : () =>
                              onReview(ArtistApplicationReviewAction.declined),
                    child: const Text('DECLINE'),
                  ),
                if ((application.status == ArtistApplicationStatus.offered ||
                        application.status == ArtistApplicationStatus.booked) &&
                    booking != null)
                  TextButton(
                    key: ValueKey('applicant-${application.id}-booking'),
                    onPressed: () => app.openBooking(
                      booking.id,
                      viewAs: BookingSide.organizer,
                    ),
                    child: const Text('VIEW BOOKING'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

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
