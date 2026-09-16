import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/opportunity_labels.dart';
import '../widgets/send_offer_sheet.dart';

/// An organizer's own opportunity: slot fill, applicants with their decisions
/// and the confirmed line-up. Every count comes from the loaded opportunity
/// and its applicant list; nothing is stored separately.
class OrgOpportunityDetailScreen extends StatefulWidget {
  const OrgOpportunityDetailScreen({super.key, required this.opportunityId});

  final String opportunityId;

  @override
  State<OrgOpportunityDetailScreen> createState() =>
      _OrgOpportunityDetailScreenState();
}

class _OrgOpportunityDetailScreenState
    extends State<OrgOpportunityDetailScreen> {
  Opportunity? _opportunity;
  List<ApplicantRow> _applicants = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  Object? _loadToken;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant OrgOpportunityDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opportunityId == widget.opportunityId) return;
    _opportunity = null;
    _applicants = const [];
    _busy = false;
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
      });
      final unreviewedIds = [
        for (final row in applicants)
          if (row.application.status == ArtistApplicationStatus.submitted ||
              row.application.status == ArtistApplicationStatus.underReview)
            row.application.id,
      ];
      if (unreviewedIds.isNotEmpty) {
        unawaited(app.markApplicationsViewed(unreviewedIds));
      }
    } catch (error) {
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _shortlist(ApplicantRow row) async {
    final app = context.read<AppState>();
    if (_busy || !app.canManageOrganization(app.organizationId)) return;
    final opportunityId = widget.opportunityId;
    setState(() => _busy = true);
    try {
      await app.repository.reviewApplication(
        applicationId: row.application.id,
        action: ArtistApplicationReviewAction.shortlisted,
      );
      if (!mounted || widget.opportunityId != opportunityId) return;
      await _load(refresh: true);
    } catch (error) {
      if (mounted) app.say('Could not update that application. Please retry.');
    } finally {
      if (mounted && widget.opportunityId == opportunityId) {
        setState(() => _busy = false);
      }
    }
  }

  /// BOOK is today's send-offer. An offer needs a shortlisted application, so
  /// a fresh applicant is shortlisted on the way into the sheet.
  Future<void> _book(ApplicantRow row, OpportunitySlot slot) async {
    final app = context.read<AppState>();
    if (_busy || !app.canManageOrganization(app.organizationId)) return;
    final opportunityId = widget.opportunityId;
    if (row.application.status != ArtistApplicationStatus.shortlisted) {
      setState(() => _busy = true);
      try {
        await app.repository.reviewApplication(
          applicationId: row.application.id,
          action: ArtistApplicationReviewAction.shortlisted,
        );
      } catch (error) {
        if (mounted) {
          app.say('Could not update that application. Please retry.');
        }
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted || widget.opportunityId != opportunityId) return;
    }
    final bookingId = await showSendOfferSheet(context, row: row, slot: slot);
    if (!mounted || widget.opportunityId != opportunityId) return;
    if (bookingId != null) app.say('Offer sent');
    await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final opportunity = _opportunity;
    final canManage = app.canManageOrganization(app.organizationId);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        headerTopPad(context),
        EpLayout.gutter,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: EpIconPill(
            key: const Key('org-opportunity-back'),
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: app.back,
          ),
        ),
        const SizedBox(height: 28),
        if (opportunity != null) ...[
          EpDisplay(opportunity.title, size: 28, maxLines: 3),
          const SizedBox(height: 12),
          _MetaLine(opportunity: opportunity),
          const SizedBox(height: 24),
          _SlotFill(opportunity: opportunity),
          _Applicants(
            opportunity: opportunity,
            applicants: _applicants,
            bookings: app.organizationBookings,
            canManage: canManage,
            busy: _busy,
            onShortlist: (row) => unawaited(_shortlist(row)),
            onBook: (row, slot) => unawaited(_book(row, slot)),
          ),
          _Confirmed(
            opportunity: opportunity,
            applicants: _applicants,
            bookings: app.organizationBookings,
          ),
          const SizedBox(height: 32),
          EpPill(
            key: const Key('org-opportunity-edit'),
            label: 'Edit opportunity',
            variant: EpPillVariant.outline,
            size: EpPillSize.large,
            expand: true,
            onPressed: () => app.openOpportunityEditor(opportunity.id),
          ),
        ] else if (_loading)
          const EpEyebrow('Loading…')
        else if (_loadFailed) ...[
          const EpEyebrow('Could not load this opportunity.'),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: EpPill(
              key: const Key('org-opportunity-retry'),
              label: 'Retry',
              onPressed: () => unawaited(_load(refresh: true)),
            ),
          ),
        ],
      ],
    );
  }
}

