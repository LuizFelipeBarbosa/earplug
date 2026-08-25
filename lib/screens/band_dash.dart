import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

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
                          Text(
                            '${band.name.toUpperCase()} ▾',
                            style: epDisplay(size: 16, height: 1),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'MANAGING · ${app.roleFor(band.id).toUpperCase()}',
                            style: epText(
                              size: 10,
                              weight: FontWeight.w800,
                              letterSpacing: 1,
                              color: Ep.accent,
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
            OutlinedButton(
              onPressed: app.toFanView,
              child: const Text('DISCOVER'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            if (isAdmin) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: app.openBandEditor,
                  child: const Text('Edit profile'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton(
                onPressed: app.previewPublicProfile,
                child: const Text('Preview public profile'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            EpStatCard(
              label: 'FOLLOWERS',
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
        const SizedBox(height: 14),
        _DashboardActions(
          openMedia: app.openBandMedia,
          publishGig: isAdmin ? app.startGigCreate : null,
          openAnalytics: () => app.resetTo(Screen.analytics),
        ),
        if (next != null) ...[
          const SizedBox(height: 14),
          const SectionLabel('NEXT UP', blue: true),
          const SizedBox(height: 8),
          _NextUpCard(gig: next, app: app),
        ],
        if (isAdmin) ...[
          const SizedBox(height: 14),
          _SetupChecklist(app: app, bandId: band.id),
          const SizedBox(height: 14),
          _DiscoveryReadinessCard(app: app, bandId: band.id),
        ],
      ],
    );
  }
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
          const SectionLabel('DISCOVERY READINESS', blue: true),
          const SizedBox(height: 8),
          if (app.discoveryReadinessLoadingFor(bandId))
            const Center(child: CircularProgressIndicator())
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => app.refreshBandDiscoveryReadiness(bandId),
                child: const Text('Retry discovery readiness'),
              ),
            ),
        ],
      );
    }

    final showAction = readiness.relevantShow == null
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
              const Expanded(
                child: SectionLabel('DISCOVERY READINESS', blue: true),
              ),
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
                color: window.active ? Ep.success : Ep.contentSecondary,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(
              task.complete ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: task.complete ? Ep.success : Ep.accent,
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
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel('SETUP CHECKLIST')),
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
                      child: const Text('Retry setup checklist'),
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
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Ep.border)),
          ),
          child: Row(
            children: [
              Icon(
                task.complete
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 16,
                color: task.complete ? Ep.success : Ep.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.label,
                  style: Theme.of(context).textTheme.epBody,
                ),
              ),
              const Icon(Icons.chevron_right, color: Ep.contentSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return filled
        ? FilledButton(onPressed: onTap, child: Text(label))
        : OutlinedButton(onPressed: onTap, child: Text(label));
  }
}

class _DashboardActions extends StatelessWidget {
  final VoidCallback openMedia;
  final VoidCallback? publishGig;
  final VoidCallback openAnalytics;

  const _DashboardActions({
    required this.openMedia,
    required this.publishGig,
    required this.openAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionButton(label: '▶ ADD MEDIA', onTap: openMedia),
      if (publishGig != null)
        _ActionButton(label: '+ PUBLISH GIG', filled: true, onTap: publishGig!),
      _ActionButton(label: '▦ ANALYTICS', onTap: openAnalytics),
    ];

    if (MediaQuery.textScalerOf(context).scale(1) > 1.25) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            actions[index],
            if (index < actions.length - 1) const SizedBox(height: 8),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          Expanded(child: actions[index]),
          if (index < actions.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _NextUpCard extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _NextUpCard({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: const EdgeInsets.all(12),
      radius: 13,
      onTap: () => app.openGig(gig.id),
      child: Row(
        children: [
          GigFlyer(
            gig,
            app.flyer(gig.flyKey),
            width: 46,
            height: 60,
            radius: 5,
            shadow: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gig.title.toUpperCase(),
                  style: epText(size: 13.5, weight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${gig.dateShort} · ${app.venue(gig.venueId).name}',
                  style: Theme.of(context).textTheme.epCaption,
                ),
                const SizedBox(height: 3),
                Text(
                  '${app.rsvpCount(gig)} RSVPs · counting live',
                  style: epText(
                    size: 11,
                    weight: FontWeight.w800,
                    color: Ep.accent,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Ep.contentSecondary),
        ],
      ),
    );
  }
}
