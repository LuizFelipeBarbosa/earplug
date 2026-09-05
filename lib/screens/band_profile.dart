import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../data/repository.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/band_identity_editor.dart';
import '../widgets/brand_icons.dart';
import '../widgets/common.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/video_player_sheet.dart';
import '../widgets/video_thumbnail.dart';

class BandProfileScreen extends StatelessWidget {
  final String bandId;

  const BandProfileScreen({super.key, required this.bandId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.band(bandId);
    if (band == null) {
      if (app.publicBandMissing(bandId)) {
        return Center(
          child: Text(
            'BAND NOT FOUND',
            style: epText(color: context.epColors.contentSecondary),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final media = context.watch<BandMediaController>();
    final vids = media.videosFor(bandId);
    final pinned = media.pinnedVideoFor(bandId);
    final soundVideos = vids.where((video) => video.id != pinned?.id).toList();
    if (pinned != null) soundVideos.insert(0, pinned);
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
            children: [
              _BandHero(
                band: band,
                bio: app.bioFor(bandId),
                onEditBanner: app.bandId == bandId && app.isAdminOf(bandId)
                    ? app.openBandEditor
                    : null,
              ),
              const SizedBox(height: 12),
              EpButton(
                following
                    ? 'FOLLOWING ✓ · ${band.followersLabel}'
                    : 'FOLLOW · ${band.followersLabel}',
                fontSize: 12.5,
                kind: EpButtonKind.filled,
                padding: const EdgeInsets.symmetric(vertical: 13),
                onTap: () => app.requestFollow(bandId),
              ),
              _BandLinks(app: app, bandId: bandId),
              if (soundVideos.isNotEmpty) ...[
                const SectionBar(label: 'THIS IS WHAT WE SOUND LIKE'),
                for (var index = 0; index < soundVideos.length; index += 2) ...[
                  Row(
                    children: [
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 168 / 104,
                          child: _ClipTile(
                            clip: soundVideos[index],
                            band: band,
                            app: app,
                            pinned: soundVideos[index].id == pinned?.id,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: index + 1 < soundVideos.length
                            ? AspectRatio(
                                aspectRatio: 168 / 104,
                                child: _ClipTile(
                                  clip: soundVideos[index + 1],
                                  band: band,
                                  app: app,
                                  pinned:
                                      soundVideos[index + 1].id == pinned?.id,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  if (index + 2 < soundVideos.length) const SizedBox(height: 8),
                ],
              ],
              if (photos.isNotEmpty) ...[
                const SectionBar(label: 'PHOTOS'),
                SizedBox(
                  height: 104,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (
                          var i = 0;
                          i < math.min(photos.length, 6);
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Builder(
                            builder: (context) {
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
                                        fallback: ColoredBox(
                                          color: context.epColors.surface,
                                        ),
                                      ),
                                      ColoredBox(
                                        color: band.color.withValues(
                                          alpha: .14,
                                        ),
                                      ),
                                      if (photos.length > 6 && i == 5) ...[
                                        ColoredBox(
                                          color: Colors.black.withValues(
                                            alpha: .55,
                                          ),
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
                                  onTap: () =>
                                      showPhotoViewer(context, photos, i),
                                  child: SizedBox(
                                    width: 96,
                                    height: 96,
                                    child: tile,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              SectionBar(label: 'UPCOMING GIGS', count: upcoming.length),
              for (final g in upcoming) ...[
                FanEventCard(gig: g, app: app),
                const SizedBox(height: 8),
              ],
              if (upcoming.isEmpty)
                Text(
                  'Nothing on the calendar right now.',
                  style: epText(
                    size: 11.5,
                    color: context.epColors.contentDisabled,
                  ),
                ),
              _PastShows(band: band, app: app),
              if (details?.credits?.trim().isNotEmpty == true) ...[
                const SectionBar(label: 'CREDITS'),
                Text(
                  details!.credits!.trim(),
                  style: epText(
                    size: 12,
                    color: context.epColors.contentSecondary,
                    height: 1.45,
                  ),
                ),
              ],
              if (details?.memberNames.isNotEmpty == true) ...[
                const SectionBar(label: 'BAND MEMBERS'),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final name in details!.memberNames)
                      Chip(label: Text(name)),
                  ],
                ),
              ],
              _BandReviewsSection(
                key: ValueKey('band-reviews-loader-$bandId'),
                bandId: bandId,
                summary: band.reviewSummary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BandReviewsSection extends StatefulWidget {
  const _BandReviewsSection({
    super.key,
    required this.bandId,
    required this.summary,
  });

  final String bandId;
  final ReviewSummary? summary;

  @override
  State<_BandReviewsSection> createState() => _BandReviewsSectionState();
}

class _BandReviewsSectionState extends State<_BandReviewsSection> {
  late final Future<List<PublicReview>> _reviews;

  @override
  void initState() {
    super.initState();
    _reviews = context.read<AppState>().repository.reviewsForBand(
      widget.bandId,
      limit: 5,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PublicReview>>(
      future: _reviews,
      builder: (context, snapshot) {
        final summary = widget.summary;
        final reviews = snapshot.data ?? const <PublicReview>[];
        if (summary == null || (summary.count == 0 && reviews.isEmpty)) {
          return const SizedBox.shrink();
        }
        return Column(
          key: const ValueKey('band-reviews'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionBar(label: 'REVIEWS', count: summary.count),
            Text(
              '★ ${summary.mean.toStringAsFixed(1)} · ${summary.count} reviews · '
              '${summary.completedBookings} completed bookings',
              style: Theme.of(context).textTheme.epBody,
            ),
            for (final review in reviews) ...[
              const SizedBox(height: 10),
              EpCard(
                key: ValueKey('band-review-${review.reviewId}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: '${review.rating} out of 5 stars',
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          for (var rating = 1; rating <= 5; rating++)
                            Icon(
                              rating <= review.rating
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 18,
                              color: context.epColors.accent,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      review.counterpartyName,
                      style: Theme.of(context).textTheme.epBody,
                    ),
                    Text(
                      review.monthLabel,
                      style: Theme.of(context).textTheme.epCaption,
                    ),
                    if (review.categories.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final category in review.categories)
                            EpChip(
                              label: category.toUpperCase(),
                              active: true,
                              onTap: null,
                              readOnly: true,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      review.text,
                      style: Theme.of(context).textTheme.epBody,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BandHero extends StatelessWidget {
  const _BandHero({
    required this.band,
    required this.bio,
    required this.onEditBanner,
  });

  final Band band;
  final String bio;
  final VoidCallback? onEditBanner;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('band-profile-hero-${band.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            BandIdentityHeader(
              name: band.name,
              area: band.area,
              initials: band.initials,
              color: band.color,
              avatarUrl: band.profileImageUrl,
              bannerUrl: band.headerImageUrl,
            ),
            if (onEditBanner != null)
              Positioned(
                right: 96,
                bottom: 10,
                child: Semantics(
                  button: true,
                  label: 'Edit header image',
                  excludeSemantics: true,
                  child: IconButton(
                    key: const ValueKey('edit-band-profile-banner'),
                    tooltip: 'Edit header image',
                    onPressed: onEditBanner,
                    style: ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                      backgroundColor: WidgetStatePropertyAll(
                        Colors.black.withValues(alpha: .72),
                      ),
                      foregroundColor: WidgetStatePropertyAll(Colors.white),
                    ),
                    icon: Icon(Icons.photo_camera_outlined, size: 19),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.epColors.raised,
            border: Border.all(color: context.epColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 5,
                children: [
                  for (final genre in band.genres)
                    Text(
                      genre.toUpperCase(),
                      style: Theme.of(context).textTheme.epChipLabel.copyWith(
                        color: context.epColors.accent,
                      ),
                    ),
                ],
              ),
              if (bio.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(bio, style: Theme.of(context).textTheme.epBody),
              ],
              const SizedBox(height: 10),
              Text(
                '${band.followersLabel} '
                '${band.followers == 1 ? 'follower' : 'followers'}',
                style: Theme.of(context).textTheme.epCaption,
              ),
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
    return ScreenHeader(
      filled: false,
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
                          color: context.epColors.contentSecondary,
                        ),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: app.openBandEditor,
                        child: Text('Edit profile'),
                      ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: app.returnToBandDashboard,
                  icon: Icon(Icons.arrow_back, size: 17),
                  label: Text('Return to band dashboard'),
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
                    color: context.epColors.contentSecondary,
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
      (
        name: 'Instagram',
        icon: BrandGlyph.instagram,
        value: app.linkIgFor(bandId),
        instagram: true,
      ),
      (
        name: 'Bandcamp',
        icon: BrandGlyph.bandcamp,
        value: app.linkBcFor(bandId),
        instagram: false,
      ),
      (
        name: 'YouTube',
        icon: BrandGlyph.youtube,
        value: app.linkYtFor(bandId),
        instagram: false,
      ),
    ].where((link) => link.value.trim().isNotEmpty).toList();
    if (links.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final link in links)
            _BandSocialButton(
              key: ValueKey('band-social-${link.name.toLowerCase()}'),
              name: link.name,
              icon: link.icon,
              onPressed: () =>
                  _openBandLink(context, link.value, instagram: link.instagram),
            ),
        ],
      ),
    );
  }
}

class _BandSocialButton extends StatelessWidget {
  const _BandSocialButton({
    super.key,
    required this.name,
    required this.icon,
    required this.onPressed,
  });

  final String name;
  final BrandGlyph icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tooltip = 'Open $name';
    return Semantics(
      button: true,
      label: tooltip,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: tooltip,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(48, 48)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
            icon: BrandIcon(
              glyph: icon,
              size: 18,
              color: context.epColors.accent,
            ),
            label: Text('${name.toUpperCase()} ↗'),
          ),
        ),
      ),
    );
  }
}

Future<void> _openBandLink(
  BuildContext context,
  String raw, {
  required bool instagram,
}) async {
  final uri = bandLinkUri(raw, instagram: instagram);
  await openExternalForUser(context, uri.toString());
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
        SectionBar(label: 'PAST GIGS · ${rows.length} PLAYED'),
        for (final row in rows) _PastRow(show: row),
      ];
    } else if (band.past.isNotEmpty) {
      content = [
        SectionBar(label: 'PAST GIGS · ${band.past.length} PLAYED'),
        for (final row in band.past) _PastRow(show: row),
      ];
    } else if (history == null && error == null) {
      content = [
        const SectionBar(label: 'PAST GIGS'),
        Text(
          'Loading past shows…',
          style: epText(size: 11.5, color: context.epColors.contentDisabled),
        ),
      ];
    } else if (error != null) {
      content = [
        const SectionBar(label: 'PAST GIGS'),
        Text(
          "Couldn't load past shows.",
          style: epText(size: 11.5, color: context.epColors.contentDisabled),
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
        const SectionBar(label: 'PAST GIGS'),
        Text(
          'No past shows yet.',
          style: epText(size: 11.5, color: context.epColors.contentDisabled),
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: content,
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.show});

  final PastGig show;

  @override
  Widget build(BuildContext context) {
    return LedgerRow(title: show.title, details: [show.meta]);
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

class _ClipTile extends StatelessWidget {
  final BandMedia clip;
  final Band band;
  final AppState app;
  final bool pinned;

  const _ClipTile({
    required this.clip,
    required this.band,
    required this.app,
    required this.pinned,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.epColors.surface,
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
            BandVideoThumbnail(
              media: clip,
              fallback: ClipTexture(bandColor: band.color),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                    stops: [.38, 1],
                  ),
                ),
              ),
            ),
            Center(
              child: PlayTriangle(
                size: 13,
                color: context.epColors.contentPrimary,
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(
                clip.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.epCaption.copyWith(
                  color: context.epColors.contentPrimary,
                ),
              ),
            ),
            Positioned(
              left: 7,
              right: 7,
              top: 6,
              child: Row(
                children: [
                  if (pinned)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: context.epColors.volt,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PINNED',
                              style: Theme.of(context).textTheme.epCaption
                                  .copyWith(
                                    color: context.epColors.dark,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 5),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .72),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          clip.url == null || clip.url!.isEmpty
                              ? 'PROCESSING'
                              : clip.lenLabel,
                          style: Theme.of(context).textTheme.epCaption.copyWith(
                            color: context.epColors.contentPrimary,
                            fontSize: 9.5,
                          ),
                        ),
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
