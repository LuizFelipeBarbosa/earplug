import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/sheets.dart';

class MyGigsScreen extends StatelessWidget {
  const MyGigsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final profile = app.profile;
    final profileName = profile?.name.trim();
    final displayName = profileName == null || profileName.isEmpty
        ? 'YOUR PROFILE'
        : profileName.toUpperCase();
    final fanSince = profile == null ? '—' : monthLabel(profile.createdAt);
    final upcoming = [
      for (final id in app.rsvps)
        if (app.gig(id) case final Gig g) g,
    ];
    final savedGigs = [
      for (final id in app.saved)
        if (app.gig(id) case final Gig g) g,
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Row(
          children: [
            EpProfileAvatar(name: profileName, size: 56, radius: 16),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.epSectionHeading,
                  ),
                  Text(
                    '${app.gigsAttended} gigs attended · fan since $fanSince',
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        EpCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          onTap: () => showSwitcherSheet(context),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'SWITCH TO BAND VIEW',
                  style: Theme.of(
                    context,
                  ).textTheme.epLabel.copyWith(letterSpacing: .8),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${app.myBandNames} ›',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(
                    context,
                  ).textTheme.epLabel.copyWith(color: Ep.accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel("UPCOMING — YOU'RE GOING", blue: true),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          DashedBox(
            child: Text(
              'No RSVPs yet — go find a show.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.epBody.copyWith(color: Ep.contentSecondary),
            ),
          ),
        for (final g in upcoming) ...[
          FanEventCard(
            gig: g,
            app: app,
            trailingAction: _QrAction(gig: g, venue: app.venue(g.venueId)),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const SectionLabel('SAVED'),
        const SizedBox(height: 8),
        if (savedGigs.isEmpty)
          Text(
            'Nothing saved — tap the bookmark on a gig to stash it here.',
            style: Theme.of(context).textTheme.epCaption,
          ),
        for (final g in savedGigs) ...[
          FanEventCard(gig: g, app: app),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const SectionLabel('FOLLOWING'),
        const SizedBox(height: 8),
        if (app.follows.isEmpty)
          Text(
            'Not following any bands yet.',
            style: Theme.of(context).textTheme.epCaption,
          ),
        for (final id in app.follows.toList())
          if (app.band(id) != null) ...[
            _FollowRow(bandId: id, app: app),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        const SectionLabel('HISTORY'),
        const SizedBox(height: 6),
        if (app.history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No gigs on record yet — RSVP and show up, this fills itself in.',
              style: Theme.of(context).textTheme.epCaption,
            ),
          ),
        for (final p in app.history)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ep.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    p.title,
                    style: Theme.of(context).textTheme.epBody,
                  ),
                ),
                const SizedBox(width: 8),
                Text(p.meta, style: Theme.of(context).textTheme.epCaption),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Your history powers new-vs-returning fan stats for bands — always aggregated, never named.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: app.signOut,
          child: Text(
            'SIGN OUT',
            style: Theme.of(context).textTheme.epLabel.copyWith(
              letterSpacing: 1,
              color: Ep.contentSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _QrAction extends StatelessWidget {
  const _QrAction({required this.gig, required this.venue});

  final Gig gig;
  final Venue venue;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: ValueKey('show-qr-${gig.id}'),
      onPressed: () => showQrDialog(context, gig, venue),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 9),
        ),
        textStyle: WidgetStatePropertyAll(
          Theme.of(
            context,
          ).textTheme.epLabel.copyWith(fontSize: 9, letterSpacing: .4),
        ),
      ),
      child: const Text('SHOW QR'),
    );
  }
}

class _FollowRow extends StatelessWidget {
  final String bandId;
  final AppState app;

  const _FollowRow({required this.bandId, required this.app});

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();
    return EpCard(
      padding: const EdgeInsets.all(9),
      onTap: () => app.openBand(bandId),
      child: Row(
        children: [
          BandAvatar(band, size: 36, radius: 8, fontSize: 12),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  band.name.toUpperCase(),
                  style: Theme.of(context).textTheme.epLabel,
                ),
                Text(
                  band.genreLine,
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => app.toggleFollow(bandId),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10),
              ),
              textStyle: WidgetStatePropertyAll(
                Theme.of(
                  context,
                ).textTheme.epLabel.copyWith(fontSize: 10, letterSpacing: .4),
              ),
            ),
            child: const Text('FOLLOWING ✓'),
          ),
        ],
      ),
    );
  }
}
