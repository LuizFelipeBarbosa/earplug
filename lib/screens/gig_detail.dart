import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/map_view.dart';

Future<void> _openExternal(AppState app, String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!ok) app.say("Couldn't open that link.");
}

class GigDetailScreen extends StatelessWidget {
  final String gigId;

  const GigDetailScreen({super.key, required this.gigId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final gig = app.gig(gigId);
    if (gig == null) {
      if (app.publicGigError(gigId) case final error?) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: epText(color: Ep.contentSecondary),
                ),
                const SizedBox(height: 16),
                EpButton('TRY AGAIN', onTap: () => app.retryPublicGig(gigId)),
              ],
            ),
          ),
        );
      }
      if (app.publicGigMissing(gigId)) {
        return Center(
          child: Text(
            'THIS GIG IS NO LONGER AVAILABLE',
            style: epText(color: Ep.contentSecondary),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final venue = app.venue(gig.venueId);
    final performers = gig.performers.isNotEmpty
        ? gig.performers
        : [
            for (var index = 0; index < gig.lineup.length; index++)
              if (app.band(gig.lineup[index]) case final band?)
                GigPerformer(
                  id: '',
                  kind: GigPerformerKind.band,
                  name: band.name,
                  role: index == 0
                      ? GigPerformerRole.headliner
                      : GigPerformerRole.support,
                  bandId: band.id,
                ),
          ];

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _Hero(gig: gig, app: app, performers: performers),
            if (gig.lifecycle == GigLifecycle.cancelled)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Ep.warning.withValues(alpha: .12),
                  border: Border.all(color: Ep.warning),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'THIS GIG HAS BEEN CANCELLED',
                  textAlign: TextAlign.center,
                  style: epText(
                    size: 12,
                    weight: FontWeight.w900,
                    letterSpacing: .8,
                    color: Ep.warning,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoCards(gig: gig),
                  const SizedBox(height: 16),
                  Text(
                    gig.desc,
                    style: epText(
                      size: 13.5,
                      color: Ep.contentSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('LINEUP'),
                  const SizedBox(height: 8),
                  for (final performer in performers) ...[
                    _LineupRow(performer: performer, app: app),
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _CtaBar(gig: gig, app: app),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final Gig gig;
  final AppState app;
  final List<GigPerformer> performers;

  const _Hero({required this.gig, required this.app, required this.performers});

  @override
  Widget build(BuildContext context) {
    final fly = app.flyer(gig.flyKey);
    final venue = app.venue(gig.venueId);
    final lineupLine = performers
        .map((performer) => performer.name)
        .join(' · ')
        .toUpperCase();
    final topPad = headerTopPad(context);

    return GigFlyer(
      gig,
      fly,
      height: 330,
      radius: 0,
      shadow: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, topPad + 8, 22, 20),
        child: Stack(
          key: const ValueKey('gig-detail-hero-content'),
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    gig.title.toUpperCase(),
                    style: epDisplay(
                      size: 34,
                      color: fly.fg,
                      letterSpacing: -.5,
                      height: .98,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${gig.dateShort} · ${venue.name.toUpperCase()}',
                      style: epDisplay(size: 15, color: fly.fg),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lineupLine,
                      style: epText(
                        size: 11,
                        weight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: fly.fg.withValues(alpha: .75),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: -8,
              top: -2,
              child: CircleIconButton(
                tooltip: 'Back',
                onTap: app.back,
                background: Colors.black.withValues(alpha: .55),
                bordered: false,
              ),
            ),
            Positioned(
              right: -8,
              top: -2,
              child: Row(
                children: [
                  _HeroAction(
                    key: ValueKey('gig-detail-save-${gig.id}'),
                    tooltip: app.saved.contains(gig.id)
                        ? 'Remove saved event'
                        : 'Save event',
                    onTap: () => app.requestSave(gig.id),
                    child: Icon(
                      app.saved.contains(gig.id)
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _HeroAction(
                    key: ValueKey('gig-detail-share-${gig.id}'),
                    tooltip: 'Share event',
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: 'https://earplug.app/g/${gig.id}'),
                      );
                      app.say('Link copied: earplug.app/g/${gig.id}');
                    },
                    child: Text(
                      'SHARE ↗',
                      style: epText(
                        size: 11,
                        weight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    super.key,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(99),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: child,
          ),
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
              Text(
                label,
                style: epText(
                  size: 10,
                  weight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Ep.contentDisabled,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: epText(
                  size: 13,
                  weight: FontWeight.w800,
                  color: valueColor ?? Ep.contentPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            cell('DATE', gig.dateShort),
            const SizedBox(width: 8),
            cell('DOORS / SET', gig.time),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            cell(
              'PRICE',
              gig.priceLabel,
              valueColor: gig.free ? Ep.accent : Ep.contentPrimary,
            ),
            const SizedBox(width: 8),
            cell('AGE', gig.ageRequirement.label),
          ],
        ),
      ],
    );
  }
}

class _LineupRow extends StatelessWidget {
  final GigPerformer performer;
  final AppState app;

  const _LineupRow({required this.performer, required this.app});

  @override
  Widget build(BuildContext context) {
    final band = performer.bandId == null ? null : app.band(performer.bandId!);
    return EpCard(
      padding: const EdgeInsets.all(10),
      onTap: band == null ? null : () => app.openBand(band.id),
      child: Row(
        children: [
          if (band != null)
            BandAvatar(band)
          else
            const CircleAvatar(child: Icon(Icons.music_note, size: 18)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  performer.name.toUpperCase(),
                  style: epText(
                    size: 13.5,
                    weight: FontWeight.w800,
                    letterSpacing: .3,
                  ),
                ),
                Text(
                  band?.genreLine ?? performer.role.name.toUpperCase(),
                  style: epText(size: 11.5, color: Ep.contentSecondary),
                ),
              ],
            ),
          ),
          if (band != null)
            const Icon(Icons.chevron_right, color: Ep.contentSecondary),
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
    return EpCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => app.openVenue(venue.id),
              child: VenueMiniMap(venue: venue),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => app.openVenue(venue.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              venue.name.toUpperCase(),
                              style: epText(
                                size: 13.5,
                                weight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${venue.addr} · ${venue.area}',
                              style: epText(
                                size: 11.5,
                                color: Ep.contentSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _openExternal(
                    app,
                    'https://www.google.com/maps/search/?api=1&query='
                    '${venue.point.latitude},${venue.point.longitude}',
                  ),
                  child: const Text('DIRECTIONS ↗'),
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
    final followedBandNames = [
      for (final id in followedOnBill)
        if (app.band(id) case final Band band) band.name,
    ];
    final socialLine = !app.authed
        ? 'Log in to see when bands you follow are on the bill.'
        : followedBandNames.isEmpty
        ? 'None of the bands you follow are on this bill yet.'
        : 'Bands you follow on this bill: '
              '${followedBandNames.join(', ')}.';

    return EpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$going+ going', style: epDisplay(size: 22)),
          const SizedBox(height: 5),
          Text(
            socialLine,
            style: epText(size: 12, color: Ep.contentSecondary, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Attendance stays vague on purpose. There is no public list.',
            style: epText(
              size: 10.5,
              letterSpacing: .3,
              color: Ep.contentDisabled,
            ),
          ),
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
    if (gig.lifecycle == GigLifecycle.cancelled) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        color: Ep.background,
        child: EpButton(
          'GIG CANCELLED',
          kind: EpButtonKind.disabled,
          onTap: null,
        ),
      );
    }
    final isRsvpd = app.rsvps.contains(gig.id);
    final external = gig.tix == Ticketing.external;
    final tixNote = external
        ? 'External ticketing'
        : gig.free
        ? 'Free. RSVP for headcount'
        : 'Pay at the door · RSVP holds nothing';

    final Widget button;
    if (external) {
      button = EpButton(
        'GET TICKETS ↗',
        kind: EpButtonKind.light,
        fontSize: 14,
        padding: const EdgeInsets.symmetric(vertical: 16),
        onTap: () {
          final url = gig.externalUrl;
          if (url == null) {
            app.say('No ticket link listed for this gig.');
          } else {
            _openExternal(app, url);
          }
        },
      );
    } else if (isRsvpd) {
      button = EpButton(
        'GOING ✓',
        kind: EpButtonKind.outline,
        fontSize: 14,
        onTap: () => app.toggleRsvp(gig.id),
      );
    } else {
      button = EpButton(
        "RSVP: I'M IN",
        fontSize: 14,
        padding: const EdgeInsets.symmetric(vertical: 16),
        onTap: () => app.requestRsvp(gig.id),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: [0, .75, 1],
          colors: [Ep.background, Ep.background, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gig.priceLabel,
                  style: epDisplay(
                    size: 17,
                    color: gig.free ? Ep.accent : Ep.contentPrimary,
                  ),
                ),
                Text(
                  tixNote,
                  style: epText(
                    size: 10,
                    weight: FontWeight.w700,
                    letterSpacing: .5,
                    color: Ep.contentSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: button),
        ],
      ),
    );
  }
}
