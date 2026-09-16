import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/sheets.dart';
import 'door_mode.dart';

class BandDashScreen extends StatelessWidget {
  const BandDashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null) return const SizedBox.shrink();

    final gigs = app.myBandGigs;
    final next = gigs.isEmpty ? null : gigs.first;
    final clips = context.watch<BandMediaController>().videosFor(band.id);
    final isAdmin = app.isAdminOf(band.id);
    final desktop = EpLayout.isDesktop(context);
    final stats = [
      EpStat(band.followersLabel, 'Fans'),
      EpStat(next == null ? '0' : '${app.rsvpCount(next)}', 'Next RSVPs'),
      EpStat('${clips.length}', 'Clips'),
    ];

    if (desktop) {
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
                    _NextUp(
                      app: app,
                      gig: next,
                      isAdmin: isAdmin,
                      displaySize: 72,
                      showPublishAnother: true,
                    ),
                    const SizedBox(height: 40),
                    EpStatGrid(stats: stats, valueSize: 48),
                    _UpcomingGigs(app: app, gigs: gigs),
                    _MenuRows(app: app, isAdmin: isAdmin),
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
                    child: _Readiness(
                      app: app,
                      bandId: band.id,
                      expanded: true,
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
        const SizedBox(height: 28),
        _NextUp(app: app, gig: next, isAdmin: isAdmin, displaySize: 44),
        const SizedBox(height: 28),
        EpStatGrid(stats: stats),
        _MenuRows(app: app, isAdmin: isAdmin),
        if (isAdmin) _Readiness(app: app, bandId: band.id, expanded: false),
      ],
    );
  }
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
                      Wrap(
                        children: [
                          EpEyebrow('Managing · ${app.roleFor(band.id)}'),
                          if (band.profileComplete)
                            const EpEyebrow(
                              ' · Profile complete',
                              key: Key('profile-complete-badge'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        EpPill(label: 'Discover', onPressed: app.toFanView),
      ],
    );
  }
}

class _NextUp extends StatelessWidget {
  const _NextUp({
    required this.app,
    required this.gig,
    required this.isAdmin,
    required this.displaySize,
    this.showPublishAnother = false,
  });

  final AppState app;
  final Gig? gig;
  final bool isAdmin;
  final double displaySize;
  final bool showPublishAnother;

  @override
  Widget build(BuildContext context) {
    final gig = this.gig;
    if (gig == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EpEyebrow.accent('Nothing scheduled'),
          const SizedBox(height: 12),
          EpDisplay('Publish\nyour next show', size: displaySize, maxLines: 3),
          if (isAdmin) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: EpPill(
                label: 'Publish a gig',
                variant: EpPillVariant.primary,
                size: EpPillSize.regular,
                onPressed: app.startGigCreate,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpEyebrow.accent(
          'Next up · ${gig.dateShort} · Doors ${_doorsLabel(context, gig)}',
        ),
        const SizedBox(height: 12),
        EpDisplay(gig.title, size: displaySize, maxLines: 3),
        const SizedBox(height: 12),
        Text(
          '${app.venue(gig.venueId).name} · ${app.rsvpCount(gig)} RSVPs · '
          'counting live',
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (isAdmin)
              EpPill(
                label: 'Door mode',
                variant: EpPillVariant.primary,
                size: EpPillSize.regular,
                onPressed: () =>
                    showDoorMode(context, _doorLaunchFor(context, app, gig)),
              ),
            EpPill(
              key: const Key('band-next-public-gig'),
              label: 'Public gig ↗',
              size: EpPillSize.regular,
              onPressed: () => app.openGig(gig.id),
            ),
            if (isAdmin && showPublishAnother)
              EpPill(
                label: 'Publish another',
                size: EpPillSize.regular,
                onPressed: app.startGigCreate,
              ),
          ],
        ),
      ],
    );
  }
}

/// Desktop-only list of the band's gigs; the rail has no gig manager shortcut.
class _UpcomingGigs extends StatelessWidget {
  const _UpcomingGigs({required this.app, required this.gigs});

