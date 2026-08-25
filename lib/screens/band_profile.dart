import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/video_player_sheet.dart';

class BandProfileScreen extends StatelessWidget {
  final String bandId;

  const BandProfileScreen({super.key, required this.bandId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();

    final media = context.watch<BandMediaController>();
    final vids = media.videosFor(bandId);
    final pinned = media.pinnedVideoFor(bandId);
    final clips = vids.where((v) => v.id != pinned?.id).take(4).toList();
    final photos = media.photosFor(bandId);
    final upcoming = [
      for (final id in band.upcoming)
        if (app.gig(id) case final Gig g) g,
    ];
    final following = app.follows.contains(bandId);
    final isManagedPreview =
        app.current.screen == Screen.bandPreview &&
        app.current.param == bandId &&
        app.myBands.contains(bandId);
    final details = app.profileDetailsFor(bandId);

    return Column(
      children: [
        _ProfileHeader(
          app: app,
          isManagedPreview: isManagedPreview,
          isAdmin: app.isAdminOf(bandId),
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
                        Text(
                          band.name.toUpperCase(),
                          style: epDisplay(size: 22, height: 1),
                        ),
                        if (band.profileComplete) ...[
                          const SizedBox(height: 7),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: ProfileCompleteBadge(),
                          ),
                        ],
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            for (final t in band.genres)
                              SizedBox(
                                height: 48,
                                child: Chip(label: Text(t.toUpperCase())),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${band.area} · ${band.followersLabel} followers',
                          style: epText(size: 11.5, color: Ep.contentSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                app.bioFor(bandId),
                style: epText(
                  size: 13,
                  color: Ep.contentSecondary,
                  height: 1.5,
                ),
              ),
              _BandLinks(app: app, bandId: bandId),
              const SizedBox(height: 16),
              EpButton(
                following
                    ? 'FOLLOWING ✓'
                    : '+ FOLLOW ${band.name.toUpperCase()}',
                fontSize: 12.5,
                kind: following ? EpButtonKind.outline : EpButtonKind.filled,
                padding: const EdgeInsets.symmetric(vertical: 13),
                onTap: () => app.requestFollow(bandId),
              ),
              if (pinned != null) ...[
                const SizedBox(height: 16),
                const SectionLabel('▶ THIS IS WHAT WE SOUND LIKE', blue: true),
                const SizedBox(height: 8),
                _PinnedVideo(pinned: pinned, band: band, app: app),
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
                  children: [
                    for (final v in clips)
                      _ClipTile(clip: v, band: band, app: app),
                  ],
                ),
              ],
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionLabel('PHOTOS'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: math.min(photos.length, 6),
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final tile = ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              EpNetworkImage(
                                url: photos[i].url,
                                fallback: const ColoredBox(color: Ep.surface),
                              ),
                              if (photos.length > 6 && i == 5) ...[
                                ColoredBox(
                                  color: Colors.black.withValues(alpha: .55),
                                ),
                                Center(
                                  child: Text(
                                    '+${photos.length - 6}',
                                    style: epDisplay(size: 16),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                      return Material(
                        key: ValueKey('band-photo-${photos[i].id}'),
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => showPhotoViewer(context, photos, i),
                          child: SizedBox(width: 96, height: 96, child: tile),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const SectionLabel('UPCOMING GIGS'),
              const SizedBox(height: 8),
              for (final g in upcoming) ...[
                FanEventCard(gig: g, app: app),
                const SizedBox(height: 8),
              ],
              if (upcoming.isEmpty)
                Text(
                  'Nothing on the calendar right now.',
                  style: epText(size: 11.5, color: Ep.contentDisabled),
                ),
              _PastShows(band: band, app: app),
              if (details?.credits?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 16),
                const SectionLabel('CREDITS'),
                const SizedBox(height: 6),
                Text(
                  details!.credits!.trim(),
                  style: epText(
                    size: 12,
                    color: Ep.contentSecondary,
                    height: 1.45,
                  ),
                ),
              ],
              if (details?.memberNames.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                const SectionLabel('BAND MEMBERS'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final name in details!.memberNames)
                      Chip(label: Text(name)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.app,
    required this.isManagedPreview,
    required this.isAdmin,
  });

  final AppState app;
  final bool isManagedPreview;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ep.border)),
      ),
      child: isManagedPreview
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'PUBLIC PROFILE PREVIEW',
                        style: epText(
                          size: 12,
                          weight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: Ep.contentSecondary,
                        ),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: app.openBandEditor,
                        child: const Text('Edit profile'),
                      ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: app.returnToBandDashboard,
                  icon: const Icon(Icons.arrow_back, size: 17),
                  label: const Text('Return to band dashboard'),
                ),
              ],
            )
          : Row(
              children: [
                CircleIconButton(onTap: app.back),
                const SizedBox(width: 10),
                Text(
                  'BAND',
                  style: epText(
                    size: 12,
                    weight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Ep.contentSecondary,
                  ),
                ),
              ],
            ),
    );
  }
}

class _BandLinks extends StatelessWidget {
  const _BandLinks({required this.app, required this.bandId});

  final AppState app;
  final String bandId;

  @override
  Widget build(BuildContext context) {
    final links = [
      (label: 'INSTAGRAM', value: app.linkIgFor(bandId), instagram: true),
      (label: 'BANDCAMP', value: app.linkBcFor(bandId), instagram: false),
      (label: 'YOUTUBE', value: app.linkYtFor(bandId), instagram: false),
    ].where((link) => link.value.trim().isNotEmpty).toList();
    if (links.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final link in links)
            OutlinedButton(
              onPressed: () =>
                  _openBandLink(app, link.value, instagram: link.instagram),
              child: Text('${link.label} ↗'),
            ),
        ],
      ),
    );
  }
}

