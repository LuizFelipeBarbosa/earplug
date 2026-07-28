import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/map_view.dart';

class GigDetailScreen extends StatelessWidget {
  final String gigId;

  const GigDetailScreen({super.key, required this.gigId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final gig = app.gig(gigId);
    if (gig == null) return const SizedBox.shrink();
    final venue = app.venue(gig.venueId);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _Hero(gig: gig, app: app),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoCards(gig: gig),
                  const SizedBox(height: 16),
                  Text(gig.desc, style: epText(size: 13.5, color: Ep.inkA(.75), height: 1.5)),
                  const SizedBox(height: 16),
                  const SectionLabel('LINEUP'),
                  const SizedBox(height: 8),
                  for (final bandId in gig.lineup) ...[
                    _LineupRow(bandId: bandId, app: app),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  const SectionLabel('VENUE'),
                  const SizedBox(height: 8),
                  _VenueCard(venue: venue, app: app),
                  const SizedBox(height: 16),
                  const SectionLabel("WHO'S GOING"),
                  const SizedBox(height: 8),
                  _WhosGoing(gig: gig, app: app),
                ],
              ),
            ),
          ],
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _CtaBar(gig: gig, app: app)),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _Hero({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    final fly = app.flyer(gig.flyKey);
    final venue = app.venue(gig.venueId);
    final lineupLine = gig.lineup
        .map((id) => app.band(id)?.name ?? 'TBA')
        .join(' · ')
        .toUpperCase();
    final topPad = headerTopPad(context);

    return FlyerBox(
      style: fly,
      height: 330,
      radius: 0,
      shadow: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, topPad + 8, 22, 20),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(gig.title.toUpperCase(),
                      style: epDisplay(size: 34, color: fly.fg, letterSpacing: -.5, height: .98)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${gig.dateShort} · ${venue.name.toUpperCase()}',
                        style: epDisplay(size: 15, color: fly.fg)),
                    const SizedBox(height: 4),
                    Text(lineupLine,
                        style: epText(
                            size: 11,
                            weight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: fly.fg.withValues(alpha: .75))),
                  ],
                ),
              ],
            ),
            Positioned(
              left: -8,
              top: -2,
              child: GestureDetector(
                onTap: app.back,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_left, size: 22, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              right: -8,
              top: -2,
              child: GestureDetector(
                onTap: () => app.say('Link copied — earplug.app/g/${gig.id}'),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('SHARE ↗',
                      style: epText(
                          size: 11, weight: FontWeight.w800, letterSpacing: 1, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCards extends StatelessWidget {
  final Gig gig;

  const _InfoCards({required this.gig});

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, {Color? valueColor}) {
      return Expanded(
        child: EpCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: epText(
                      size: 10, weight: FontWeight.w800, letterSpacing: 1.2, color: Ep.inkA(.45))),
              const SizedBox(height: 3),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: epText(size: 13, weight: FontWeight.w800, color: valueColor ?? Ep.ink)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell('DATE', gig.dateShort),
        const SizedBox(width: 8),
        cell('DOORS / SET', gig.time),
        const SizedBox(width: 8),
        cell('PRICE', gig.priceLabel, valueColor: gig.free ? Ep.link : Ep.ink),
      ],
    );
  }
}

class _LineupRow extends StatelessWidget {
  final String bandId;
  final AppState app;

  const _LineupRow({required this.bandId, required this.app});

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();
    return EpCard(
      padding: const EdgeInsets.all(10),
      onTap: () => app.openBand(bandId),
      child: Row(
        children: [
          BandAvatar(band),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(band.name.toUpperCase(),
                    style: epText(size: 13.5, weight: FontWeight.w800, letterSpacing: .3)),
                Text(band.genreLine, style: epText(size: 11.5, color: Ep.inkA(.55))),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: Ep.inkA(.4)),
        ],
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  final Venue venue;
  final AppState app;

  const _VenueCard({required this.venue, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Ep.card,
        border: Border.all(color: Ep.whiteA(.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          VenueMiniMap(venue: venue),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venue.name.toUpperCase(),
                          style: epText(size: 13.5, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${venue.addr} · ${venue.area}',
                          style: epText(size: 11.5, color: Ep.inkA(.55))),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => app.say('Opening directions… (demo)'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: Ep.whiteA(.25)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('DIRECTIONS ↗',
                        style: epText(size: 11, weight: FontWeight.w800, letterSpacing: .8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhosGoing extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _WhosGoing({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    final going = gig.going + (app.rsvps.contains(gig.id) ? 1 : 0);
    final followedOnBill = app.follows.where(gig.lineup.contains).toList();
    final socialLine = !app.authed
        ? 'Log in to see which of your people are going.'
        : followedOnBill.isEmpty
            ? '3 people you know are going.'
            : 'Bands you follow on this bill: '
                '${followedOnBill.map((id) => app.band(id)!.name).join(', ')}. '
                'Plus 3 people you know.';

    return EpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$going+ going', style: epDisplay(size: 22)),
          const SizedBox(height: 5),
          Text(socialLine, style: epText(size: 12, color: Ep.inkA(.6), height: 1.5)),
          const SizedBox(height: 8),
          Text('Attendance stays vague on purpose — no public list, ever.',
              style: epText(size: 10.5, letterSpacing: .3, color: Ep.inkA(.38))),
        ],
      ),
    );
  }
}

class _CtaBar extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _CtaBar({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    final isRsvpd = app.rsvps.contains(gig.id);
    final external = gig.tix == Ticketing.external;
    final tixNote = external
        ? 'External ticketing'
        : gig.free
            ? 'Free — RSVP for headcount'
            : 'Pay at the door · RSVP holds nothing';

    final Widget button;
    if (external) {
      button = EpButton('GET TICKETS ↗',
          kind: EpButtonKind.light,
          fontSize: 14,
          padding: const EdgeInsets.symmetric(vertical: 16),
          onTap: () => app.say('Opening ticket site… (demo)'));
    } else if (isRsvpd) {
      button = EpButton('GOING ✓',
          kind: EpButtonKind.outline,
          fontSize: 14,
          onTap: () => app.toggleRsvp(gig.id));
    } else {
      button = EpButton("RSVP — I'M IN",
          fontSize: 14,
          glow: true,
          padding: const EdgeInsets.symmetric(vertical: 16),
          onTap: () => app.requestRsvp(gig.id));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: [0, .75, 1],
          colors: [Ep.bg, Ep.bg, Color(0x000A0A0C)],
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(gig.priceLabel,
                  style: epDisplay(size: 17, color: gig.free ? Ep.link : Ep.ink)),
              Text(tixNote,
                  style: epText(size: 10, weight: FontWeight.w700, letterSpacing: .5, color: Ep.inkA(.5))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(child: button),
        ],
      ),
    );
  }
}