  final AppState app;
  final List<Gig> gigs;

  @override
  Widget build(BuildContext context) {
    if (gigs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 4),
          child: EpEyebrow('Upcoming · ${gigs.length}'),
        ),
        for (final gig in gigs)
          EpGigRow(
            key: ValueKey('band-gig-${gig.id}'),
            date: gig.startsAt.toLocal(),
            title: gig.title,
            sub: '${app.venue(gig.venueId).name} · ${app.rsvpCount(gig)} RSVPs',
            onTap: app.openGigManager,
            trailing: EpMonoText('Manage', color: context.epColors.muted),
          ),
      ],
    );
  }
}

class _MenuRows extends StatelessWidget {
  const _MenuRows({required this.app, required this.isAdmin});

  final AppState app;
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
            trailingText: switch (app.bandPayoutStatus?.state) {
              StripeAccountState.enabled =>
                (app.bandPayoutStatus?.canSellTickets ?? false)
                    ? 'Enabled'
                    : 'Enable ticket sales',
              StripeAccountState.onboarding ||
              StripeAccountState.restricted => 'Finish setup',
              _ => 'Set up',
            },
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
          key: const Key('band-public-profile'),
          icon: Icons.mic_none,
          label: isAdmin ? 'Preview public profile' : 'View public profile',
          onTap: app.previewPublicProfile,
        ),
      ],
    );
  }
}

/// Discovery readiness and the setup checklist as one list: the six discovery
/// steps plus the three setup tasks discovery does not already cover.
class _Readiness extends StatefulWidget {
  const _Readiness({
    required this.app,
    required this.bandId,
    required this.expanded,
  });

  final AppState app;
  final String bandId;

  /// Desktop shows every item; the phone hides completed ones behind a toggle.
  final bool expanded;

  @override
  State<_Readiness> createState() => _ReadinessState();
}

class _ReadinessState extends State<_Readiness> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final readiness = app.discoveryReadinessFor(widget.bandId);
    final status = app.setupStatusFor(widget.bandId);
    final items = _readinessItems(app, readiness, status);
    final done = items.where((item) => item.done).length;
    final showAll = widget.expanded || _showAll;
    final visible = showAll
        ? items
        : items.where((item) => !item.done).toList(growable: false);

    return Column(
      key: const Key('band-readiness'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: widget.expanded ? 0 : 24, bottom: 8),
          child: Row(
            children: [
              const Expanded(child: EpEyebrow('Readiness')),
              const SizedBox(width: 12),
              EpEyebrow('$done of ${items.length}'),
            ],
          ),
        ),
        if (items.isNotEmpty) ...[
          EpReadinessBar(done: done, total: items.length),
          const SizedBox(height: 12),
        ],
        if (widget.expanded)
          Text(
            'Complete listings move ahead within nearby same-day results.',
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.muted),
          ),
        for (final item in visible)
          EpChecklistRow(
            key: item.key,
            done: item.done,
            label: item.label,
            actionLabel: item.done ? null : item.actionLabel,
            onAction: item.done ? null : item.onAction,
          ),
        if (!widget.expanded && done > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('band-readiness-toggle'),
              onPressed: () => setState(() => _showAll = !_showAll),
              child: EpMonoText(_showAll ? 'Show remaining' : 'Show all'),
            ),
          ),
        if (readiness == null)
          _ReadinessRetry(
            label: 'Retry discovery readiness',
            loading: app.discoveryReadinessLoadingFor(widget.bandId),
            onRetry: () => app.refreshBandDiscoveryReadiness(widget.bandId),
          ),
        if (status == null)
          _ReadinessRetry(
            label: 'Retry setup checklist',
            loading: app.setupStatusLoadingFor(widget.bandId),
            onRetry: () => app.refreshBandSetupStatus(widget.bandId),
          ),
        if (readiness?.nextEligibleShow case final show?)
          if (readiness?.boostWindow case final window?) ...[
            const SizedBox(height: 20),
            EpEyebrow('Next eligible · ${show.title}'),
            const SizedBox(height: 4),
            _BoostWindow(window: window),
          ],
      ],
    );
  }
}

