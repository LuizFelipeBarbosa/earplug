import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/band_members_panel.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/readiness_module.dart';
import '../widgets/sheets.dart';
import 'door_mode.dart';

/// Vertical rhythm between the dashboard's sections.
const double _sectionGap = 28;

class BandDashScreen extends StatefulWidget {
  const BandDashScreen({super.key});

  @override
  State<BandDashScreen> createState() => _BandDashScreenState();
}

class _BandDashScreenState extends State<BandDashScreen> {
  String? _lastSection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final section = app.current.screen == Screen.bandDash
        ? app.current.param
        : null;
    if (section == _lastSection) return;
    final band = app.myBand;
    if (section == 'members' && band == null) return;
    _lastSection = section;
    if (section == 'members') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            app.current.screen != Screen.bandDash ||
            app.current.param != 'members') {
          return;
        }
        _showBandMembersSheet(context, band!.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null) return const SizedBox.shrink();

    final gigs = app.myBandGigs;
    final next = gigs.isEmpty ? null : gigs.first;
    final isAdmin = app.isAdminOf(band.id);
    // Only admins load readiness; the module renders nothing once every step
    // is done, so the gap around it follows the same rule.
    final snapshot = isAdmin ? app.readinessSnapshotFor(band.id) : null;
    final showReadiness = snapshot != null && !snapshot.complete;
    final readiness = isAdmin ? app.discoveryReadinessFor(band.id) : null;
    final readinessFailed =
        isAdmin &&
        readiness == null &&
        !app.discoveryReadinessLoadingFor(band.id);

    final manage = [
      const EpEyebrow('Manage'),
      const SizedBox(height: 4),
      _MenuRows(app: app, bandId: band.id, isAdmin: isAdmin),
      if (readiness != null) _BoostFooter(readiness: readiness),
    ];

    if (EpLayout.isDesktop(context)) {
      // The rail carries the identity, the switcher and "back to discover",
      // so the content column starts at the hero.
      return ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NextUp(app: app, gig: next, isAdmin: isAdmin),
                    const SizedBox(height: 40),
                    ...manage,
                  ],
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: 40),
                Expanded(
                  flex: 10,
                  child: Container(
                    padding: const EdgeInsets.only(left: 40),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: context.epColors.line),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ReadinessModule(bandId: band.id),
                        if (readinessFailed)
                          _ReadinessRetry(app: app, bandId: band.id),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        headerTopPad(context),
        EpLayout.gutter,
        tabBarClearance,
      ),
      children: [
        _Header(app: app, band: band),
        const SizedBox(height: _sectionGap),
        _NextUp(app: app, gig: next, isAdmin: isAdmin),
        if (isAdmin) ...[
          if (showReadiness) const SizedBox(height: _sectionGap),
          ReadinessModule(bandId: band.id),
          if (readinessFailed) ...[
            const SizedBox(height: _sectionGap),
            _ReadinessRetry(app: app, bandId: band.id),
          ],
        ],
        const SizedBox(height: _sectionGap),
        ...manage,
      ],
    );
  }
}

Future<void> _showBandMembersSheet(BuildContext context, String bandId) {
  return showEpSheet(
    context,
    (ctx) => KeyedSubtree(
      key: const Key('band-members-sheet'),
      child: EpSheetShell(
        padding: const EdgeInsets.fromLTRB(
          EpLayout.gutter,
          20,
          EpLayout.gutter,
          24,
        ),
        maxHeightFactor: .88,
        scrollable: true,
        header: const SizedBox.shrink(),
        children: [BandMembersPanel(bandId: bandId)],
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.app, required this.band});

  final AppState app;
  final Band band;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => showSwitcherSheet(context),
            child: Row(
              children: [
                if (band.profileImageUrl == null)
                  EpAvatarTile(initials: _initials(band.name), accent: true)
                else
                  BandAvatar(band),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: EpDisplay(band.name, size: 20, maxLines: 2),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.expand_more,
                            size: 16,
                            color: context.epColors.muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      EpEyebrow('Managing · ${app.roleFor(band.id)}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        EpPill(
          key: const Key('band-dash-discover'),
          label: 'Discover',
          variant: EpPillVariant.accentOutline,
          size: EpPillSize.chip,
          onPressed: app.toFanView,
        ),
      ],
    );
  }
}

/// The hero: the next published gig with its live RSVP count, or a prompt to
/// publish one.
class _NextUp extends StatelessWidget {
  const _NextUp({required this.app, required this.gig, required this.isAdmin});

