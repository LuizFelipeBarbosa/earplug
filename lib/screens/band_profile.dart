import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BandProfileScreen extends StatelessWidget {
  final String bandId;

  const BandProfileScreen({super.key, required this.bandId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();

    final vids = app.videosFor(bandId);
    final pinned = vids.firstWhere((v) => v.pinned, orElse: () => vids.first);
    final clips = vids.where((v) => v != pinned).take(4).toList();
    final upcoming = [
      for (final id in band.upcoming)
        if (app.gig(id) case final Gig g) g,
    ];
    final following = app.follows.contains(bandId);

    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Ep.whiteA(.09)))),
          child: Row(
            children: [
              CircleIconButton(onTap: app.back),
              const SizedBox(width: 10),
              Text('BAND',
                  style: epText(
                      size: 12, weight: FontWeight.w800, letterSpacing: 1.4, color: Ep.inkA(.5))),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
            children: [
              Row(
                children: [
                  BandAvatar(band, size: 72, radius: 14, fontSize: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(band.name.toUpperCase(), style: epDisplay(size: 22, height: 1)),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            for (final t in band.genres)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Ep.whiteA(.25)),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(t.toUpperCase(),
                                    style: epText(
                                        size: 10,
                                        weight: FontWeight.w800,
                                        letterSpacing: .8,
                                        color: Ep.inkA(.8))),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${band.area} · ${band.followersLabel} followers',
                            style: epText(size: 11.5, color: Ep.inkA(.5))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(app.bioFor(bandId),
                  style: epText(size: 13, color: Ep.inkA(.7), height: 1.5)),
              const SizedBox(height: 16),
              EpButton(
                following ? 'FOLLOWING ✓' : '+ FOLLOW ${band.name.toUpperCase()}',
                fontSize: 12.5,
                kind: following ? EpButtonKind.outline : EpButtonKind.filled,
                padding: const EdgeInsets.symmetric(vertical: 13),
                onTap: () => app.requestFollow(bandId),
              ),
              const SizedBox(height: 16),
              const SectionLabel('▶ THIS IS WHAT WE SOUND LIKE', blue: true),
              const SizedBox(height: 8),
              _PinnedVideo(pinned: pinned, app: app),
              const SizedBox(height: 16),
              const SectionLabel('CLIPS'),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 168 / 104,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [for (final v in clips) _ClipTile(clip: v, app: app)],
              ),
              const SizedBox(height: 16),
              const SectionLabel('UPCOMING GIGS'),
              const SizedBox(height: 8),
              for (final g in upcoming) ...[
                _UpcomingRow(gig: g, app: app),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              SectionLabel('PAST GIGS · ${band.past.length} PLAYED'),
              const SizedBox(height: 6),
              for (final p in band.past)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Ep.whiteA(.07)))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(p.title,
                            style:
                                epText(size: 12.5, weight: FontWeight.w700, color: Ep.inkA(.75))),
                      ),
                      Text(p.meta, style: epText(size: 11, color: Ep.inkA(.4))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PinnedVideo extends StatelessWidget {
  final VideoClip pinned;
  final AppState app;

  const _PinnedVideo({required this.pinned, required this.app});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => app.say('▶ Video player placeholder (demo)'),
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF16161C), Color(0xFF0D0D10)],
          ),
          border: Border.all(color: Ep.whiteA(.12)),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Ep.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Ep.blue.withValues(alpha: .5),
                        blurRadius: 24,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.only(left: 5),
                  child: PlayTriangle(size: 18),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 10,
              right: 110,
              child: Text(pinned.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: epText(size: 11.5, weight: FontWeight.w800, letterSpacing: .4)),
            ),
            Positioned(
              right: 12,
              bottom: 10,
              child: Text('${pinned.views} · ${pinned.len}',
                  style: epText(size: 10.5, weight: FontWeight.w700, color: Ep.inkA(.55))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  final VideoClip clip;
  final AppState app;

  const _ClipTile({required this.clip, required this.app});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => app.say('▶ Video player placeholder (demo)'),
      child: Container(
        decoration: BoxDecoration(
          color: Ep.card,
          border: Border.all(color: Ep.whiteA(.1)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Center(child: PlayTriangle(size: 13, color: Ep.whiteA(.85))),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(clip.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: epText(size: 10, weight: FontWeight.w700, color: Ep.inkA(.8))),
            ),
            Positioned(
              right: 7,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(clip.len, style: epText(size: 9, weight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _UpcomingRow({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    return EpCard(
      padding: const EdgeInsets.all(10),
      onTap: () => app.openGig(gig.id),
      child: Row(
        children: [
          FlyerBox(
              style: app.flyer(gig.flyKey),
              width: 40,
              height: 52,
              rotationDeg: -2,
              radius: 5,
              shadow: false),
          const SizedBox(width: 11),
          Expanded(
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
          const SizedBox(width: 8),
          PriceBadge(gig),
        ],
      ),
    );
  }
}
