import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../application_tracker.dart';
import '../band_application_groups.dart';
import '../date_names.dart';
import '../models.dart';
import '../theme.dart';
import 'application_tracker_bar.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_sheet.dart';
import 'ep_text.dart';
import 'form_bits.dart';

class BandApplicationsTab extends StatefulWidget {
  const BandApplicationsTab({super.key});

  @override
  State<BandApplicationsTab> createState() => _BandApplicationsTabState();
}

class _BandApplicationsTabState extends State<BandApplicationsTab> {
  final Set<String> _withdrawing = {};

  Future<void> _withdraw(AppState app, ArtistApplication application) async {
    if (!_withdrawing.add(application.id)) return;
    setState(() {});
    try {
      if (!await epConfirm(
        context,
        title: 'Withdraw application?',
        body: 'Your band will no longer be considered for this opportunity.',
      )) {
        return;
      }
      await app.repository.withdrawApplication(application.id);
      await app.refreshMyApplications();
      await app.refreshBrowse();
    } catch (error) {
      app.say(error is StateError ? error.message : '$error');
    } finally {
      if (mounted) setState(() => _withdrawing.remove(application.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final groups = BandApplicationGroups.from(app.myApplications);
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: app.refreshMyApplications,
      child: ListView(
        key: const PageStorageKey('band-applications'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          EpLayout.gutter,
          16,
          EpLayout.gutter,
          tabBarClearance,
        ),
        children: [
          _ApplicationsSummary(groups: groups),
          const EpHairline(),
          EpSectionHeader(label: 'IN PROGRESS · ${groups.inProgress.length}'),
          const SizedBox(height: 12),
          if (groups.inProgress.isEmpty)
            const EmptyNote(message: 'Your applications will appear here.'),
          for (final row in groups.inProgress) ...[
            _ApplicationCard(
              row: row,
              app: app,
              now: now,
              onWithdraw: _withdrawing.contains(row.application.id)
                  ? null
                  : () => _withdraw(app, row.application),
            ),
            const SizedBox(height: 12),
          ],
          if (groups.decided.isNotEmpty) ...[
            EpSectionHeader(label: 'DECIDED · ${groups.decided.length}'),
            const SizedBox(height: 12),
            for (final row in groups.decided) ...[
              _ApplicationCard(row: row, app: app, now: now),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 24),
          EpMonoText(
            'Accepted applications move to MY GIGS automatically.',
            key: const Key('applications-footer-hint'),
            color: context.epColors.contentSecondary,
            keepCase: true,
          ),
        ],
      ),
    );
  }
}

class _ApplicationsSummary extends StatelessWidget {
  const _ApplicationsSummary({required this.groups});

  final BandApplicationGroups groups;

  @override
  Widget build(BuildContext context) {
    final stats = [
      EpStat('${groups.active}', 'ACTIVE'),
      EpStat('${groups.shortlisted}', 'SHORTLISTED'),
      EpStat('${groups.booked}', 'BOOKED'),
    ];
    // EpStatGrid wraps narrow layouts and has no vertical cell dividers.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: IntrinsicHeight(
        child: Row(
          key: const Key('applications-summary'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < stats.length; index++) ...[
              if (index > 0)
                SizedBox(
                  width: 1,
                  child: ColoredBox(color: context.epColors.border),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: index == 0 ? 0 : 16, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EpDisplay(stats[index].value, size: 32),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: EpEyebrow(stats[index].label),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.row,
    required this.app,
    required this.now,
    this.onWithdraw,
  });

  final BandApplication row;
  final AppState app;
  final DateTime now;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final application = row.application;
    final opportunity = row.opportunity;
    final status = application.status;
    final (label, tone) = switch (status) {
      ArtistApplicationStatus.submitted ||
      ArtistApplicationStatus.underReview => (
        'IN REVIEW',
        EpStatusPillTone.neutral,
      ),
      ArtistApplicationStatus.shortlisted => (
        'SHORTLISTED',
        EpStatusPillTone.success,
      ),
      ArtistApplicationStatus.offered => (
        'OFFER RECEIVED',
        EpStatusPillTone.success,
      ),
      ArtistApplicationStatus.booked => ('BOOKED', EpStatusPillTone.success),
      ArtistApplicationStatus.declined => (
        'DECLINED',
        EpStatusPillTone.neutral,
      ),
      ArtistApplicationStatus.withdrawn => (
        'WITHDRAWN',
        EpStatusPillTone.neutral,
      ),
      ArtistApplicationStatus.expired => ('EXPIRED', EpStatusPillTone.neutral),
    };
    final tracker = ApplicationTracker.of(application);
    final closesAt = opportunity.applicationsCloseAt;
    final closing = closesAt.isAfter(now)
        ? 'applications close ${shortDateLabel(closesAt)}'
        : null;
    final booking = status == ArtistApplicationStatus.offered
        ? app.bandBookings
              .where((b) => b.applicationId == application.id)
              .firstOrNull
        : null;
    final canWithdraw =
        status.isActive && status != ArtistApplicationStatus.offered;
    final venue = opportunity.venue;
    return EpCard(
      key: ValueKey('band-app-${application.id}'),
      onTap: () => app.openOpportunity(opportunity.slug),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpDisplay(opportunity.title, size: 20, maxLines: 2),
          const SizedBox(height: 8),
          EpMonoText(
            [
              if (venue != null) venue.name,
              venue?.neighborhood ?? opportunity.area,
            ].join(' · '),
            color: context.epColors.contentSecondary,
          ),
          const SizedBox(height: 8),
          EpMonoText('APPLIED ${shortDateLabel(application.createdAt)}'),
          const SizedBox(height: 12),
          StatusPill(label: label, tone: tone),
          const SizedBox(height: 20),
          ApplicationTrackerBar(
            key: ValueKey('band-app-${application.id}-tracker'),
            tracker: tracker,
          ),
          if (application.hostNote case final note?) ...[
            const SizedBox(height: 16),
            EpMonoText(
              'Host replied ${_relativeTime(application.hostNoteAt, now)} — $note'
              '${closing == null ? '' : ' · $closing'}',
              key: ValueKey('band-app-${application.id}-note'),
              keepCase: true,
              color: context.epColors.contentSecondary,
            ),
          ] else if (closing != null) ...[
            const SizedBox(height: 16),
            EpMonoText(
              closing,
              keepCase: true,
              color: context.epColors.contentSecondary,
            ),
          ],
          if (tracker.isDecided) ...[
            const SizedBox(height: 16),
            EpMonoText(
              _decisionReason(application),
              key: ValueKey('band-app-${application.id}-reason'),
              keepCase: true,
              color: context.epColors.contentSecondary,
            ),
          ],
          if (booking != null || canWithdraw) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: booking != null
                    ? EpPill(
                        key: ValueKey('band-app-${application.id}-respond'),
                        label: 'Respond',
                        variant: EpPillVariant.primary,
                        size: EpPillSize.chip,
                        onPressed: () => app.openBooking(
                          booking.id,
                          viewAs: BookingSide.artist,
                        ),
                      )
                    : EpPill(
                        key: ValueKey('band-app-${application.id}-withdraw'),
                        label: 'Withdraw',
                        variant: EpPillVariant.outline,
                        size: EpPillSize.chip,
                        onPressed: onWithdraw,
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _relativeTime(DateTime? timestamp, DateTime now) {
  if (timestamp == null) return 'recently';
  final elapsed = now.difference(timestamp);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

String _decisionReason(ArtistApplication application) {
  if (application.status == ArtistApplicationStatus.withdrawn) {
    return 'You withdrew this application';
  }
  if (application.status == ArtistApplicationStatus.expired) {
    return 'Applications closed without a decision';
  }
  final reason = application.declineReason?.label;
  final note = application.declineNote;
  return [
    ?reason,
    if (note != null && note.isNotEmpty) note,
    if (reason == null && (note == null || note.isEmpty))
      'The host passed this time',
  ].join(' — ');
}
