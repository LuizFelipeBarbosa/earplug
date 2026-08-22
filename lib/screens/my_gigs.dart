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
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Ep.blue,
                shape: BoxShape.circle,
              ),
              child: Text(
                profileInitials(profileName),
                style: epDisplay(size: 19, color: Colors.white),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: epDisplay(size: 19)),
                  Text(
                    '${app.gigsAttended} gigs attended · fan since $fanSince',
                    style: epText(size: 11.5, color: Ep.inkA(.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        EpCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          borderColor: Ep.whiteA(.16),
          onTap: () => showSwitcherSheet(context),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'SWITCH TO BAND VIEW',
                  style: epText(
                    size: 12,
                    weight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${app.myBandNames} ›',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: epText(
                    size: 11,
                    weight: FontWeight.w800,
                    color: Ep.link,
                  ),
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
              style: epText(size: 12.5, color: Ep.inkA(.45)),
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
            style: epText(size: 11.5, color: Ep.inkA(.4)),
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
            style: epText(size: 11.5, color: Ep.inkA(.4)),
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
              style: epText(size: 11.5, color: Ep.inkA(.4)),
            ),
          ),
        for (final p in app.history)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Ep.whiteA(.07))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    p.title,
                    style: epText(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: Ep.inkA(.75),
                    ),
                  ),
                ),
                Text(p.meta, style: epText(size: 11, color: Ep.inkA(.4))),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Your history powers new-vs-returning fan stats for bands — always aggregated, never named.',
          style: epText(size: 10.5, color: Ep.inkA(.35), height: 1.4),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: app.signOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'SIGN OUT',
              textAlign: TextAlign.center,
              style: epText(
                size: 11,
                weight: FontWeight.w800,
                letterSpacing: 1,
                color: Ep.inkA(.45),
              ),
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
    return GestureDetector(
      key: ValueKey('show-qr-${gig.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showQrDialog(context, gig, venue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: Ep.blue,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          'SHOW QR',
          style: epText(
            size: 8.5,
            weight: FontWeight.w900,
            letterSpacing: .4,
            color: Colors.white,
          ),
        ),
      ),
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
      child: Row(
        children: [
          GestureDetector(
            onTap: () => app.openBand(bandId),
            child: BandAvatar(
              band,
              size: 36,
              radius: 8,
              fontSize: 12,
              rotationDeg: 0,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: GestureDetector(
              onTap: () => app.openBand(bandId),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    band.name.toUpperCase(),
                    style: epText(size: 13, weight: FontWeight.w800),
                  ),
                  Text(
                    band.genreLine,
                    style: epText(size: 11, color: Ep.inkA(.5)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => app.toggleFollow(bandId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Ep.whiteA(.22)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'FOLLOWING ✓',
                style: epText(
                  size: 10,
                  weight: FontWeight.w800,
                  letterSpacing: .6,
                  color: Ep.inkA(.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
