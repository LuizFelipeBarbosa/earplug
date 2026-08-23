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
    final hasProfileImage =
        band.heroUrl?.isNotEmpty == true ||
        media.photosFor(band.id).any((item) => item.isHero);
    final tasks = [
      _BandTask(
        label: 'Add a profile image',
        complete: hasProfileImage,
        onTap: app.openBandMedia,
      ),
      _BandTask(
        label: 'Write a short bio',
        complete: app.bioFor(band.id).trim().isNotEmpty,
        onTap: () => app.resetTo(Screen.bandEdit),
      ),
      _BandTask(
        label: 'Add a band link',
        complete:
            app.linkIgFor(band.id).trim().isNotEmpty ||
            app.linkBcFor(band.id).trim().isNotEmpty ||
            app.linkYtFor(band.id).trim().isNotEmpty,
        onTap: () => app.resetTo(Screen.bandEdit),
      ),
      _BandTask(
        label: 'Post a music clip',
        complete: clips.isNotEmpty,
        onTap: app.openBandMedia,
      ),
      _BandTask(
        label: 'Publish a gig',
        complete:
            mine.isNotEmpty ||
            band.past.isNotEmpty ||
            (app.bandHistory(band.id)?.gigs.isNotEmpty ?? false),
        onTap: app.startGigCreate,
      ),
    ];
    final remainingTasks = tasks.where((task) => !task.complete).toList();

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
          publishGig: app.startGigCreate,
          openAnalytics: () => app.resetTo(Screen.analytics),
        ),
        if (next != null) ...[
          const SizedBox(height: 14),
          const SectionLabel('NEXT UP', blue: true),
          const SizedBox(height: 8),
          _NextUpCard(gig: next, app: app),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(child: SectionLabel('BAND CHECKLIST')),
            const SizedBox(width: 8),
            Text(
              '${tasks.length - remainingTasks.length} OF ${tasks.length} DONE',
              style: Theme.of(context).textTheme.epCaption,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (remainingTasks.isEmpty)
          const EpCard(
            variant: EpCardVariant.selected,
            child: Text('Your band profile is ready for the next show.'),
          )
        else
          for (final task in remainingTasks) _BandTaskRow(task: task),
      ],
    );
  }
}

class _BandTask {
  final String label;
  final bool complete;
  final VoidCallback onTap;

  const _BandTask({
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
        onTap: task.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Ep.border)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.radio_button_unchecked,
                size: 16,
                color: Ep.accent,
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
  final VoidCallback publishGig;
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
      _ActionButton(label: '+ PUBLISH GIG', filled: true, onTap: publishGig),
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
