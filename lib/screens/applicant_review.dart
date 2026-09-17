import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/opportunity_labels.dart';
import '../widgets/send_offer_sheet.dart';
import 'band_profile.dart';

/// One application, reviewed against the applicant's full band page with the
/// decision row pinned underneath.
class ApplicantReviewScreen extends StatefulWidget {
  const ApplicantReviewScreen({super.key, required this.applicationId});

  final String applicationId;

  @override
  State<ApplicantReviewScreen> createState() => _ApplicantReviewScreenState();
}

class _ApplicantReviewScreenState extends State<ApplicantReviewScreen> {
  ApplicantRow? _row;
  Opportunity? _opportunity;
  bool _loading = true;
  bool _busy = false;
  Object? _loadToken;
  final _barKey = GlobalKey();
  double _barHeight = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ApplicantReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.applicationId == widget.applicationId) return;
    _row = null;
    _opportunity = null;
    _busy = false;
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    final app = context.read<AppState>();
    unawaited(app.refreshOrganizationBookings());
    final token = Object();
    _loadToken = token;
    setState(() => _loading = true);
    try {
      final opportunityId =
          _opportunity?.id ??
          await _findOpportunityId(app, widget.applicationId);
      if (!mounted || !identical(_loadToken, token)) return;
      final (opportunity, applicants) = opportunityId == null
          ? (null, const <ApplicantRow>[])
          : await (
              app.loadOpportunity(opportunityId, refresh: refresh),
              app.repository.applicantsFor(opportunityId),
            ).wait;
      if (!mounted || !identical(_loadToken, token)) return;
      final row = applicants
          .where((row) => row.application.id == widget.applicationId)
          .firstOrNull;
      // The applicant's band is usually only a feed summary, or not cached at
      // all; the band page needs the full band before it can render.
      if (row != null) await app.ensurePublicBand(row.application.bandId);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _opportunity = opportunity;
        _row = row;
        _loading = false;
      });
      if (row != null &&
          (row.application.status == ArtistApplicationStatus.submitted ||
              row.application.status == ArtistApplicationStatus.underReview)) {
        unawaited(app.markApplicationsViewed([row.application.id]));
      }
    } catch (error) {
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() => _loading = false);
    }
  }

  /// The profile's trailing spacer follows the bar's real height, so its last
  /// section always scrolls clear of the bar; measured once the bar has laid
  /// out and refreshed whenever its content changes.
  void _measureBar() {
    final height = _barKey.currentContext?.size?.height;
    if (!mounted || height == null || height == _barHeight) return;
    setState(() => _barHeight = height);
  }

  /// The route carries only the application id; the application lives on one
  /// of the organization's opportunities.
  static Future<String?> _findOpportunityId(
    AppState app,
    String applicationId,
  ) async {
    final organizationId = app.organizationId;
    var opportunities = app.opportunitiesFor(organizationId);
    if (opportunities.isEmpty) {
      await app.refreshOpportunities(organizationId);
      opportunities = app.opportunitiesFor(organizationId);
    }
    final applicantLists = await Future.wait([
      for (final opportunity in opportunities)
        app.repository.applicantsFor(opportunity.id),
    ]);
    for (final (index, rows) in applicantLists.indexed) {
      if (rows.any((row) => row.application.id == applicationId)) {
        return opportunities[index].id;
      }
    }
    return null;
  }

  Future<void> _review(ArtistApplicationReviewAction action) async {
    final app = context.read<AppState>();
    final row = _row;
    if (_busy ||
        row == null ||
        !app.canManageOrganization(app.organizationId)) {
      return;
    }
    final applicationId = widget.applicationId;
    setState(() => _busy = true);
    try {
      if (action == ArtistApplicationReviewAction.declined) {
        final confirmed = await epConfirm(
          context,
          title: 'Decline this applicant?',
          body:
              'The application will be declined and removed from the active applicant count.',
        );
        if (!confirmed || !mounted) return;
      }
      if (widget.applicationId != applicationId) return;
      await app.repository.reviewApplication(
        applicationId: row.application.id,
        action: action,
      );
      if (!mounted || widget.applicationId != applicationId) return;
      if (action == ArtistApplicationReviewAction.declined) {
        app.back();
        return;
      }
      await _load(refresh: true);
    } catch (error) {
      if (mounted) app.say('Could not update that application. Please retry.');
    } finally {
      if (mounted && widget.applicationId == applicationId) {
        setState(() => _busy = false);
      }
    }
  }

  /// BOOK is today's send-offer; an offer needs a shortlisted application, so
  /// a fresh applicant is shortlisted on the way into the sheet.
  Future<void> _book() async {
    final app = context.read<AppState>();
    final row = _row;
    final opportunity = _opportunity;
    if (_busy ||
        row == null ||
        opportunity == null ||
        !app.canManageOrganization(app.organizationId)) {
      return;
    }
    final applicationId = widget.applicationId;
    final slot = opportunity.slots.firstWhere(
      (slot) => slot.id == row.application.slotId,
    );
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
      if (!mounted || widget.applicationId != applicationId) return;
    }
    final bookingId = await showSendOfferSheet(context, row: row, slot: slot);
    if (!mounted || widget.applicationId != applicationId) return;
    if (bookingId == null) {
      await _load(refresh: true);
      return;
    }
    app.say('Offer sent');
    app.back();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final row = _row;
    final opportunity = _opportunity;
    final band = row == null ? null : app.band(row.application.bandId);
    final showBar = row != null && opportunity != null;
    if (showBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureBar());
    }

    final Widget body;
    if (row != null && opportunity != null && band != null) {
      body = BandProfileView(
        key: ValueKey(band.id),
        bandId: band.id,
        showHeaderBar: false,
        bottomPadding: _barHeight + 24,
      );
    } else if (row != null && app.publicBandMissing(row.application.bandId)) {
      body = const Center(child: EpEyebrow('Band not found'));
    } else if (_loading || (row != null && band == null)) {
      body = const Center(child: EpEyebrow('Loading…'));
    } else {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EpEyebrow('Could not load this application.'),
            const SizedBox(height: 16),
            EpPill(
              key: const Key('applicant-review-retry'),
              label: 'Retry',
              onPressed: () => unawaited(_load(refresh: true)),
            ),
          ],
        ),
      );
    }

    final topPad = headerTopPad(context);
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          top: topPad,
          left: EpLayout.gutter,
          child: EpIconPill(
            key: const Key('applicant-review-back'),
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: app.back,
          ),
        ),
        if (row != null)
          Positioned(
            top: topPad + 8,
            right: EpLayout.gutter,
            child: EpBadge(
              key: const Key('applicant-review-status'),
              label: applicationStatusLabel(row.application.status),
              tone: applicationStatusTone(row.application.status),
            ),
          ),
        // Last in the stack so it sits over the profile's scroll content and
        // takes the taps; the CTA's own SafeArea keeps the buttons above the
        // home indicator while its background runs to the viewport edge.
        if (showBar)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DecisionBar(
              key: _barKey,
              row: row,
              opportunity: opportunity,
              booking: app.organizationBookings
                  .where(
                    (booking) => booking.applicationId == row.application.id,
                  )
                  .firstOrNull,
              canManage: app.canManageOrganization(app.organizationId),
              busy: _busy,
              onDecline: () =>
                  unawaited(_review(ArtistApplicationReviewAction.declined)),
              onShortlist: () =>
                  unawaited(_review(ArtistApplicationReviewAction.shortlisted)),
              onBook: () => unawaited(_book()),
            ),
          ),
      ],
    );
  }
}