  final AppState app;
  final Gig? gig;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final gig = this.gig;
    if (gig == null) {
      return EpCard(
        key: const Key('band-next-up-empty'),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EpEyebrow('Nothing scheduled'),
            const SizedBox(height: 12),
            const EpDisplay(
              'No gig coming up — publish one',
              size: 24,
              maxLines: 3,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: EpPill(
                  key: const Key('band-next-up-publish'),
                  label: 'Publish a gig',
                  variant: EpPillVariant.primary,
                  size: EpPillSize.chip,
                  onPressed: app.startGigCreate,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return EpCard(
      key: const Key('band-next-up'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: EpEyebrow.accent('Next up')),
              const SizedBox(width: 12),
              Flexible(
                child: EpMonoText(
                  '${gig.dateShort} · Doors ${_doorsLabel(context, gig)}',
                  key: const Key('band-next-up-when'),
                  color: context.epColors.contentSecondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          EpDisplay(gig.title, size: 32, maxLines: 3),
          const SizedBox(height: 12),
          EpMonoText(
            '${app.venue(gig.venueId).name} · ${app.rsvpCount(gig)} RSVPs · '
            'counting live',
            color: context.epColors.contentSecondary,
          ),
          const SizedBox(height: 20),
          // A wrap rather than a row so large text never clips an action.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isAdmin)
                EpPill(
                  key: const Key('band-next-door-mode'),
                  label: 'Door mode',
                  variant: EpPillVariant.primary,
                  size: EpPillSize.chip,
                  onPressed: () =>
                      showDoorMode(context, _doorLaunchFor(context, app, gig)),
                ),
              EpPill(
                key: const Key('band-next-public-gig'),
                label: 'Public gig ↗',
                variant: EpPillVariant.outline,
                size: EpPillSize.chip,
                keepCase: true,
                onPressed: () => app.openGig(gig.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuRows extends StatelessWidget {
  const _MenuRows({
    required this.app,
    required this.bandId,
    required this.isAdmin,
  });

  final AppState app;
  final String bandId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isAdmin)
          EpMenuRow(
            key: const Key('band-command-publish-gig'),
            icon: Icons.add,
            label: 'Publish a gig',
            onTap: app.startGigCreate,
          ),
        EpMenuRow(
          key: const Key('band-command-add-media'),
          icon: Icons.play_arrow,
          label: 'Add media',
          onTap: app.openBandMedia,
        ),
        EpMenuRow(
          key: const Key('band-command-analytics'),
          icon: Icons.bar_chart,
          label: 'Insights',
          onTap: () => app.resetTo(Screen.analytics),
        ),
        if (isAdmin)
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
        if (isAdmin)
          EpMenuRow(
            key: const Key('band-command-edit-profile'),
            icon: Icons.edit_outlined,
            label: 'Edit profile',
            onTap: app.openBandEditor,
          ),
        EpMenuRow(
          key: const Key('band-command-members'),
          icon: Icons.group_outlined,
          label: 'Band members',
          trailingText:
              '${app.profileDetailsFor(bandId)?.memberNames.length ?? 0}',
          onTap: () => _showBandMembersSheet(context, bandId),
        ),
        EpMenuRow(
          key: const Key('band-public-profile'),
          icon: Icons.mic_none,
          label: isAdmin ? 'Preview public profile' : 'View public profile',
          onTap: app.previewPublicProfile,
        ),
      ],
    );
  }
}

/// Stripe onboarding is not finished until the account is enabled.
bool _payoutsNeedSetup(StripeAccountStatus? status) => switch (status?.state) {
  StripeAccountState.enabled => false,
  _ => true,
};

/// Two muted lines under the menu: the next show that can be boosted and its
/// window. The boundary refresh that keeps `active` current lives in AppState.
class _BoostFooter extends StatelessWidget {
  const _BoostFooter({required this.readiness});

  final BandDiscoveryReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final show = readiness.nextEligibleShow;
    final window = readiness.boostWindow;
    if (show == null || window == null) return const SizedBox.shrink();
    final palette = context.epColors;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpMonoText(
            'Next eligible · ${show.title}',
            key: const Key('band-boost-next'),
            color: palette.contentSecondary,
          ),
          const SizedBox(height: 4),
          EpMonoText(
            'Boost window · '
            '${Gig.dateShortFor(window.opensAt.millisecondsSinceEpoch)} – '
            '${Gig.dateShortFor(window.closesAt.millisecondsSinceEpoch)}'
            '${window.active ? ' · Active now' : ''}',
            key: const Key('band-boost-window'),
            color: window.active ? palette.accent : palette.contentSecondary,
          ),
        ],
      ),
    );
  }
}

/// Shown only when discovery readiness failed to load, so the checklist has
/// nothing to build from.
class _ReadinessRetry extends StatelessWidget {
  const _ReadinessRetry({required this.app, required this.bandId});

  final AppState app;
  final String bandId;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: EpMonoText(
          'Readiness unavailable',
          color: context.epColors.contentSecondary,
        ),
      ),
      const SizedBox(width: 12),
      EpPill(
        key: const Key('band-readiness-retry'),
        label: 'Retry',
        size: EpPillSize.chip,
        onPressed: () {
          app.refreshBandDiscoveryReadiness(bandId);
          app.refreshBandSetupStatus(bandId);
        },
      ),
    ],
  );
}

String _doorsLabel(BuildContext context, Gig gig) => gig.doorsAt == null
    ? gig.time.split('/').first.trim()
    : TimeOfDay.fromDateTime(gig.doorsAt!.toLocal()).format(context);

DoorModeLaunch _doorLaunchFor(BuildContext context, AppState app, Gig next) =>
    DoorModeLaunch.organizer(
      gigId: next.id,
      gigTitle: next.title,
      venueName: app.venue(next.venueId).name,
      doorsTime: _doorsLabel(context, next),
    );

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2);
  return words.isEmpty ? '??' : words.map((word) => word[0]).join();
}
