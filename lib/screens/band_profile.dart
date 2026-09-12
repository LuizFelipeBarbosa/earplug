import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../band_media_state.dart';
import '../data/repository.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/brand_icons.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/video_player_sheet.dart';
import '../widgets/video_thumbnail.dart';

class BandProfileScreen extends StatelessWidget {
  const BandProfileScreen({super.key, required this.bandId});

  final String bandId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.band(bandId);
    if (band == null) {
      if (app.publicBandMissing(bandId)) {
        return const Center(child: EpEyebrow('Band not found'));
      }
      return const Center(child: CircularProgressIndicator());
    }

    final media = context.watch<BandMediaController>();
    final videos = media.videosFor(bandId);
    final pinned = media.pinnedVideoFor(bandId);
    final soundVideos = videos
        .where((video) => video.id != pinned?.id)
        .toList();
    if (pinned != null) soundVideos.insert(0, pinned);
    final photos = media.photosFor(bandId);
    final upcoming = [
      for (final id in band.upcoming)
        if (app.gig(id) case final Gig gig) gig,
    ];
    final isManagedPreview =
        app.current.screen == Screen.bandPreview &&
        app.current.param == bandId &&
        app.myBands.contains(bandId);
    final details = app.profileDetailsFor(bandId);
    final bio = app.bioFor(bandId);
    final bodyStyle = Theme.of(
      context,
    ).textTheme.epBody.copyWith(color: context.epColors.muted);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: EpLayout.workspaceWidth),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _BandHero(
              band: band,
              onBack: isManagedPreview ? app.returnToBandDashboard : app.back,
              backLabel: isManagedPreview ? 'Return to band dashboard' : 'Back',
              onEditBanner: app.bandId == bandId && app.isAdminOf(bandId)
                  ? app.openBandEditor
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  _ProfileActions(
                    app: app,
                    bandId: bandId,
                    isManagedPreview: isManagedPreview,
                  ),
                  if (bio.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(bio, style: bodyStyle),
                  ],
                  if (soundVideos.isNotEmpty || photos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const EpHairline(),
                    const EpSectionHeader(
                      label: 'This is what we sound like',
                      padding: EdgeInsets.only(top: 24, bottom: 12),
                    ),
                    _BandMediaGrid(
                      band: band,
                      app: app,
                      videos: soundVideos,
                      pinnedId: pinned?.id,
                      photos: photos,
                    ),
                  ],
                  EpSectionHeader(label: 'Upcoming · ${upcoming.length}'),
                  for (final gig in upcoming) _UpcomingGig(gig: gig, app: app),
                  if (upcoming.isEmpty)
                    Text(
                      'Nothing on the calendar right now.',
                      style: bodyStyle,
                    ),
                  _PastShows(band: band, app: app),
                  if (details?.credits?.trim().isNotEmpty == true) ...[
                    const EpSectionHeader(label: 'Credits'),
                    Text(details!.credits!.trim(), style: bodyStyle),
                  ],
                  if (details?.memberNames.isNotEmpty == true) ...[
                    const EpSectionHeader(label: 'Band members'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in details!.memberNames)
                          EpChip(
                            label: name,
                            active: false,
                            onTap: null,
                            readOnly: true,
                          ),
                      ],
                    ),
                  ],
                  _BandReviewsSection(
                    key: ValueKey('band-reviews-loader-$bandId'),
                    bandId: bandId,
                    summary: band.reviewSummary,
                  ),
                  const SizedBox(height: tabBarClearance),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BandHero extends StatelessWidget {
  const _BandHero({
    required this.band,
    required this.onBack,
    required this.backLabel,
    required this.onEditBanner,
  });

  final Band band;
  final VoidCallback onBack;
  final String backLabel;
  final VoidCallback? onEditBanner;

  @override
  Widget build(BuildContext context) {
    final colors = context.epColors;
    final topInset = MediaQuery.paddingOf(context).top;
    final metadata = [
      ...band.genres,
      '${band.followersLabel} ${band.followers == 1 ? 'follower' : 'followers'}',
    ].join(' · ');

    // The artboard is 300px tall. A minimum lets long names and larger text
    // grow naturally without covering the navigation or clipping the title.
    return ConstrainedBox(
      key: ValueKey('band-profile-hero-${band.id}'),
      constraints: BoxConstraints(minHeight: 300 + topInset),
      child: EpPanel(
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: EpNetworkImage(
                url: band.headerImageUrl ?? band.profileImageUrl,
                fallback: const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                key: const ValueKey('band-profile-banner-scrim'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: const [0, .6],
                    colors: [colors.background, Colors.transparent],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                EpLayout.gutter,
                112 + topInset,
                EpLayout.gutter,
                22,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EpEyebrow.accent(
                    [
                      'Band',
                      if (band.area.trim().isNotEmpty) band.area,
                    ].join(' · '),
                  ),
                  const SizedBox(height: 12),
                  EpDisplay(band.name, size: 52),
                  const SizedBox(height: 12),
                  EpMonoText(metadata, color: colors.muted),
                ],
              ),
            ),
            Positioned(
              top: 16 + topInset,
              left: 12,
              child: EpIconPill(
                icon: Icons.arrow_back,
                semanticLabel: backLabel,
                onPressed: onBack,
              ),
            ),
            Positioned(
              top: 20 + topInset,
              right: EpLayout.gutter,
              child: Semantics(
                key: const ValueKey('band-profile-avatar-frame'),
                image: true,
                label: '${band.name} profile image',
                excludeSemantics: true,
                child: SizedBox.square(
                  key: const ValueKey('band-profile-image-control'),
                  dimension: 56,
                  child: EpNetworkImage(
                    url: band.profileImageUrl,
                    cacheWidth: 56,
                    cacheHeight: 56,
                    fallback: EpAvatarTile(
                      initials: band.initials,
                      size: 56,
                      accent: true,
                    ),
                  ),
                ),
              ),
            ),
            if (onEditBanner != null)
              Positioned(
                top: 64 + topInset,
                left: 12,
                child: Semantics(
                  button: true,
                  label: 'Edit header image',
                  excludeSemantics: true,
                  child: IconButton(
                    key: const ValueKey('edit-band-profile-banner'),
                    tooltip: 'Edit header image',
                    onPressed: onEditBanner,
                    style: IconButton.styleFrom(
                      backgroundColor: colors.background,
                      foregroundColor: colors.ink,
                    ),
                    icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.app,
    required this.bandId,
    required this.isManagedPreview,
  });

  final AppState app;
  final String bandId;
  final bool isManagedPreview;

  @override
  Widget build(BuildContext context) {
    final following = app.follows.contains(bandId);
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
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            EpPill(
              label: following ? 'Following' : 'Follow',
              variant: following ? EpPillVariant.ink : EpPillVariant.primary,
              size: EpPillSize.regular,
              onPressed: () => app.requestFollow(bandId),
            ),
            for (final link in links)
              if (link.value.trim().isNotEmpty)
                _BandSocialButton(
                  key: ValueKey('band-social-${link.name.toLowerCase()}'),
                  name: link.name,
                  icon: link.icon,
                  onPressed: () => _openBandLink(
                    context,
                    link.value,
                    instagram: link.instagram,
                  ),
                ),
          ],
        ),
        if (isManagedPreview) ...[
          const SizedBox(height: 16),
          const EpEyebrow('Public profile preview'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (app.isAdminOf(bandId))
                EpPill(
                  label: 'Edit profile',
                  icon: Icons.edit_outlined,
                  onPressed: app.openBandEditor,
                ),
              EpPill(
                label: 'Return to band dashboard',
                onPressed: app.returnToBandDashboard,
              ),
            ],
          ),
        ],
      ],
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
    // EpPill accepts IconData, while BrandIcon paints a widget. Keep its pill
    // chrome, focus, and action semantics, and compose the brand content above.
    return Tooltip(
      message: 'Open $name',
      excludeFromSemantics: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: EpPill(
              label: '',
              semanticLabel: 'Open $name',
              expand: true,
              onPressed: onPressed,
            ),
          ),
          IgnorePointer(
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BrandIcon(
                        glyph: icon,
                        size: 16,
                        color: context.epColors.ink,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: EpMonoText('$name ↗')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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

class _BandMediaGrid extends StatelessWidget {
  const _BandMediaGrid({
    required this.band,
    required this.app,
    required this.videos,
    required this.pinnedId,
    required this.photos,
  });

  final Band band;
  final AppState app;
  final List<BandMedia> videos;
  final String? pinnedId;
  final List<BandMedia> photos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final clip in videos)
              SizedBox(
                width: width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: width * 104 / 168),
                  child: _ClipTile(
                    clip: clip,
                    band: band,
                    app: app,
                    pinned: clip.id == pinnedId,
                  ),
                ),
              ),
            for (var index = 0; index < photos.length; index++)
              SizedBox(
                width: width,
                child: AspectRatio(
                  aspectRatio: 168 / 104,
                  child: Semantics(
                    button: true,
                    label: photos[index].title,
                    child: Material(
                      key: ValueKey('band-photo-${photos[index].id}'),
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => showPhotoViewer(context, photos, index),
                        child: EpPanel(
                          child: EpNetworkImage(
                            url: photos[index].url,
                            fallback: const EpPanel(striped: true),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({
    required this.clip,
    required this.band,
    required this.app,
    required this.pinned,
  });

  final BandMedia clip;
  final Band band;
  final AppState app;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final processing = clip.url == null || clip.url!.isEmpty;
    final metadata = [
      if (pinned) 'Pinned',
      if (processing)
        'Processing'
      else if (clip.lenLabel.isNotEmpty)
        clip.lenLabel,
    ].join(' · ');
    final colors = context.epColors;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (processing) {
              app.say('That clip is still processing.');
              return;
            }
            showBandVideo(context, media: clip, bandName: band.name);
          },
          child: EpPanel(
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Positioned.fill(
                  child: BandVideoThumbnail(
                    media: clip,
                    fallback: const EpPanel(striped: true),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.background.withValues(alpha: .65),
                          Colors.transparent,
                          colors.background.withValues(alpha: .85),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (metadata.isNotEmpty)
                        EpMonoText(
                          metadata,
                          color: pinned ? colors.accent : colors.muted,
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: PlayTriangle(size: 16)),
                      ),
                      Text(
                        clip.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epBody,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingGig extends StatelessWidget {
  const _UpcomingGig({required this.gig, required this.app});

  final Gig gig;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    final cancelled = gig.lifecycle == GigLifecycle.cancelled;
    final going = app.rsvps.contains(gig.id);
    final external = gig.tix == Ticketing.external;
    final lineup = [
      for (final id in gig.lineup)
        if (app.band(id) case final Band band) band.name,
    ];
    return Column(
      key: ValueKey('fan-event-${gig.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (app.isDiscoveryBoosted(gig))
          EpEyebrow(
            'Discovery boost · Complete listing',
            key: ValueKey('discovery-boost-${gig.id}'),
          ),
        Semantics(
          label: gig.dateShort,
          child: EpGigRow(
            date: gig.startsAt,
            title: gig.title,
            sub: [
              if (venue.id.isNotEmpty) venue.name,
              if (venue.area.trim().isNotEmpty) venue.area,
              if (gig.doorsLabel.trim().isNotEmpty) 'Doors ${gig.doorsLabel}',
              gig.priceLabel,
              if (lineup.isNotEmpty) lineup.join(' · '),
            ].join(' · '),
            onTap: () => app.openGig(gig.id),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              EpMonoText(
                '${gig.ageRequirement.label} · '
                '${cancelled ? 'Cancelled' : '${app.rsvpCount(gig)} going'}',
                color: context.epColors.muted,
              ),
              Wrap(
                key: ValueKey('event-actions-${gig.id}'),
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  EpIconPill(
                    key: ValueKey('save-${gig.id}'),
                    semanticLabel: app.saved.contains(gig.id)
                        ? 'Remove saved event'
                        : 'Save event',
                    icon: app.saved.contains(gig.id)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    onPressed: () => app.requestSave(gig.id),
                  ),
                  EpIconPill(
                    key: ValueKey('share-${gig.id}'),
                    semanticLabel: 'Share event',
                    icon: Icons.ios_share,
                    onPressed: () => copyForUser(
                      context,
                      publicWebUrl('g/${gig.publicRef}'),
                      successMessage:
                          'Link copied: ${publicWebDisplayUrl('g/${gig.publicRef}')}',
                    ),
                  ),
                  if (!cancelled)
                    EpPill(
                      key: ValueKey('ticket-action-${gig.id}'),
                      label: external
                          ? 'Tickets ↗'
                          : (going ? 'Going ✓' : 'RSVP'),
                      onPressed: () {
                        if (external) {
                          final url = gig.externalUrl;
                          if (url == null || url.isEmpty) {
                            app.say('No ticket link listed for this gig.');
                            return;
                          }
                          openExternalForUser(context, url);
                        } else if (going) {
                          app.toggleRsvp(gig.id);
                        } else {
                          app.requestRsvp(gig.id);
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
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
    final bodyStyle = Theme.of(
      context,
    ).textTheme.epBody.copyWith(color: context.epColors.muted);
    final List<Widget> content;

    if (rows.isNotEmpty) {
      content = [
        EpSectionHeader(label: 'Past gigs · ${rows.length} played'),
        for (final row in rows)
          LedgerRow(title: row.title, details: [row.meta]),
      ];
    } else if (band.past.isNotEmpty) {
      content = [
        EpSectionHeader(label: 'Past gigs · ${band.past.length} played'),
        for (final row in band.past)
          LedgerRow(title: row.title, details: [row.meta]),
      ];
    } else if (history == null && error == null) {
      content = [
        const EpSectionHeader(label: 'Past gigs'),
        Text('Loading past shows…', style: bodyStyle),
      ];
    } else if (error != null) {
      content = [
        const EpSectionHeader(label: 'Past gigs'),
        Text("Couldn't load past shows.", style: bodyStyle),
        const SizedBox(height: 10),
        EpPill(
          label: 'Retry',
          onPressed: () => app.refreshBandHistory(band.id),
        ),
      ];
    } else {
      content = [
        const EpSectionHeader(label: 'Past gigs'),
        Text('No past shows yet.', style: bodyStyle),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: content,
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
            EpSectionHeader(label: 'Reviews · ${summary.count}'),
            Text(
              '★ ${summary.mean.toStringAsFixed(1)} · ${summary.count} reviews · '
              '${summary.completedBookings} completed bookings',
              style: Theme.of(context).textTheme.epBody,
            ),
            for (final review in reviews)
              _ReviewRow(
                key: ValueKey('band-review-${review.reviewId}'),
                review: review,
              ),
          ],
        );
      },
    );
  }
}

/// A public review as a hairline row: rating, who wrote it, and their words.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({super.key, required this.review});

  final PublicReview review;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.epColors.line)),
      ),
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
                    rating <= review.rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: context.epColors.accent,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(review.counterpartyName, style: textTheme.epBody),
          Text(review.monthLabel, style: textTheme.epCaption),
          if (review.categories.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final category in review.categories)
                  EpChip(
                    label: category,
                    active: true,
                    onTap: null,
                    readOnly: true,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(review.text, style: textTheme.epBody),
        ],
      ),
    );
  }
}
