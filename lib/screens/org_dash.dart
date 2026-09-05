import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/readiness_segments.dart';
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

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        _DashboardHeader(
          organizationName: organizationName,
          role: role,
          onTap: () => showSwitcherSheet(context),
          onDiscover: app.toFanView,
        ),
        const SizedBox(height: 18),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _LoadError(onRetry: _refresh)
        else if (dashboard != null) ...[
          _VerificationCard(verification: dashboard.verification),
          const SizedBox(height: 18),
          Row(
            children: [
              EpStatCard(
                label: 'VENUES',
                value: '${dashboard.venues.length}',
                caption: 'managed profiles',
              ),
              const SizedBox(width: 8),
              EpStatCard(
                label: 'MEMBERS',
                value: '${dashboard.memberCount}',
                caption: 'on the team',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  key: const Key('org-dash-stat-opportunities'),
                  onTap: () => app.resetTo(Screen.orgOpportunities),
                  child: EpStatCard(
                    expand: false,
                    label: 'OPPORTUNITIES',
                    value: '$openOpportunities',
                    caption: openOpportunities > 0
                        ? 'open right now'
                        : 'none open',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionBar(label: 'COMMAND CENTER'),
          const SizedBox(height: 10),
          _CommandGrid(
            canManage: app.canManageOrganization(app.organizationId),
            onOpportunity: app.openOpportunityEditor,
            onVenues: () => app.go(Screen.orgVenues),
            onTeam: () => app.go(Screen.orgTeam),
            onSettings: () => app.go(Screen.orgSettings),
          ),
          const SizedBox(height: 12),
          EpStatCard(
            key: const ValueKey('org-dash-stat-rating'),
            expand: false,
            label: 'RATING',
            value: reviewSummary != null && reviewSummary.count > 0
                ? reviewSummary.mean.toStringAsFixed(1)
                : '—',
            caption: reviewSummary != null && reviewSummary.count > 0
                ? '${reviewSummary.count} reviews'
                : 'no reviews yet',
          ),
          if (_reviews.isNotEmpty)
            Column(
              key: const ValueKey('org-dash-reviews'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionBar(label: 'REVIEWS'),
                for (final review in _reviews) ...[
                  EpCard(
                    key: ValueKey('org-dash-review-${review.reviewId}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review.counterpartyName,
                          style: Theme.of(context).textTheme.epBody,
                        ),
                        const SizedBox(height: 6),
                        Semantics(
                          label: '${review.rating} out of 5 stars',
                          excludeSemantics: true,
                          child: Row(
                            children: [
                              for (var rating = 1; rating <= 5; rating++)
                                Icon(
                                  rating <= review.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  size: 18,
                                  color: context.epColors.accent,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          review.monthLabel,
                          style: Theme.of(context).textTheme.epCaption,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          review.text,
                          style: Theme.of(context).textTheme.epBody,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
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
    final roleText = currentRole == null
        ? 'MEMBER'
        : _roleLabel(currentRole).toUpperCase();
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.zero,
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 34),
                const SizedBox(width: 9),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              organizationName.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: epDisplay(size: 16, height: 1),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'ORGANIZER · $roleText',
                        style: epText(
                          size: 11,
                          weight: FontWeight.w800,
                          letterSpacing: 1,
                          color: context.epColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: onDiscover, child: const Text('DISCOVER')),
      ],
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.verification});

  final OrganizationVerification verification;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, bool, String?)>[
      ('Verified', verification.verified, null),
      ('Stripe details', verification.stripeDetailsSubmitted, null),
      ('Payouts enabled', verification.stripePayoutsEnabled, null),
      ('Profile complete', verification.profileComplete, null),
      ('Team invited', verification.teamInvited, null),
    ];
    return EpCard(
      key: const Key('org-dash-verification'),
      variant: EpCardVariant.raised,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ORGANIZATION READINESS', style: epDisplay(size: 15)),
          const SizedBox(height: 11),
          ReadinessSegments(steps: [for (final step in steps) step.$2]),
          const SizedBox(height: 10),
          ...steps.map((step) {
            final row = Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    step.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: step.$2
                        ? context.epColors.success
                        : context.epColors.contentDisabled,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.$1,
                          style: Theme.of(context).textTheme.epBody,
                        ),
                        if (step.$3 case final caption?)
                          Text(
                            caption,
                            style: Theme.of(context).textTheme.epCaption,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            final key = switch (step.$1) {
              'Stripe details' => const Key('org-dash-readiness-stripe'),
              'Payouts enabled' => const Key('org-dash-readiness-payouts'),
              _ => null,
            };
            if (step.$2 || key == null) return row;
            return InkWell(
              key: key,
              onTap: () => context.read<AppState>().go(Screen.orgSettings),
              child: row,
            );
          }),
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

class _CommandGrid extends StatelessWidget {
  const _CommandGrid({
    required this.canManage,
    required this.onOpportunity,
    required this.onVenues,
    required this.onTeam,
    required this.onSettings,
  });

  final bool canManage;
  final VoidCallback onOpportunity;
  final VoidCallback onVenues;
  final VoidCallback onTeam;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final commands = [
      _Command(
        key: const Key('org-dash-command-opportunity'),
        label: 'NEW OPPORTUNITY',
        caption: canManage
            ? 'Post a slot for artists'
            : 'Managers post opportunities',
        icon: Icons.campaign_outlined,
        onTap: canManage ? onOpportunity : null,
      ),
      _Command(
        key: const Key('org-dash-command-venues'),
        label: 'VENUES',
        icon: Icons.location_on_outlined,
        onTap: onVenues,
      ),
      if (canManage)
        _Command(
          key: const Key('org-dash-command-team'),
          label: 'TEAM',
          icon: Icons.group_outlined,
          onTap: onTeam,
        ),
      if (canManage)
        _Command(
          key: const Key('org-dash-command-settings'),
          label: 'SETTINGS',
          icon: Icons.settings_outlined,
          onTap: onSettings,
        ),
    ];
    final singleColumn =
        MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.35;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: singleColumn ? 1 : 2,
        childAspectRatio: singleColumn ? 3.5 : 1.55,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: commands.length,
      itemBuilder: (_, index) => commands[index],
    );
  }
}

class _Command extends StatelessWidget {
  const _Command({
    super.key,
    required this.label,
    required this.icon,
    this.caption,
    this.onTap,
  });

  final String label;
  final String? caption;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = enabled
        ? context.epColors.ink
        : context.epColors.contentDisabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled
            ? context.epColors.surface
            : context.epColors.surfaceDisabled,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.epColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground, size: 22),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.epLabel.copyWith(color: foreground),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    caption!,
                    style: Theme.of(context).textTheme.epCaption.copyWith(
                      color: context.epColors.contentDisabled,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