class _BoostWindow extends StatelessWidget {
  const _BoostWindow({required this.window});

  final DiscoveryBoostWindow window;

  @override
  Widget build(BuildContext context) {
    final label =
        'Boost window · '
        '${Gig.dateShortFor(window.opensAt.millisecondsSinceEpoch)} – '
        '${Gig.dateShortFor(window.closesAt.millisecondsSinceEpoch)}'
        '${window.active ? ' · Active now' : ''}';
    return window.active ? EpEyebrow.accent(label) : EpEyebrow(label);
  }
}

class _ReadinessRetry extends StatelessWidget {
  const _ReadinessRetry({
    required this.label,
    required this.loading,
    required this.onRetry,
  });

  final String label;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: loading
        ? const Center(child: CircularProgressIndicator())
        : Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onRetry, child: EpMonoText(label)),
          ),
  );
}

class _ReadinessItem {
  const _ReadinessItem({
    required this.key,
    required this.label,
    required this.done,
    required this.actionLabel,
    required this.onAction,
  });

  final Key key;
  final String label;
  final bool done;
  final String actionLabel;
  final VoidCallback onAction;
}

List<_ReadinessItem> _readinessItems(
  AppState app,
  BandDiscoveryReadiness? readiness,
  BandSetupStatus? status,
) {
  final hasShow = readiness?.relevantShow != null;
  final showAction = hasShow ? app.openGigManager : app.startGigCreate;
  return [
    if (readiness != null) ...[
      _ReadinessItem(
        key: const ValueKey('band-discovery-profile'),
        label: 'Complete profile',
        done: readiness.profileComplete,
        actionLabel: 'Edit',
        onAction: () => app.openBandEditor(section: 'required'),
      ),
      _ReadinessItem(
        key: const ValueKey('band-discovery-image'),
        label: 'Profile image',
        done: readiness.profileImageReady,
        actionLabel: 'Add',
        onAction: app.openBandMedia,
      ),
      _ReadinessItem(
        key: const ValueKey('band-discovery-clip'),
        label: 'Video clip',
        done: readiness.clipReady,
        actionLabel: 'Add',
        onAction: app.openBandMedia,
      ),
      _ReadinessItem(
        key: const ValueKey('band-discovery-show'),
        label: 'Published lineup',
        done: readiness.publishedShowReady,
        actionLabel: hasShow ? 'Manage' : 'Create',
        onAction: showAction,
      ),
      _ReadinessItem(
        key: const ValueKey('band-discovery-listing'),
        label: 'Venue and readable poster',
        done: readiness.venuePosterReady,
        actionLabel: hasShow ? 'Edit' : 'Create',
        onAction: showAction,
      ),
      _ReadinessItem(
        key: const ValueKey('band-discovery-revision'),
        label: 'Latest revision published',
        done: readiness.publishedRevisionCurrent,
        actionLabel: hasShow ? 'Republish' : 'Create',
        onAction: showAction,
      ),
    ],
    if (status != null) ...[
      _ReadinessItem(
        key: const ValueKey('band-setup-preview'),
        label: 'Public profile previewed',
        done: status.publicProfilePreviewed,
        actionLabel: 'Preview',
        onAction: app.previewPublicProfile,
      ),
      _ReadinessItem(
        key: const ValueKey('band-setup-social'),
        label: 'Add social links',
        done: status.socialLinksAdded,
        actionLabel: 'Edit',
        onAction: () => app.openBandEditor(section: 'links'),
      ),
      _ReadinessItem(
        key: const ValueKey('band-setup-members'),
        label: 'Invite band members',
        done: status.membersInvited,
        actionLabel: 'Invite',
        onAction: app.openInvitationPanel,
      ),
    ],
  ];
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