/// `FRI OCT 31 · 9:00 PM · THE WAREHOUSE · ACTIVE` with the status in accent.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.opportunity});

  final Opportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final startsAt = opportunity.startsAt.toLocal();
    final place = opportunity.venue?.name ?? opportunity.area;
    final status = opportunity.status == OpportunityStatus.open
        ? 'Active'
        : opportunityStatusLabel(opportunity.status);
    final lead =
        '${dateLabel(startsAt)} · '
        '${TimeOfDay.fromDateTime(startsAt).format(context)} · '
        '$place · ';
    final style = Theme.of(
      context,
    ).textTheme.epChipLabel.copyWith(fontSize: 11, color: context.epColors.ink);
    return Text.rich(
      key: const Key('org-opportunity-meta'),
      TextSpan(
        text: lead.toUpperCase(),
        children: [
          TextSpan(
            text: status.toUpperCase(),
            style: TextStyle(color: context.epColors.accent),
          ),
        ],
      ),
      semanticsLabel: '$lead$status',
      style: style,
    );
  }
}

class _SlotFill extends StatelessWidget {
  const _SlotFill({required this.opportunity});

  final Opportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final slots = opportunity.slots
        .where((slot) => slot.status != SlotStatus.cancelled)
        .toList();
    final booked = slots
        .where((slot) => slot.status == SlotStatus.booked)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EpEyebrow(
          'Slots — $booked of ${slots.length} filled',
          key: const Key('org-opportunity-slots-label'),
        ),
        const SizedBox(height: 10),
        EpReadinessBar(
          key: const Key('org-opportunity-fill-bar'),
          done: booked,
          total: slots.length,
        ),
      ],
    );
  }
}

class _Applicants extends StatelessWidget {
  const _Applicants({
    required this.opportunity,
    required this.applicants,
    required this.bookings,
    required this.canManage,
    required this.busy,
    required this.onShortlist,
    required this.onBook,
  });

  final Opportunity opportunity;
  final List<ApplicantRow> applicants;
  final List<Booking> bookings;
  final bool canManage;
  final bool busy;
  final ValueChanged<ApplicantRow> onShortlist;
  final void Function(ApplicantRow row, OpportunitySlot slot) onBook;

  static const _hidden = {
    ArtistApplicationStatus.booked,
    ArtistApplicationStatus.withdrawn,
    ArtistApplicationStatus.expired,
  };

  @override
  Widget build(BuildContext context) {
    final rows = applicants
        .where((row) => !_hidden.contains(row.application.status))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EpSectionHeader(label: 'Applicants · ${rows.length}'),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: EpMonoText(
              'No applicants yet',
              color: context.epColors.muted,
            ),
          ),
        for (final row in rows)
          _ApplicantRow(
            row: row,
            slot: opportunity.slots.firstWhere(
              (slot) => slot.id == row.application.slotId,
            ),
            currency: opportunity.currency,
            booking: bookings
                .where((booking) => booking.applicationId == row.application.id)
                .firstOrNull,
            canManage: canManage,
            busy: busy,
            onShortlist: () => onShortlist(row),
            onBook: (slot) => onBook(row, slot),
          ),
      ],
    );
  }
}

class _ApplicantRow extends StatelessWidget {
  const _ApplicantRow({
    required this.row,
    required this.slot,
    required this.currency,
    required this.booking,
    required this.canManage,
    required this.busy,
    required this.onShortlist,
    required this.onBook,
  });

  final ApplicantRow row;
  final OpportunitySlot slot;
  final String currency;
  final Booking? booking;
  final bool canManage;
  final bool busy;
  final VoidCallback onShortlist;
  final ValueChanged<OpportunitySlot> onBook;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final application = row.application;
    final id = application.id;
    final status = application.status;
    final declined = status == ArtistApplicationStatus.declined;
    final fee = Money(application.askMinor ?? slot.guaranteeMinor, currency);
    final colors = context.epColors;

