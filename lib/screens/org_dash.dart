import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/sheets.dart';

class OrgDashScreen extends StatefulWidget {
  const OrgDashScreen({super.key});

  @override
  State<OrgDashScreen> createState() => _OrgDashScreenState();
}

class _OrgDashScreenState extends State<OrgDashScreen> {
  OrganizationDashboard? _dashboard;
  List<PublicReview> _reviews = const [];
  Object? _error;
  bool _loading = true;
  String? _loadedOrganizationId;
  bool _showAllReadiness = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    _refresh();
    _loadReviews(organizationId);
    app.refreshOpportunities(organizationId);
  }

  Future<void> _loadReviews(String organizationId) async {
    final app = context.read<AppState>();
    _reviews = const [];
    try {
      final reviews = await app.repository.reviewsForOrganization(
        organizationId,
        limit: 3,
      );
      if (!mounted || app.organizationId != organizationId) return;
      setState(() => _reviews = reviews);
    } catch (_) {
      // Reviews are optional; a failed load must not hide the dashboard.
    }
  }

  Future<void> _refresh() async {
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
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _dashboard = dashboard;
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dashboard = _dashboard;
    final reviewSummary = dashboard?.organization.reviewSummary;
    final membership = app.currentOrganization;
    final organizationName =
        dashboard?.organization.name ??
        membership?.organization.name ??
        'Organizer';
    final role = app.organizerRoleFor(app.organizationId) ?? dashboard?.role;
    final openOpportunities = app
        .opportunitiesFor(app.organizationId)
        .where((opportunity) => opportunity.status == OpportunityStatus.open)
        .length;

    final canManage = app.canManageOrganization(app.organizationId);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        headerTopPad(context),
        EpLayout.gutter,
        0,
      ),
      children: [
        _OrganizerHeader(
          organizationName: organizationName,
          role: role,
          onTap: () => showSwitcherSheet(context),
          onDiscover: app.toFanView,
        ),
        const SizedBox(height: 28),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _LoadError(onRetry: _refresh)
        else if (dashboard != null) ...[
          _ReadinessSection(
            verification: dashboard.verification,
            isHost: app.currentIsHost,
            showAll: _showAllReadiness,
            onShowAll: () => setState(() => _showAllReadiness = true),
          ),
          const SizedBox(height: 24),
          _DashboardStats(
            stats: [
              if (app.currentIsVenueOperator)
                _DashboardStat(
                  key: const Key('org-dash-venue-requests'),
                  value: '${dashboard.venues.length}',
                  label:
                      'Venues · '
                      '${dashboard.pendingVenueConsents > 0 ? '${dashboard.pendingVenueConsents} venue ${dashboard.pendingVenueConsents == 1 ? 'request' : 'requests'}' : 'managed profiles'}',
                ),
              if (!app.currentIsHost)
                _DashboardStat(
                  key: const Key('org-dash-stat-members'),
                  value: '${dashboard.memberCount}',
                  label: 'Members',
                ),
              Semantics(
                button: true,
                child: GestureDetector(
                  key: const Key('org-dash-stat-opportunities'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => app.resetTo(Screen.orgOpportunities),
                  child: _DashboardStat(
                    value: '$openOpportunities',
                    label: 'Open slots',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          EpMenuRow(
            key: const Key('org-dash-command-opportunity'),
            icon: Icons.add,
            label: app.currentIsHost ? 'New request' : 'New opportunity',
            sub: canManage
                ? 'Post a slot for artists'
                : 'Managers post opportunities',
            onTap: canManage ? app.openOpportunityEditor : null,
          ),
          if (app.currentIsHost || app.currentIsVenueOperator)
            EpMenuRow(
              key: Key(
                app.currentIsHost
                    ? 'org-dash-locations'
                    : 'org-dash-command-venues',
              ),
              icon: Icons.place_outlined,
              label: app.currentIsHost ? 'Locations' : 'Venues',
              onTap: app.currentIsHost
                  ? () => app.go(Screen.privateLocations)
                  : () => app.go(Screen.orgVenues),
            ),
          if (canManage && !app.currentIsHost)
            EpMenuRow(
              key: const Key('org-dash-command-team'),
              icon: Icons.people_outline,
              label: 'Team',
              onTap: () => app.go(Screen.orgTeam),
            ),
          if (app.canSeeFinance(app.organizationId))
            EpMenuRow(
              key: const Key('org-dash-command-finance'),
              icon: Icons.confirmation_number_outlined,
              label: 'Finance',
              trailingText: app.financeOverview == null
                  ? 'Set up'
                  : '${app.financeOverview!.ticketNetAmount.label} ticket net',
              onTap: app.openFinance,
            ),
          if (canManage)
            EpMenuRow(
              key: const Key('org-dash-command-settings'),
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => app.go(Screen.orgSettings),
            ),
          if (reviewSummary != null && reviewSummary.count > 0)
            Padding(
              key: const Key('org-dash-stat-rating'),
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EpEyebrow('Rating'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      EpDisplay(
                        reviewSummary.mean.toStringAsFixed(1),
                        size: 24,
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.star,
                        size: 16,
                        color: context.epColors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${reviewSummary.count} '
                          '${reviewSummary.count == 1 ? 'review' : 'reviews'} · '
                          '${reviewSummary.completedBookings} completed '
                          '${reviewSummary.completedBookings == 1 ? 'booking' : 'bookings'}',
                          style: Theme.of(context).textTheme.epBody.copyWith(
                            color: context.epColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_reviews.isNotEmpty)
            Column(
              key: const ValueKey('org-dash-reviews'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EpSectionHeader(label: 'Reviews'),
                for (final review in _reviews)
                  _ReviewRow(
                    key: ValueKey('org-dash-review-${review.reviewId}'),
                    review: review,
                  ),
              ],
            ),
        ],
        const SizedBox(height: tabBarClearance),
      ],
    );
  }
}

class _OrganizerHeader extends StatelessWidget {
  const _OrganizerHeader({
    required this.organizationName,
    required this.role,
    required this.onTap,
    required this.onDiscover,
  });

  final String organizationName;
  final OrganizationRole? role;
  final VoidCallback onTap;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final currentRole = role;
    final roleText = currentRole == null ? 'Member' : _roleLabel(currentRole);
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.zero,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: EpDisplay(organizationName, size: 20, maxLines: 2),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more,
                      size: 16,
                      color: context.epColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                EpEyebrow.accent('Organizer · $roleText'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        EpPill(
          label: 'Discover',
          variant: EpPillVariant.outline,
          size: EpPillSize.chip,
          onPressed: onDiscover,
        ),
      ],
    );
  }
}

class _ReadinessSection extends StatelessWidget {
  const _ReadinessSection({
    required this.verification,
    required this.isHost,
    required this.showAll,
    required this.onShowAll,
  });

  final OrganizationVerification verification;
  final bool isHost;
  final bool showAll;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        label: 'Verified',
        pendingLabel: 'Get verified',
        done: verification.verified,
        hint: 'Verification pending',
      ),
      if (!isHost) ...[
        (
          label: 'Stripe details',
          pendingLabel: 'Add Stripe details',
          done: verification.stripeDetailsSubmitted,
          hint: 'Stripe details pending',
        ),
        (
          label: 'Payouts enabled',
          pendingLabel: 'Enable payouts',
          done: verification.stripePayoutsEnabled,
          hint: 'Payouts pending',
        ),
      ],
      (
        label: 'Profile complete',
        pendingLabel: 'Complete your profile',
        done: verification.profileComplete,
        hint: 'Profile pending',
      ),
      if (!isHost)
        (
          label: 'Team invited',
          pendingLabel: 'Invite your team',
          done: verification.teamInvited,
          hint: 'Team pending',
        ),
    ];
    final done = steps.where((step) => step.done).length;
    final hint =
        steps.where((step) => !step.done).firstOrNull?.hint ?? 'All set';
    final showDone = showAll || EpLayout.isDesktop(context);

    return Column(
      key: const Key('org-dash-verification'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: EpEyebrow.accent('Readiness · $done of ${steps.length}'),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: EpEyebrow(hint),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        EpReadinessBar(done: done, total: steps.length),
        const SizedBox(height: 12),
        ...steps.where((step) => !step.done || showDone).map((step) {
          final key = switch (step.label) {
            'Stripe details' => const Key('org-dash-readiness-stripe'),
            'Payouts enabled' => const Key('org-dash-readiness-payouts'),
            _ => null,
          };
          final onAction = !step.done && key != null
              ? () => context.read<AppState>().go(Screen.orgSettings)
              : null;
          final row = EpChecklistRow(
            done: step.done,
            label: step.done ? step.label : step.pendingLabel,
            actionLabel: onAction == null ? null : 'Finish in Stripe',
            onAction: onAction,
            required: false,
          );
          if (step.done || key == null) return row;
          return InkWell(key: key, onTap: onAction, child: row);
        }),
        if (done > 0 && !showDone)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onShowAll,
              style: TextButton.styleFrom(
                foregroundColor: context.epColors.ink,
                textStyle: Theme.of(context).textTheme.epChipLabel,
              ),
              child: EpMonoText('Show all', color: context.epColors.ink),
            ),
          ),
      ],
    );
  }
}

