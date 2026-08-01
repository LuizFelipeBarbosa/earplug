import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: context.read<AppState>().query);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Genre chips set the query from outside the text field.
    if (_controller.text != app.query) {
      _controller.text = app.query;
    }
    final q = app.query.trim().toLowerCase();
    final searching = q.isNotEmpty;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Ep.whiteA(.09))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SEARCH & EXPLORE', style: epDisplay(size: 20)),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                onChanged: app.setQuery,
                style: epText(size: 14),
                decoration: epInputDecoration('Bands, gigs, venues…'),
              ),
            ],
          ),
        ),
        Expanded(
          child: searching
              ? _SearchResults(app: app, q: q)
              : _BrowseRows(app: app),
        ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  final AppState app;
  final String q;

  const _SearchResults({required this.app, required this.q});

  @override
  Widget build(BuildContext context) {
    final bandIds = [
      for (final id in app.exploreBandIds)
        if (app.band(id) case final Band band)
          if (band.name.toLowerCase().contains(q) ||
              band.genres.any((genre) => genre.toLowerCase().contains(q)))
            id,
    ];
    final gigs = app.allGigs.where((g) {
      return g.title.toLowerCase().contains(q) ||
          app.venue(g.venueId).name.toLowerCase().contains(q) ||
          g.genres.any((t) => t.contains(q));
    }).toList();
    final venues = app.venues.where((venue) {
      return venue.name.toLowerCase().contains(q) ||
          venue.area.toLowerCase().contains(q) ||
          venue.addr.toLowerCase().contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, tabBarClearance),
      children: [
        const SectionLabel('BANDS'),
        const SizedBox(height: 6),
        if (bandIds.isEmpty)
          Text('No bands found.', style: epText(size: 12, color: Ep.inkA(.4))),
        for (final id in bandIds) ...[
          _BandRow(bandId: id, app: app),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 8),
        const SectionLabel('VENUES'),
        const SizedBox(height: 6),
        if (venues.isEmpty)
          Text('No venues found.', style: epText(size: 12, color: Ep.inkA(.4))),
        for (final venue in venues) ...[
          _VenueRow(venue: venue, app: app),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 8),
        const SectionLabel('GIGS'),
        const SizedBox(height: 6),
        if (gigs.isEmpty)
          Text('No gigs found.', style: epText(size: 12, color: Ep.inkA(.4))),
        for (final g in gigs) ...[
          _GigRow(gig: g, app: app),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _BandRow extends StatelessWidget {
  final String bandId;
  final AppState app;

  const _BandRow({required this.bandId, required this.app});

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();
    return EpCard(
      padding: const EdgeInsets.all(9),
      onTap: () => app.openBand(bandId),
      child: Row(
        children: [
          BandAvatar(band, size: 36, radius: 8, fontSize: 12, rotationDeg: 0),
          const SizedBox(width: 11),
          Expanded(
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
        ],
      ),
    );
  }
}

class _GigRow extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _GigRow({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: const EdgeInsets.all(9),
      onTap: () => app.openGig(gig.id),
      child: Row(
        children: [
          GigFlyer(
            gig,
            app.flyer(gig.flyKey),
            width: 34,
            height: 44,
            rotationDeg: -2,
            radius: 4,
            shadow: false,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gig.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: epText(size: 13, weight: FontWeight.w800),
                ),
                Text(
                  '${gig.dateShort} · ${app.venue(gig.venueId).name}',
                  style: epText(size: 11, color: Ep.inkA(.5)),
                ),
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

class _BrowseRows extends StatelessWidget {
  final AppState app;

  const _BrowseRows({required this.app});

  @override
  Widget build(BuildContext context) {
    final gigs = app.allGigs;
    final tonight = [
      ...gigs.where((g) => g.when == GigWhen.tonight),
      ...gigs.where((g) => g.when == GigWhen.week).take(3),
    ];
    final free = gigs.where((g) => g.free && g.when != GigWhen.later).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, tabBarClearance),
      children: [
        const SectionLabel('GENRES'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final t in kGenres)
              EpChip(label: t, active: false, onTap: () => app.setQuery(t)),
          ],
        ),
        const SizedBox(height: 18),
        const SectionLabel('TONIGHT NEAR YOU', blue: true),
        const SizedBox(height: 8),
        _FlyerRail(gigs: tonight, app: app, tilt: -1.2),
        const SizedBox(height: 18),
        const SectionLabel('FREE THIS WEEK', blue: true),
        const SizedBox(height: 8),
        _FlyerRail(gigs: free, app: app, tilt: 1.2, freeTag: true),
        const SizedBox(height: 18),
        const SectionLabel('BANDS ON EARPLUG'),
        const SizedBox(height: 8),
        SizedBox(
          height: 118,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final id in app.exploreBandIds)
                _BandTile(bandId: id, app: app),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _VenueRows(app: app),
      ],
    );
  }
}

class _VenueRows extends StatelessWidget {
  const _VenueRows({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final venues = app.venues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('VENUES'),
        const SizedBox(height: 8),
        if (venues.isNotEmpty)
          for (final venue in venues) ...[
            _VenueRow(venue: venue, app: app),
            const SizedBox(height: 6),
          ]
        else if (app.venueStatus == DataStatus.connecting)
          Text('Loading venues…', style: epText(size: 11.5, color: Ep.inkA(.4)))
        else if (app.venueStatus == DataStatus.error) ...[
          Text(
            "Couldn't load venues.",
            style: epText(size: 11.5, color: Ep.inkA(.4)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 120,
            child: EpButton(
              'RETRY',
              kind: EpButtonKind.outline,
              padding: const EdgeInsets.symmetric(vertical: 10),
              onTap: app.retryVenues,
            ),
          ),
        ] else
          Text(
            'No venues listed yet.',
            style: epText(size: 11.5, color: Ep.inkA(.4)),
          ),
      ],
    );
  }
}

class _VenueRow extends StatelessWidget {
  const _VenueRow({required this.venue, required this.app});

  final Venue venue;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: const EdgeInsets.all(9),
      onTap: () => app.setQuery(venue.name),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venue.name.toUpperCase(),
                  style: epText(size: 13, weight: FontWeight.w800),
                ),
                Text(
                  '${venue.addr} · ${venue.area}',
                  style: epText(size: 11, color: Ep.inkA(.5)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            app.distanceOf(venue),
            style: epText(size: 11, color: Ep.inkA(.5)),
          ),
        ],
      ),
    );
  }
}

class _FlyerRail extends StatelessWidget {
  final List<Gig> gigs;
  final AppState app;
  final double tilt;
  final bool freeTag;

  const _FlyerRail({
    required this.gigs,
    required this.app,
    required this.tilt,
    this.freeTag = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 186,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          for (final g in gigs)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => app.openGig(g.id),
                child: SizedBox(
                  width: 118,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GigFlyer(
                            g,
                            app.flyer(g.flyKey),
                            width: 118,
                            height: 150,
                            rotationDeg: tilt,
                            radius: 8,
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  g.title.toUpperCase(),
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: epDisplay(
                                    size: 12,
                                    color: app.flyer(g.flyKey).fg,
                                    height: 1.1,
                                  ),
                                ),
                                Text(
                                  g.dateShort,
                                  style: epText(
                                    size: 9,
                                    weight: FontWeight.w800,
                                    letterSpacing: .5,
                                    color: app
                                        .flyer(g.flyKey)
                                        .fg
                                        .withValues(alpha: .85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (freeTag)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Transform.rotate(
                                angle: 6 * 3.14159 / 180,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Ep.blue,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    'FREE',
                                    style: epText(
                                      size: 9,
                                      weight: FontWeight.w900,
                                      letterSpacing: .8,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        app.venue(g.venueId).name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: epText(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: Ep.inkA(.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BandTile extends StatelessWidget {
  final String bandId;
  final AppState app;

  const _BandTile({required this.bandId, required this.app});

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => app.openBand(bandId),
      child: SizedBox(
        width: 86,
        child: Column(
          children: [
            BandAvatar(band, size: 64, radius: 13, fontSize: 20),
            const SizedBox(height: 7),
            Text(
              band.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: epText(size: 10.5, weight: FontWeight.w800, height: 1.2),
            ),
            const SizedBox(height: 2),
            if (band.genres.isNotEmpty)
              Text(
                band.genres.first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: epText(size: 9.5, color: Ep.inkA(.45)),
              ),
          ],
        ),
      ),
    );
  }
}