    final actions = <Widget>[
      if (status == ArtistApplicationStatus.shortlisted)
        const StatusPill(label: 'Shortlisted', tone: EpStatusPillTone.success),
      if (status == ArtistApplicationStatus.offered)
        const StatusPill(label: 'Offer sent', tone: EpStatusPillTone.selected),
      if (declined) const _DeclinedPill(),
      if (canManage && !declined) ...[
        if (status == ArtistApplicationStatus.submitted ||
            status == ArtistApplicationStatus.underReview)
          EpPill(
            key: ValueKey('applicant-$id-shortlist'),
            label: 'Shortlist',
            onPressed: busy ? null : onShortlist,
          ),
        if (booking != null)
          EpPill(
            key: ValueKey('applicant-$id-booking'),
            label: 'View booking',
            onPressed: () =>
                app.openBooking(booking!.id, viewAs: BookingSide.organizer),
          )
        else if (status != ArtistApplicationStatus.offered)
          EpPill(
            key: ValueKey('applicant-$id-book'),
            label: 'Book',
            variant: EpPillVariant.primary,
            onPressed: busy ? null : () => onBook(slot),
          ),
        EpPill(
          key: ValueKey('applicant-$id-review'),
          label: 'Review',
          variant: EpPillVariant.ghost,
          onPressed: () => app.openApplicantReview(id),
        ),
      ],
    ];

    return Opacity(
      opacity: declined ? .4 : 1,
      child: Column(
        key: ValueKey('applicant-$id'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => app.openBand(row.band.id),
                      child: BandAvatar(row.band),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            key: ValueKey('applicant-$id-profile'),
                            onTap: () => app.openBand(row.band.id),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: EpDisplay(
                                    row.band.name,
                                    size: 20,
                                    maxLines: 2,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: colors.muted,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          EpMonoText(
                            '${row.band.genreLine} · ${fee.label}',
                            color: colors.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
          const EpHairline(),
        ],
      ),
    );
  }
}

/// [StatusPill] has no destructive tone; a declined applicant reads in the
/// destructive colour with the same chrome.
class _DeclinedPill extends StatelessWidget {
  const _DeclinedPill();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Declined',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: context.epColors.line),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          'DECLINED',
          style: Theme.of(
            context,
          ).textTheme.epChipLabel.copyWith(color: context.epColors.destructive),
        ),
      ),
    ),
  );
}

class _Confirmed extends StatelessWidget {
  const _Confirmed({
    required this.opportunity,
    required this.applicants,
    required this.bookings,
  });

  final Opportunity opportunity;
  final List<ApplicantRow> applicants;
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final booked = [
      for (final slot in opportunity.slots)
        if (slot.status == SlotStatus.booked && slot.bandId != null) slot,
    ]..sort((a, b) => a.order.compareTo(b.order));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EpSectionHeader(label: 'Confirmed · ${booked.length}'),
        if (booked.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: EpMonoText(
              'No confirmed acts yet',
              color: context.epColors.muted,
            ),
          ),
        for (final slot in booked)
          Builder(
            builder: (context) {
              final bandId = slot.bandId!;
              final band =
                  applicants
                      .where((row) => row.band.id == bandId)
                      .firstOrNull
                      ?.band ??
                  app.band(bandId);
              final name =
                  band?.name ??
                  bookings
                      .where((booking) => booking.slotId == slot.id)
                      .firstOrNull
                      ?.bandName ??
                  'Band';
              return EpEntityRow(
                key: ValueKey('org-opportunity-confirmed-${slot.id}'),
                leading: band == null
                    ? EpFanAvatar(name: name)
                    : BandAvatar(band),
                title: name,
                sub:
                    '${slotRoleLabel(slot.role)} · '
                    '${Money(slot.guaranteeMinor, opportunity.currency).label}',
                trailing: const StatusPill(
                  label: 'Booked',
                  tone: EpStatusPillTone.success,
                ),
                onTap: () => app.openBand(bandId),
              );
            },
          ),
      ],
    );
  }
}
