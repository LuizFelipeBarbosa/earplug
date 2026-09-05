import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/readiness_segments.dart';
import '../widgets/sheets.dart';
import 'door_mode.dart';

class BandDashScreen extends StatelessWidget {
  const BandDashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null) return const SizedBox.shrink();

    final mine = app.myBandGigs;
    final next = mine.isEmpty ? null : mine.first;
    final media = context.watch<BandMediaController>();
    final clips = media.videosFor(band.id);
    final isAdmin = app.isAdminOf(band.id);
    final readiness = isAdmin ? app.discoveryReadinessFor(band.id) : null;
    final doorLaunch = next == null || !isAdmin
        ? null
        : _doorLaunchFor(context, app, next, readiness);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => showSwitcherSheet(context),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                ),
                child: Row(
                  children: [
                    BandAvatar(band, size: 38, radius: 9, fontSize: 13),
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
                                  band.name.toUpperCase(),
                                  style: epDisplay(size: 16, height: 1),
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 18),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'MANAGING · ${app.roleFor(band.id).toUpperCase()}',
                            style: epText(
                              size: 11,
                              weight: FontWeight.w800,
                              letterSpacing: 1,
                              color: context.epColors.accent,
                            ),
                          ),
                          if (band.profileComplete) ...[
                            const SizedBox(height: 5),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: ProfileCompleteBadge(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: app.toFanView, child: Text('DISCOVER')),
          ],
        ),
        if (next != null) ...[
          const SizedBox(height: 14),
          VoltStrip(
            kicker: 'NEXT UP · ${next.dateShort}',
            title: next.title,
            meta:
                '${app.venue(next.venueId).name} · ${next.time} · ${app.rsvpCount(next)} RSVPs · counting live',
            actionLabel: doorLaunch == null ? null : 'DOOR MODE',
            onAction: doorLaunch == null
                ? null
                : () => showDoorMode(context, doorLaunch),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('band-next-public-gig'),
              onPressed: () => app.openGig(next.id),
              child: Text('VIEW PUBLIC GIG →'),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            EpStatCard(
              label: 'FANS',
              value: band.followersLabel,
              caption: band.followers == 0
                  ? 'just the band so far'
                  : 'and counting',
            ),
            const SizedBox(width: 8),
            EpStatCard(
              label: 'NEXT GIG RSVPS',
              value: next != null ? '${app.rsvpCount(next)}' : '0',
              caption: next != null
                  ? (next.title.length > 16
                        ? next.title.substring(0, 16)
                        : next.title)
                  : 'no gig listed',
            ),
            const SizedBox(width: 8),
            EpStatCard(
              label: 'MUSIC CLIPS',
              value: '${clips.length}',
              caption: clips.isEmpty
                  ? 'post your first sample'
                  : 'on your profile',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionBar(label: 'CONSOLE'),
        const SizedBox(height: 10),
        _CommandGrid(
          openMedia: app.openBandMedia,
          publishGig: isAdmin
              ? app.gigWritePolicy
                    ? app.startGigCreate
                    : () => app.resetTo(Screen.gigMgr)
              : null,
          gigCommandLabel: app.gigWritePolicy ? 'PUBLISH GIG' : 'FIND GIGS',
          gigCommandIcon: app.gigWritePolicy ? Icons.add : Icons.search,
          editProfile: isAdmin ? app.openBandEditor : null,
          openAnalytics: () => app.resetTo(Screen.analytics),
          openPayouts: isAdmin ? () => app.resetTo(Screen.bandPayouts) : null,
          payoutsCaption: switch (app.bandPayoutStatus?.state) {
            StripeAccountState.enabled => 'Enabled',
            StripeAccountState.onboarding ||
            StripeAccountState.restricted => 'Finish setup',
            _ => 'Set up payouts',
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('band-public-profile'),
            onPressed: app.previewPublicProfile,
            child: Text(
              isAdmin ? 'PREVIEW PUBLIC PROFILE →' : 'VIEW PUBLIC PROFILE →',
            ),
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 14),
          _DiscoveryReadinessCard(app: app, bandId: band.id),
          const SizedBox(height: 20),
          _SetupChecklist(app: app, bandId: band.id),
        ],
      ],
    );
  }
}

DoorModeLaunch? _doorLaunchFor(
  BuildContext context,
  AppState app,
  Gig next,
  BandDiscoveryReadiness? readiness,
) {
  if (next.tix != Ticketing.rsvp) return null;

  String? projectId;
  final readinessShows = [readiness?.relevantShow, readiness?.nextEligibleShow];
  for (final show in readinessShows) {
    if (show?.gigId == next.id && show!.projectId.trim().isNotEmpty) {
      projectId = show.projectId;
      break;
    }
  }
  if (projectId == null) {
    for (final project in app.managedGigProjects) {
      if (project.publicGigId == next.id && project.id.trim().isNotEmpty) {
        projectId = project.id;
        break;
      }
    }
  }
  if (projectId == null) return null;

  final doorsTime = next.doorsAt == null
      ? next.time.split('/').first.trim()
      : TimeOfDay.fromDateTime(next.doorsAt!.toLocal()).format(context);
  return DoorModeLaunch(
    projectId: projectId,
    gigTitle: next.title,
    venueName: app.venue(next.venueId).name,
    doorsTime: doorsTime,
  );
}

