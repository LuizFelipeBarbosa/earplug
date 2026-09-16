import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_gig_buckets.dart';
import '../models.dart';
import '../theme.dart';
import 'band_next_up_card.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_text.dart';
import 'form_bits.dart' show EmptyNote;

class BandMyGigsTab extends StatefulWidget {
  const BandMyGigsTab({super.key, required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  State<BandMyGigsTab> createState() => _BandMyGigsTabState();
}

class _BandMyGigsTabState extends State<BandMyGigsTab> {
  bool _pastExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      app.ensureManagedGigs();
      unawaited(app.refreshBandBookings());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final buckets = BandGigBuckets.from(
      bookings: app.bandBookings,
      projects: app.managedGigProjects,
      ledger: app.myBand?.past ?? const [],
      now: DateTime.now(),
    );
    final loadingEmpty =
        (app.bandBookingsStatus == DataStatus.connecting ||
            app.managedGigsLoading) &&
        buckets.nextUp == null &&
        buckets.upcoming.isEmpty &&
        buckets.hosting.isEmpty &&
        buckets.drafts.isEmpty &&
        buckets.past.isEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          app.refreshBandBookings(),
          app.refreshManagedGigs(),
        ]);
      },
      child: ListView(
        key: const PageStorageKey('band-my-gigs'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          EpLayout.gutter,
          16,
          EpLayout.gutter,
          tabBarClearance,
        ),
        children: [
          BandNextUpCard(bandId: app.bandId),
          const SizedBox(height: 28),
          const EpSectionHeader(label: 'NEXT BOOKING'),
          if (buckets.nextUp case final booking?)
            _NextBookingCard(booking: booking)
          else if (loadingEmpty)
            const EpMonoText('LOADING…')
          else
            Column(
              key: const Key('my-gigs-empty-next'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EmptyNote(
                  message: 'No gigs coming up — find your next stage',
                ),
                const SizedBox(height: 12),
                EpPill(
                  key: const Key('my-gigs-empty-discover'),
                  label: 'Discover',
                  onPressed: widget.onDiscover,
                ),
              ],
            ),
          if (buckets.upcoming.isNotEmpty) ...[
            EpSectionHeader(label: 'UPCOMING · ${buckets.upcoming.length}'),
            for (final booking in buckets.upcoming)
              _bookingRow(context, app, booking, label: 'BOOKED'),
          ],
          if (buckets.hosting.isNotEmpty) ...[
            EpSectionHeader(label: 'HOSTING · ${buckets.hosting.length}'),
            for (final project in buckets.hosting)
              _projectRow(context, app, project),
          ],
          if (buckets.drafts.isNotEmpty) ...[
            EpSectionHeader(label: 'DRAFTS · ${buckets.drafts.length}'),
            for (final project in buckets.drafts)
              EpEntityRow(
                key: Key('my-gigs-draft-${project.id}'),
                title: _projectTitle(project, fallback: 'Untitled draft'),
                sub: _draftMissing(project),
                trailing: _statusTrailing(
                  context,
                  'DRAFT',
                  EpStatusPillTone.neutral,
                  canOpen: app.isAdminOf(project.bandId),
                ),
                onTap: app.isAdminOf(project.bandId)
                    ? () => app.editGigProject(project.id)
                    : null,
              ),
          ],
          if (!loadingEmpty) ...[
            const SizedBox(height: 24),
            EpEntityRow(
              key: const Key('my-gigs-past-toggle'),
              title: 'PAST · ${buckets.past.length}',
              sub: buckets.cancelledCount > 0
                  ? 'Incl. ${buckets.cancelledCount} cancelled'
                  : null,
              trailing: Icon(
                _pastExpanded ? Icons.expand_less : Icons.expand_more,
                color: context.epColors.contentSecondary,
              ),
              onTap: () => setState(() => _pastExpanded = !_pastExpanded),
            ),
            if (_pastExpanded)
              Column(
                key: const Key('my-gigs-past-body'),
                children: [
                  for (final entry in buckets.past)
                    switch (entry) {
                      BandPastBooking(:final booking, :final cancelled) =>
                        _bookingRow(
                          context,
                          app,
                          booking,
                          label: cancelled ? 'CANCELLED' : 'DONE',
                          tone: EpStatusPillTone.neutral,
                        ),
                      BandPastProject(:final project) => _projectRow(
                        context,
                        app,
                        project,
                      ),
                      BandPastLedger(:final pastGig) => EpEntityRow(
                        title: pastGig.title,
                        sub: pastGig.meta,
                      ),
                    },
                ],
              ),
          ],
          if (app.isAdminOf(app.bandId)) ...[
            const SizedBox(height: 28),
            const EpEyebrow('Manage'),
            const SizedBox(height: 4),
            EpMenuRow(
              key: const Key('band-dash-payouts'),
              icon: Icons.confirmation_number_outlined,
              label: 'Payouts',
              trailing: _payoutsNeedSetup(app.bandPayoutStatus)
                  ? const StatusPill(
                      key: Key('band-dash-payouts-badge'),
                      label: 'Set up',
                      tone: EpStatusPillTone.attention,
                    )
                  : null,
              onTap: () => app.resetTo(Screen.bandPayouts),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stripe onboarding is not finished until the account is enabled.
bool _payoutsNeedSetup(StripeAccountStatus? status) => switch (status?.state) {
  StripeAccountState.enabled => false,
  _ => true,
};

class _NextBookingCard extends StatelessWidget {
  const _NextBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final location = [
      if (booking.privateEvent) 'Private event' else booking.venue?.name,
      booking.privateEvent
          ? booking.privateLocation?.area
          : booking.venue?.approxLabel,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' · ');
    final details = [
      _slotRoleLabel(booking.slotRole),
      TimeOfDay.fromDateTime(booking.startsAt.toLocal()).format(context),
      booking.fee.artistNet.label,
    ].where((part) => part.trim().isNotEmpty).join(' · ');

    return EpCard(
      key: const Key('my-gigs-next-up'),
      radius: 0,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpDateBlock(date: booking.startsAt),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EpDisplay(
                  booking.opportunityTitle,
                  size: 24,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  EpMonoText(
                    location,
                    color: context.epColors.contentSecondary,
                  ),
                ],
                const SizedBox(height: 8),
                EpMonoText(details, color: context.epColors.contentSecondary),
                const SizedBox(height: 12),
                const StatusPill(
                  label: 'CONFIRMED',
                  tone: EpStatusPillTone.success,
                ),
                const SizedBox(height: 12),
                EpPill(
                  key: const Key('my-gigs-next-up-view'),
                  label: 'View booking',
                  variant: EpPillVariant.outline,
                  size: EpPillSize.chip,
                  onPressed: () => context.read<AppState>().openBooking(
                    booking.id,
                    viewAs: BookingSide.artist,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _bookingRow(
  BuildContext context,
  AppState app,
  Booking booking, {
  required String label,
  EpStatusPillTone tone = EpStatusPillTone.success,
}) => EpGigRow(
  key: Key('band-booking-${booking.id}'),
  date: booking.startsAt,
  title: booking.opportunityTitle,
  meta: booking.privateEvent ? 'Private event' : booking.venue?.name,
  trailing: _statusTrailing(context, label, tone),
  onTap: () => app.openBooking(booking.id, viewAs: BookingSide.artist),
);

Widget _projectRow(BuildContext context, AppState app, GigProject project) {
  final cancelled = project.status == GigProjectStatus.cancelled;
  final label = cancelled
      ? 'CANCELLED'
      : project.hasUnpublishedChanges
      ? 'UNPUBLISHED CHANGES'
      : 'PUBLISHED';
  final tone = cancelled
      ? EpStatusPillTone.neutral
      : project.hasUnpublishedChanges
      ? EpStatusPillTone.warning
      : EpStatusPillTone.success;
  final venue = project.venueId == null
      ? null
      : app.venue(project.venueId!).name;
  final trailing = _statusTrailing(context, label, tone);
  final date = project.startsAt;

  if (date == null) {
    return EpEntityRow(
      key: Key('my-gigs-hosted-${project.id}'),
      title: _projectTitle(project),
      sub: [?venue, 'Date TBD'].join(' · '),
      trailing: trailing,
      onTap: () => app.openHostedGig(project.id),
    );
  }
  return EpGigRow(
    key: Key('my-gigs-hosted-${project.id}'),
    date: date,
    title: _projectTitle(project),
    meta: venue,
    trailing: trailing,
    onTap: () => app.openHostedGig(project.id),
  );
}

Widget _statusTrailing(
  BuildContext context,
  String label,
  EpStatusPillTone tone, {
  bool canOpen = true,
}) => ConstrainedBox(
  // Long status labels wrap so the date and title retain space on phones.
  constraints: const BoxConstraints(maxWidth: 160),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: StatusPill(label: label, tone: tone),
      ),
      if (canOpen) ...[
        const SizedBox(width: 4),
        Icon(
          Icons.chevron_right,
          size: 16,
          color: context.epColors.contentSecondary,
        ),
      ],
    ],
  ),
);

String _slotRoleLabel(SlotRole role) => switch (role) {
  SlotRole.headliner => 'Headliner',
  SlotRole.support => 'Support',
  SlotRole.opener => 'Opener',
};

String _projectTitle(GigProject project, {String fallback = 'Untitled gig'}) {
  final title = project.title?.trim();
  return title == null || title.isEmpty ? fallback : title;
}

String _draftMissing(GigProject project) {
  final missing = <String>[
    if (project.title?.trim().isNotEmpty != true) 'name',
    if (project.startsAt == null || project.doorsAt == null) 'date and times',
    if (project.venueId == null) 'venue',
    if (project.performers.isEmpty) 'lineup',
  ];
  return missing.isEmpty
      ? 'review before publishing'
      : 'finish ${missing.join(', ')}';
}
