import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../demo_data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

class MyGigsScreen extends StatelessWidget {
  const MyGigsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final upcoming = [
      for (final id in app.rsvps)
        if (app.gig(id) case final Gig g) g,
    ];
    final savedGigs = [
      for (final id in app.saved)
        if (app.gig(id) case final Gig g) g,
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, tabBarClearance),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Ep.blue, shape: BoxShape.circle),
              child: Text('SR', style: epDisplay(size: 19, color: Colors.white)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SAM REYES', style: epDisplay(size: 19)),
                  Text('${app.attended} gigs attended · fan since Jul 2026',
                      style: epText(size: 11.5, color: Ep.inkA(.5))),
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
              Text('SWITCH TO BAND VIEW',
                  style: epText(size: 12, weight: FontWeight.w800, letterSpacing: .8)),
              Text('${app.myBandNames} ›',
                  style: epText(size: 11, weight: FontWeight.w800, color: Ep.link)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel("UPCOMING — YOU'RE GOING", blue: true),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          DashedBox(
            child: Text('No RSVPs yet — go find a show.',
                textAlign: TextAlign.center, style: epText(size: 12.5, color: Ep.inkA(.45))),
          ),
        for (final g in upcoming) ...[
          _UpcomingCard(gig: g, app: app),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const SectionLabel('SAVED'),
        const SizedBox(height: 8),
        for (final g in savedGigs) ...[
          _SavedRow(gig: g, app: app),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const SectionLabel('FOLLOWING'),
        const SizedBox(height: 8),
        for (final id in app.follows.toList()) ...[
          _FollowRow(bandId: id, app: app),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const SectionLabel('HISTORY'),
        const SizedBox(height: 6),
        for (final p in DemoData.fanHistory)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
            decoration:
                BoxDecoration(border: Border(bottom: BorderSide(color: Ep.whiteA(.07)))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(p.title,
                      style: epText(size: 12.5, weight: FontWeight.w700, color: Ep.inkA(.75))),
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
      ],
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _UpcomingCard({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    return EpCard(
      padding: const EdgeInsets.all(11),
      radius: 13,
      borderColor: Ep.whiteA(.12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => app.openGig(gig.id),
            child: FlyerBox(
                style: app.flyer(gig.flyKey),
                width: 44,
                height: 58,
                rotationDeg: -2,
                radius: 5,
                shadow: false),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: GestureDetector(
              onTap: () => app.openGig(gig.id),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(gig.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: epText(size: 13, weight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${gig.dateShort} · ${venue.name}',
                      style: epText(size: 11.5, color: Ep.inkA(.55))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showQrDialog(context, gig, venue),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: Ep.blue,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text('SHOW QR',
                  style: epText(
                      size: 10.5, weight: FontWeight.w900, letterSpacing: .8, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _SavedRow({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: const EdgeInsets.all(10),
      onTap: () => app.openGig(gig.id),
      child: Row(
        children: [
          FlyerBox(
              style: app.flyer(gig.flyKey),
              width: 38,
              height: 50,
              rotationDeg: -2,
              radius: 4,
              shadow: false),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gig.title.toUpperCase(),
                    style: epText(size: 12.5, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${gig.dateShort} · ${app.venue(gig.venueId).name}',
                    style: epText(size: 11, color: Ep.inkA(.5))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PriceBadge(gig),
        ],
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
    final band = app.band(bandId)!;
    return EpCard(
      padding: const EdgeInsets.all(9),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => app.openBand(bandId),
            child: BandAvatar(band, size: 36, radius: 8, fontSize: 12, rotationDeg: 0),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: GestureDetector(
              onTap: () => app.openBand(bandId),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(band.name.toUpperCase(),
                      style: epText(size: 13, weight: FontWeight.w800)),
                  Text(band.genreLine, style: epText(size: 11, color: Ep.inkA(.5))),
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
              child: Text('FOLLOWING ✓',
                  style: epText(
                      size: 10, weight: FontWeight.w800, letterSpacing: .6, color: Ep.inkA(.7))),
            ),
          ),
        ],
      ),
    );
  }
}