class _DiscoveryReadinessCard extends StatelessWidget {
  const _DiscoveryReadinessCard({required this.app, required this.bandId});

  final AppState app;
  final String bandId;

  @override
  Widget build(BuildContext context) {
    final readiness = app.discoveryReadinessFor(bandId);
    if (readiness == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionBar(label: 'DISCOVERY READINESS'),
          const SizedBox(height: 8),
          if (app.discoveryReadinessLoadingFor(bandId))
            const Center(child: CircularProgressIndicator())
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => app.refreshBandDiscoveryReadiness(bandId),
                child: Text('Retry discovery readiness'),
              ),
            ),
        ],
      );
    }

    final showAction = readiness.relevantShow == null && app.gigWritePolicy
        ? app.startGigCreate
        : app.openGigManager;
    final tasks = [
      _DiscoveryTask(
        id: 'profile',
        label: 'Complete profile',
        action: 'EDIT PROFILE',
        complete: readiness.profileComplete,
        onTap: () => app.openBandEditor(section: 'required'),
      ),
      _DiscoveryTask(
        id: 'image',
        label: 'Assign a valid profile image',
        action: 'ADD PHOTO',
        complete: readiness.profileImageReady,
        onTap: app.openBandMedia,
      ),
      _DiscoveryTask(
        id: 'clip',
        label: 'Upload a video clip',
        action: 'ADD CLIP',
        complete: readiness.clipReady,
        onTap: app.openBandMedia,
      ),
      _DiscoveryTask(
        id: 'show',
        label: 'Publish a resolved lineup',
        action: readiness.relevantShow == null ? 'CREATE SHOW' : 'MANAGE SHOW',
        complete: readiness.publishedShowReady,
        onTap: showAction,
      ),
      _DiscoveryTask(
        id: 'listing',
        label: 'Use a venue and readable poster',
        action: readiness.relevantShow == null ? 'CREATE SHOW' : 'EDIT LISTING',
        complete: readiness.venuePosterReady,
        onTap: showAction,
      ),
      _DiscoveryTask(
        id: 'revision',
        label: 'Publish the latest revision',
        action: readiness.relevantShow == null ? 'CREATE SHOW' : 'REPUBLISH',
        complete: readiness.publishedRevisionCurrent,
        onTap: showAction,
      ),
    ];
    final show = readiness.nextEligibleShow;
    final window = readiness.boostWindow;

    return EpCard(
      key: const Key('discovery-readiness-card'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: SectionBar(label: 'DISCOVERY READINESS')),
              Text(
                '${readiness.completedCount} of 6 complete',
                style: Theme.of(context).textTheme.epCaption,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Complete listings can move ahead within nearby same-day results.',
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 10),
          ReadinessSegments(steps: readiness.steps),
          const SizedBox(height: 6),
          for (final task in tasks) _DiscoveryTaskRow(task: task),
          if (show != null && window != null) ...[
            const SizedBox(height: 10),
            Text(
              'NEXT ELIGIBLE · ${show.title.toUpperCase()}',
              style: Theme.of(context).textTheme.epLabel,
            ),
            const SizedBox(height: 3),
            Text(
              'BOOST WINDOW · ${Gig.dateShortFor(window.opensAt.millisecondsSinceEpoch)} '
              '– ${Gig.dateShortFor(window.closesAt.millisecondsSinceEpoch)}'
              '${window.active ? ' · ACTIVE NOW' : ''}',
              style: Theme.of(context).textTheme.epCaption.copyWith(
                color: window.active
                    ? context.epColors.success
                    : context.epColors.contentSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiscoveryTask {
  const _DiscoveryTask({
    required this.id,
    required this.label,
    required this.action,
    required this.complete,
    required this.onTap,
  });

  final String id;
  final String label;
  final String action;
  final bool complete;
  final VoidCallback onTap;
}

class _DiscoveryTaskRow extends StatelessWidget {
  const _DiscoveryTaskRow({required this.task});

  final _DiscoveryTask task;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('band-discovery-${task.id}'),
      onTap: task.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(
                task.complete
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 16,
                color: task.complete
                    ? context.epColors.success
                    : context.epColors.accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  task.label,
                  style: Theme.of(context).textTheme.epBody,
                ),
              ),
              const SizedBox(width: 6),
              Text(task.action, style: Theme.of(context).textTheme.epCaption),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupChecklist extends StatelessWidget {
  const _SetupChecklist({required this.app, required this.bandId});

  final AppState app;
  final String bandId;

  @override
  Widget build(BuildContext context) {
    final status = app.setupStatusFor(bandId);
    final tasks = status == null
        ? const <_BandTask>[]
        : [
            _BandTask(
              id: 'profile',
              label: 'Complete profile',
              complete: status.profileComplete,
              onTap: () => app.openBandEditor(section: 'required'),
            ),
            _BandTask(
              id: 'image',
              label: 'Add a profile image',
              complete: status.profileImageAdded,
              onTap: app.openBandMedia,
            ),
            _BandTask(
              id: 'music',
              label: 'Add music or a clip',
              complete: status.musicAdded,
              onTap: app.openBandMedia,
            ),
            _BandTask(
              id: 'social',
              label: 'Add social links',
              complete: status.socialLinksAdded,
              onTap: () => app.openBandEditor(section: 'links'),
            ),
            _BandTask(
              id: 'gig',
              label: 'Create first gig',
              complete: status.firstGigCreated,
              onTap: app.startGigCreate,
            ),
            _BandTask(
              id: 'members',
              label: 'Invite band members',
              complete: status.membersInvited,
              onTap: app.openInvitationPanel,
            ),
            _BandTask(
              id: 'preview',
              label: 'Preview public profile',
              complete: status.publicProfilePreviewed,
              onTap: app.previewPublicProfile,
            ),
          ];

    return Column(
      key: const Key('band-setup-checklist'),
      children: [
        Row(
          children: [
            const Expanded(child: SectionBar(label: 'SETUP CHECKLIST')),
            const SizedBox(width: 8),
            if (status != null)
              Text(
                '${status.completedCount} of 7 complete',
                style: Theme.of(context).textTheme.epCaption,
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (status == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: app.setupStatusLoadingFor(bandId)
                ? const Center(child: CircularProgressIndicator())
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => app.refreshBandSetupStatus(bandId),
                      child: Text('Retry setup checklist'),
                    ),
                  ),
          )
        else
          for (final task in tasks) _BandTaskRow(task: task),
      ],
    );
  }
}

class _BandTask {
  final String id;
  final String label;
  final bool complete;
  final VoidCallback onTap;

  const _BandTask({
    required this.id,
    required this.label,
    required this.complete,
    required this.onTap,
  });
}

class _BandTaskRow extends StatelessWidget {
  final _BandTask task;

  const _BandTaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('band-setup-${task.id}'),
        onTap: task.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.epColors.border)),
          ),
          child: Row(
            children: [
              Icon(
                task.complete
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 16,
                color: task.complete
                    ? context.epColors.success
                    : context.epColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.label,
                  style: Theme.of(context).textTheme.epBody,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: context.epColors.contentSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandGrid extends StatelessWidget {
  final VoidCallback openMedia;
  final VoidCallback? publishGig;
  final String gigCommandLabel;
  final IconData gigCommandIcon;
  final VoidCallback? editProfile;
  final VoidCallback openAnalytics;
  final VoidCallback? openPayouts;
  final String payoutsCaption;

  const _CommandGrid({
    required this.openMedia,
    required this.publishGig,
    this.gigCommandLabel = 'PUBLISH GIG',
    this.gigCommandIcon = Icons.add,
    required this.editProfile,
    required this.openAnalytics,
    required this.openPayouts,
    required this.payoutsCaption,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (publishGig != null)
        _Command(
          label: gigCommandLabel,
          icon: gigCommandIcon,
          onTap: publishGig!,
          primary: true,
        ),
      _Command(label: 'ADD MEDIA', icon: Icons.play_arrow, onTap: openMedia),
      _Command(label: 'ANALYTICS', icon: Icons.bar_chart, onTap: openAnalytics),
      if (editProfile != null)
        _Command(label: 'EDIT PROFILE', icon: Icons.edit, onTap: editProfile!),
      if (openPayouts != null)
        _Command(
          label: 'PAYOUTS',
          icon: Icons.account_balance_wallet,
          key: const Key('band-dash-payouts'),
          caption: payoutsCaption,
          onTap: openPayouts!,
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
        childAspectRatio: singleColumn ? 4.5 : 2.35,
        mainAxisExtent: openPayouts == null
            ? null
            : 64 + MediaQuery.textScalerOf(context).scale(36),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: actions.length,
      itemBuilder: (_, index) => _CommandTile(command: actions[index]),
    );
  }
}

class _Command {
  const _Command({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.key,
    this.caption,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final Key? key;
  final String? caption;
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({required this.command});

  final _Command command;

  @override
  Widget build(BuildContext context) {
    final foreground = command.primary ? Colors.white : context.epColors.ink;
    return Semantics(
      button: true,
      label: command.label,
      excludeSemantics: true,
      child: Material(
        color: command.primary ? Ep.brand : context.epColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: command.primary ? Ep.brand : context.epColors.border,
          ),
        ),
        child: InkWell(
          key:
              command.key ??
              ValueKey(
                'band-command-${command.label.toLowerCase().replaceAll(' ', '-')}',
              ),
          onTap: command.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(command.icon, color: foreground, size: 22),
                const SizedBox(height: 7),
                Text(
                  command.label,
                  style: Theme.of(
                    context,
                  ).textTheme.epLabel.copyWith(color: foreground),
                ),
                if (command.caption case final caption?)
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.epCaption.copyWith(color: foreground),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