class _DecisionBar extends StatelessWidget {
  const _DecisionBar({
    super.key,
    required this.row,
    required this.opportunity,
    required this.booking,
    required this.canManage,
    required this.busy,
    required this.onDecline,
    required this.onShortlist,
    required this.onBook,
  });

  final ApplicantRow row;
  final Opportunity opportunity;
  final Booking? booking;
  final bool canManage;
  final bool busy;
  final VoidCallback onDecline;
  final VoidCallback onShortlist;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final application = row.application;
    final status = application.status;
    final slot = opportunity.slots.firstWhere(
      (slot) => slot.id == application.slotId,
    );
    final fee = Money(
      application.askMinor ?? slot.guaranteeMinor,
      opportunity.currency,
    );
    final hint =
        '${row.band.name} · ${slotRoleLabel(slot.role)} · ${fee.label}';
    final message = application.message.trim();
    final decided = !status.isActive;
    final colors = context.epColors;

    return EpBottomCta(
      key: const Key('applicant-review-actions'),
      hint: hint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isNotEmpty) ...[
            EpMonoText(
              message,
              key: const Key('applicant-review-message'),
              keepCase: true,
              color: colors.muted,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
          ],
          if (!canManage || decided)
            Center(
              child: EpBadge(
                label: applicationStatusLabel(status),
                tone: applicationStatusTone(status),
              ),
            )
          else
            Row(
              children: [
                if (status != ArtistApplicationStatus.offered) ...[
                  Expanded(
                    child: _DestructiveOutline(
                      child: EpPill(
                        key: const Key('applicant-review-decline'),
                        label: 'Decline',
                        variant: EpPillVariant.outline,
                        size: EpPillSize.chip,
                        expand: true,
                        onPressed: busy ? null : onDecline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (status == ArtistApplicationStatus.shortlisted ||
                    status == ArtistApplicationStatus.offered)
                  const Expanded(
                    child: Center(
                      child: EpBadge(
                        key: Key('applicant-review-shortlisted'),
                        label: 'Shortlisted',
                        tone: EpBadgeTone.success,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: EpPill(
                      key: const Key('applicant-review-shortlist'),
                      label: 'Shortlist',
                      variant: EpPillVariant.outline,
                      size: EpPillSize.chip,
                      expand: true,
                      onPressed: busy ? null : onShortlist,
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: booking != null
                      ? EpPill(
                          key: const Key('applicant-review-booking'),
                          label: 'View booking',
                          variant: EpPillVariant.primary,
                          size: EpPillSize.chip,
                          expand: true,
                          onPressed: () => app.openBooking(
                            booking!.id,
                            viewAs: BookingSide.organizer,
                          ),
                        )
                      : EpPill(
                          key: const Key('applicant-review-book'),
                          label: 'Book',
                          variant: EpPillVariant.primary,
                          size: EpPillSize.chip,
                          expand: true,
                          onPressed: busy ? null : onBook,
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// An outline pill whose label reads in the destructive colour.
class _DestructiveOutline extends StatelessWidget {
  const _DestructiveOutline({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<EpPalette>()!;
    return Theme(
      data: theme.copyWith(
        extensions: [palette.copyWith(contentPrimary: palette.destructive)],
      ),
      child: child,
    );
  }
}