class _DashboardStats extends StatelessWidget {
  const _DashboardStats({required this.stats});

  final List<Widget> stats;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const EpHairline(),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Match EpStatGrid while allowing the open-slots cell to navigate.
            final useTwoColumns =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            if (useTwoColumns) {
              final cellWidth =
                  (constraints.maxWidth - 16).clamp(0.0, double.infinity) / 2;
              return SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final stat in stats)
                      SizedBox(width: cellWidth, child: stat),
                  ],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final stat in stats) Expanded(child: stat)],
            );
          },
        ),
      ),
      const EpHairline(),
    ],
  );
}

class _DashboardStat extends StatelessWidget {
  const _DashboardStat({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      EpDisplay(value, size: 28),
      const SizedBox(height: 4),
      EpEyebrow(label),
    ],
  );
}

/// A public review as a hairline row: who wrote it, their rating, their words.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({super.key, required this.review});

  final PublicReview review;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.epColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(review.counterpartyName, style: textTheme.epBody),
          const SizedBox(height: 6),
          Semantics(
            label: '${review.rating} out of 5 stars',
            excludeSemantics: true,
            child: Row(
              children: [
                for (var rating = 1; rating <= 5; rating++)
                  Icon(
                    rating <= review.rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: context.epColors.accent,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(review.monthLabel, style: textTheme.epCaption),
          const SizedBox(height: 6),
          Text(review.text, style: textTheme.epBody),
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
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          Text(
            'Could not load the organizer dashboard.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.epBody,
          ),
          const SizedBox(height: 12),
          EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
        ],
      ),
    );
  }
}

String _roleLabel(OrganizationRole role) => switch (role) {
  OrganizationRole.owner => 'Owner',
  OrganizationRole.manager => 'Manager',
  OrganizationRole.finance => 'Finance',
  OrganizationRole.door => 'Door',
};