Future<void> _openBandLink(
  AppState app,
  String raw, {
  required bool instagram,
}) async {
  final uri = bandLinkUri(raw, instagram: instagram);
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened) app.say("Couldn't open that link.");
}

@visibleForTesting
Uri bandLinkUri(String raw, {required bool instagram}) {
  final value = raw.trim();
  final hasHttpScheme = RegExp(
    r'^https?://',
    caseSensitive: false,
  ).hasMatch(value);

  if (!instagram) {
    return Uri.parse(hasHttpScheme ? value : 'https://$value');
  }

  final parsed = Uri.tryParse(hasHttpScheme ? value : 'https://$value');
  final host = parsed?.host.toLowerCase();
  if (parsed != null &&
      (host == 'instagram.com' || host == 'www.instagram.com')) {
    return parsed.replace(scheme: 'https', host: 'instagram.com');
  }
  if (hasHttpScheme) return Uri.parse(value);

  return Uri.https('instagram.com', value.replaceFirst(RegExp(r'^@'), ''));
}

class _PastShows extends StatelessWidget {
  const _PastShows({required this.band, required this.app});

  final Band band;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final history = app.bandHistory(band.id);
    final rows = history == null ? const <PastGig>[] : _pastRowsFrom(history);
    final error = app.bandHistoryError(band.id);
    final List<Widget> content;

    if (rows.isNotEmpty) {
      content = [
        SectionLabel('PAST GIGS · ${rows.length} PLAYED'),
        const SizedBox(height: 6),
        for (final row in rows) _PastRow(show: row),
      ];
    } else if (band.past.isNotEmpty) {
      content = [
        SectionLabel('PAST GIGS · ${band.past.length} PLAYED'),
        const SizedBox(height: 6),
        for (final row in band.past) _PastRow(show: row),
      ];
    } else if (history == null && error == null) {
      content = [
        const SectionLabel('PAST GIGS'),
        const SizedBox(height: 6),
        Text(
          'Loading past shows…',
          style: epText(size: 11.5, color: Ep.contentDisabled),
        ),
      ];
    } else if (error != null) {
      content = [
        const SectionLabel('PAST GIGS'),
        const SizedBox(height: 6),
        Text(
          "Couldn't load past shows.",
          style: epText(size: 11.5, color: Ep.contentDisabled),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 120,
          child: EpButton(
            'RETRY',
            kind: EpButtonKind.outline,
            fontSize: 12.5,
            padding: const EdgeInsets.symmetric(vertical: 10),
            onTap: () => app.refreshBandHistory(band.id),
          ),
        ),
      ];
    } else {
      content = [
        const SectionLabel('PAST GIGS'),
        const SizedBox(height: 6),
        Text(
          'No past shows yet.',
          style: epText(size: 11.5, color: Ep.contentDisabled),
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const SizedBox(height: 8), ...content],
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.show});

  final PastGig show;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
      decoration: BoxDecoration(
        border: const Border(bottom: BorderSide(color: Ep.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              show.title,
              style: epText(
                size: 12.5,
                weight: FontWeight.w700,
                color: Ep.contentSecondary,
              ),
            ),
          ),
          Text(show.meta, style: epText(size: 11, color: Ep.contentDisabled)),
        ],
      ),
    );
  }
}

/// Live history in the same "title · venue" / short-date shape the fan's own
/// history uses (`ConvexRepository.history`).
List<PastGig> _pastRowsFrom(BandHistory history) {
  final rows = <PastGig>[];
  for (final gig in history.gigs) {
    final venueName = history.venues[gig.venueId]?.name ?? '';
    final title = venueName.isEmpty ? gig.title : '${gig.title} · $venueName';
    rows.add(PastGig(title, gig.dateShort));
  }
  return rows;
}

class _PinnedVideo extends StatelessWidget {
  final BandMedia pinned;
  final Band band;
  final AppState app;

  const _PinnedVideo({
    required this.pinned,
    required this.band,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ep.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (pinned.url == null || pinned.url!.isEmpty) {
            app.say('That clip is still processing.');
            return;
          }
          showBandVideo(context, media: pinned, bandName: band.name);
        },
        child: SizedBox(
          height: 190,
          child: Stack(
            children: [
              Positioned.fill(child: ClipTexture(bandColor: band.color)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 90,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: .55),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Ep.brand,
                    shape: BoxShape.circle,
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
                child: Text(
                  pinned.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: epText(
                    size: 11.5,
                    weight: FontWeight.w800,
                    letterSpacing: .4,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 10,
                child: Text(
                  '${pinned.viewsLabel} · ${pinned.lenLabel}',
                  style: epText(
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: Ep.contentSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  final BandMedia clip;
  final Band band;
  final AppState app;

  const _ClipTile({required this.clip, required this.band, required this.app});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ep.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (clip.url == null || clip.url!.isEmpty) {
            app.say('That clip is still processing.');
            return;
          }
          showBandVideo(context, media: clip, bandName: band.name);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipTexture(bandColor: band.color),
            Center(child: PlayTriangle(size: 13, color: Ep.contentPrimary)),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(
                clip.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.epCaption.copyWith(color: Ep.contentPrimary),
              ),
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
                child: Text(
                  clip.lenLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.epCaption.copyWith(color: Ep.contentPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
