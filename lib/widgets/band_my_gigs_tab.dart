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
          const SizedBox(height: 16),
          if (loadingEmpty)
            const EpMonoText('LOADING…')
          else if (buckets.upcoming.isEmpty && buckets.hosting.isEmpty)
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
            _sectionHeader(
              'UPCOMING · ${buckets.upcoming.length}',
              first: true,
            ),
            for (final booking in buckets.upcoming)
              _bookingRow(context, app, booking, label: 'BOOKED'),
          ],
          if (buckets.hosting.isNotEmpty) ...[
            _sectionHeader(
              'HOSTING · ${buckets.hosting.length}',
              first: buckets.upcoming.isEmpty,
            ),
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

/// The first section sits directly under the UP NEXT card, so it drops the
/// header's default top padding; later sections keep it.
Widget _sectionHeader(String label, {bool first = false}) => first
    ? EpSectionHeader(label: label, padding: const EdgeInsets.only(bottom: 4))
    : EpSectionHeader(label: label);

/// Stripe onboarding is not finished until the account is enabled.
bool _payoutsNeedSetup(StripeAccountStatus? status) => switch (status?.state) {
  StripeAccountState.enabled => false,
  _ => true,
};

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
