import 'package:flutter/material.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../explore_ranking.dart';
import '../flyer_styles.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_text.dart';
import 'explore_friends.dart';

String _initialsFor(String title) {
  final words = title
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.characters.first;
  return '${words.first.characters.first}${words.last.characters.first}';
}

String _friendsCue(List<SocialUserCard> friends) {
  final suffix = friends.length > 1 ? ' +${friends.length - 1}' : '';
  return '${friends.first.name}$suffix going';
}

class _ExploreHairlineRow extends StatelessWidget {
  const _ExploreHairlineRow({
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.minHeight = 44,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? semanticLabel;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: child,
          ),
        ),
        const EpHairline(),
      ],
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// A resolved lineup entry for compact and JUST-FOR-YOU gig rows.
class ExploreLineupBand {
  const ExploreLineupBand({
    required this.name,
    required this.initials,
    this.avatarUrl,
  });

  final String name;
  final String initials;
  final String? avatarUrl;
}

class ExploreLineupWrap extends StatelessWidget {
  const ExploreLineupWrap({super.key, required this.bands, this.textColor});

  final List<ExploreLineupBand> bands;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 6,
    children: [
      for (final band in bands)
        _ExploreLineupChip(band: band, textColor: textColor),
    ],
  );
}

class ExploreGigInfo {
  const ExploreGigInfo({required this.dateTime, this.distance, this.price});

  final String dateTime;
  final String? distance;
  final String? price;
}

class ExploreLineupRow extends StatelessWidget {
  const ExploreLineupRow({
    super.key,
    required this.bands,
    this.tint,
    this.onSeeAll,
  });

  final List<ExploreLineupBand> bands;
  final Color? tint;
  final VoidCallback? onSeeAll;

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    if (bands.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.epBody.copyWith(color: tint);
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = [
          for (final band in bands) 26 + _textWidth(context, band.name, style),
        ];
        final seeAllStyle = Theme.of(
          context,
        ).textTheme.epChipLabel.copyWith(color: tint ?? context.epColors.ink);
        final seeAllWidth = _textWidth(context, 'See all', seeAllStyle);
        var used = 0.0;
        var count = bands.length;
        var allFit = true;
        for (var i = 0; i < bands.length; i++) {
          final next = used + (i == 0 ? 0 : 12) + widths[i];
          if (next > constraints.maxWidth) {
            count = i;
            allFit = false;
            break;
          }
          used = next;
        }
        if (!allFit) {
          while (count > 0 && used + 12 + seeAllWidth > constraints.maxWidth) {
            count--;
            used -= widths[count] + (count == 0 ? 0 : 12);
          }
        }
        final visible = bands.take(count).toList();
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              _ExploreLineupChip(
                band: visible[i],
                textColor: tint,
                allowOverflow: false,
              ),
            ],
            if (!allFit) ...[
              if (visible.isNotEmpty) const SizedBox(width: 12),
              GestureDetector(
                key: const Key('lineup-see-all'),
                onTap: onSeeAll,
                child: Text('See all', style: seeAllStyle),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ExploreGigInfoLine extends StatelessWidget {
  const _ExploreGigInfoLine({required this.info});

  final ExploreGigInfo info;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.epLabel;
    final muted = Theme.of(
      context,
    ).textTheme.epMeta.copyWith(color: context.epColors.muted);
    final spans = <InlineSpan>[
      TextSpan(
        text: info.dateTime,
        style: label.copyWith(
          color: context.epColors.ink,
          fontWeight: FontWeight.bold,
        ),
      ),
      if (info.distance != null) ...[
        const TextSpan(text: ' · '),
        TextSpan(
          text: info.distance,
          style: label.copyWith(color: context.epColors.ink),
        ),
      ],
      if (info.price != null) ...[
        const TextSpan(text: ' · '),
        TextSpan(text: info.price, style: muted),
      ],
    ];
    return Text.rich(
      TextSpan(children: spans),
      softWrap: true,
      semanticsLabel: [
        info.dateTime,
        if (info.distance != null) info.distance!,
        if (info.price != null) info.price!,
      ].join(' · '),
    );
  }
}

/// Resolves a gig's band lineup, falling back to free-text performers.
List<ExploreLineupBand> exploreLineupFor(Gig gig, AppState app) {
  final resolved = [
    for (final bandId in gig.lineup)
      if (app.band(bandId) case final Band band)
        ExploreLineupBand(
          name: band.name,
          initials: band.initials,
          avatarUrl: band.profileImageUrl,
        ),
  ];
  if (resolved.isNotEmpty) return resolved;
  return [
    for (final performer in gig.performers)
      ExploreLineupBand(
        name: performer.name,
        initials: _initialsFor(performer.name),
      ),
  ];
}

class _ExploreLineupChip extends StatelessWidget {
  const _ExploreLineupChip({
    required this.band,
    this.textColor,
    this.allowOverflow = true,
  });

  final ExploreLineupBand band;
  final Color? textColor;
  final bool allowOverflow;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.epBody;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EpAvatarTile(
          initials: band.initials,
          size: 20,
          image: band.avatarUrl == null || band.avatarUrl!.isEmpty
              ? null
              : NetworkImage(band.avatarUrl!),
        ),
        const SizedBox(width: 6),
        Text(
          band.name,
          softWrap: false,
          maxLines: 1,
          overflow: allowOverflow ? TextOverflow.ellipsis : TextOverflow.clip,
          style: textColor == null
              ? textStyle
              : textStyle.copyWith(color: textColor),
        ),
      ],
    );
  }
}

/// Compact recommendation-feed event row.
class ExploreEventRow extends StatelessWidget {
  const ExploreEventRow({
    super.key,
    required this.gig,
    required this.venueName,
    required this.onTap,
    this.trailing,
    this.stretchTrailing = false,
    this.sub,
    this.lineup,
    this.meta,
    this.info,
    this.posterActions,
    this.friends = const <SocialUserCard>[],
    this.thumbnailSize = 96,
  });

  final Gig gig;
  final String venueName;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool stretchTrailing;
  final String? sub;
  final List<ExploreLineupBand>? lineup;
  final String? meta;
  final ExploreGigInfo? info;
  final List<Widget>? posterActions;
  final List<SocialUserCard> friends;
  final double thumbnailSize;

  @override
  Widget build(BuildContext context) {
    final style = flyerStyles[gig.flyKey] ?? flyerStyles['paper']!;
    final imageUrl = gig.flyerUrl;
    final dateLine =
        '${gig.startsAt.day} ${monthNamesUpper[gig.startsAt.month - 1]}'
        ' · ${gig.doorsLabel} · $venueName';
    final monoLine = meta ?? dateLine;
    final bands = lineup ?? const <ExploreLineupBand>[];
    final poster = SizedBox(
      width: thumbnailSize,
      height: double.infinity,
      child: EpNetworkImage(
        url: imageUrl,
        fit: BoxFit.cover,
        cacheWidth: thumbnailSize.round(),
        fallback: SizedBox.expand(
          child: SizedBox(
            height: thumbnailSize,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: 240,
                height: 300,
                child: GigFlyer(gig, style),
              ),
            ),
          ),
        ),
      ),
    );
    final thumbnail = posterActions == null
        ? poster
        : Stack(
            children: [
              poster,
              Positioned(
                top: 8,
                left: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < posterActions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.epColors.background.withValues(
                            alpha: .72,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(
                          dimension: 30,
                          child: Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: posterActions![i],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
    return _ExploreHairlineRow(
      semanticLabel: gig.title,
      onTap: onTap,
      minHeight: 44,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            thumbnail,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EpDisplay(gig.title, size: 18),
                      const SizedBox(height: 2),
                      if (info != null)
                        _ExploreGigInfoLine(info: info!)
                      else
                        Text(
                          meta == null ? monoLine : monoLine.toUpperCase(),
                          semanticsLabel: monoLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.epMeta.copyWith(
                            letterSpacing: 0.4,
                            color: context.epColors.muted,
                          ),
                        ),
                      if (friends.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ExploreAvatarStack(people: friends, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                friendsGoingLine(friends),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.epCaption
                                    .copyWith(color: context.epColors.muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  if (bands.isNotEmpty || sub != null) ...[
                    const Spacer(),
                    if (bands.isNotEmpty)
                      SizedBox(
                        height: 20,
                        child: ExploreLineupRow(bands: bands, onSeeAll: onTap),
                      )
                    else
                      Text(
                        sub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          color: context.epColors.muted,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (stretchTrailing && trailing != null)
              trailing!
            else
              Align(
                alignment: Alignment.center,
                child:
                    trailing ??
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: context.epColors.muted,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Large featured card used by the Explore recommendation carousel.
class ExploreFeaturedCard extends StatelessWidget {
  const ExploreFeaturedCard({
    super.key,
    required this.gig,
    required this.venueName,
    required this.onTap,
    this.friends = const <SocialUserCard>[],
    this.meta,
    this.lineup = const <ExploreLineupBand>[],
    this.width = 300,
    this.height = 380,
  });

  final Gig gig;
  final String venueName;
  final VoidCallback onTap;
  final List<SocialUserCard> friends;
  final String? meta;
  final List<ExploreLineupBand> lineup;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = flyerStyles[gig.flyKey] ?? flyerStyles['paper']!;
    final imageUrl = gig.flyerUrl;
    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: gig.title,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                EpNetworkImage(
                  url: imageUrl,
                  fit: BoxFit.cover,
                  cacheWidth: width.round(),
                  cacheHeight: height.round(),
                  fallback: GigFlyer(gig, style, width: width, height: height),
                )
              else
                GigFlyer(gig, style, width: width, height: height),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      context.epColors.background.withValues(alpha: 0),
                      context.epColors.background.withValues(alpha: .86),
                    ],
                  ),
                ),
              ),
              if (height < width)
                ..._landscapeContent(context, style)
              else
                _portraitContent(context, style),
            ],
          ),
        ),
      ),
    );
  }

  String get _venueLine => '$venueName · doors ${gig.doorsLabel}';

  Widget _portraitContent(BuildContext context, FlyerStyle style) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpDateBlock(date: gig.startsAt),
        const Spacer(),
        if (friends.isNotEmpty) ...[
          _friendsCueRow(context),
          const SizedBox(height: 8),
        ],
        EpDisplay(
          gig.title,
          size: 28,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          color: style.fg,
        ),
        const SizedBox(height: 6),
        EpMonoText(meta ?? _venueLine, color: context.epColors.muted),
        if (lineup.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExploreLineupRow(
            bands: lineup,
            tint: style.fg.withValues(alpha: .85),
            onSeeAll: onTap,
          ),
        ],
      ],
    ),
  );

  /// Date block pinned top-left; title and venue line bottom-left.
  List<Widget> _landscapeContent(BuildContext context, FlyerStyle style) {
    final venueStyle = Theme.of(context).textTheme.epChipLabel.copyWith(
      fontSize: 11,
      color: context.epColors.muted,
    );
    return [
      Positioned(top: 16, left: 16, child: EpDateBlock(date: gig.startsAt)),
      if (friends.isNotEmpty)
        Positioned(top: 16, right: 16, child: _friendsCueRow(context)),
      Positioned(
        left: 16,
        right: 16,
        bottom: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EpDisplay(
              gig.title,
              size: 24,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              color: style.fg,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    (meta ?? _venueLine).toUpperCase(),
                    semanticsLabel: meta ?? _venueLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: venueStyle,
                  ),
                ),
              ],
            ),
            if (lineup.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExploreLineupRow(
                bands: lineup,
                tint: style.fg.withValues(alpha: .85),
                onSeeAll: onTap,
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _friendsCueRow(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExploreAvatarStack(people: friends, size: 20),
      const SizedBox(width: 7),
      Text(
        _friendsCue(friends).toUpperCase(),
        semanticsLabel: _friendsCue(friends),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.epChipLabel.copyWith(
          fontSize: 11,
          color: context.epColors.muted,
        ),
      ),
    ],
  );
}

/// Location search-result row.
class ExploreLocationRow extends StatelessWidget {
  const ExploreLocationRow({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => EpMenuRow(
    icon: Icons.place_outlined,
    label: label,
    sub: 'Set as your location',
    onTap: onTap,
  );
}

/// Layout constants shared by [ExploreBandTile] and [exploreBandRailHeight],
/// so a rail can be sized to the tile's tallest possible content.
const _bandTileAvatarSize = 72.0;
const _bandTileAvatarGap = 6.0;
const _bandTileNameMaxLines = 3;
const _bandTileGenreGap = 2.0;
const _bandTileGenreMaxLines = 2;

/// The height a BANDS rail needs to show a default [ExploreBandTile] with its
/// name and genre lines fully wrapped at the current text scale, so the rail
/// leaves no dead space under shorter tiles.
double exploreBandRailHeight(BuildContext context) {
  final textTheme = Theme.of(context).textTheme;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  // The text engine rounds each line box to whole pixels, so round each line
  // up rather than the total: a fractional total can land a pixel short.
  double lineHeight(TextStyle style) =>
      (style.fontSize! * style.height! * scale).ceilToDouble();
  final text =
      lineHeight(textTheme.epLabel) * _bandTileNameMaxLines +
      lineHeight(textTheme.epMeta) * _bandTileGenreMaxLines;
  return _bandTileAvatarSize + _bandTileAvatarGap + _bandTileGenreGap + text;
}

/// Square avatar + name + genre line, for RECOMMENDED / BANDS rails.
/// Total width 120 wrapping a 72px avatar column by default; content is
/// left-aligned so the first avatar lines up with the section heading.
class ExploreBandTile extends StatelessWidget {
  const ExploreBandTile({
    super.key,
    required this.band,
    required this.onTap,
    this.width = 120,
    this.avatarSize = _bandTileAvatarSize,
  });

  final Band band;
  final VoidCallback onTap;
  final double width;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final imageUrl = band.profileImageUrl;
    final genres = band.genres.join(' · ');
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: band.name,
        child: GestureDetector(
          onTap: onTap,
          // The whole slot is tappable, including the gaps between avatar,
          // name and genres.
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EpAvatarTile(
                initials: band.initials,
                size: avatarSize,
                image: imageUrl == null || imageUrl.isEmpty
                    ? null
                    : NetworkImage(imageUrl),
              ),
              const SizedBox(height: _bandTileAvatarGap),
              Text(
                band.name,
                maxLines: _bandTileNameMaxLines,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.epLabel,
              ),
              if (genres.isNotEmpty) ...[
                const SizedBox(height: _bandTileGenreGap),
                Text(
                  genres,
                  maxLines: _bandTileGenreMaxLines,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: Theme.of(
                    context,
                  ).textTheme.epMeta.copyWith(color: context.epColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 160x200 flyer-styled cover card for a collection of gigs.
class ExploreCollectionCard extends StatelessWidget {
  const ExploreCollectionCard({
    super.key,
    required this.collection,
    required this.onTap,
  });

  final ExploreCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gig = collection.gigs.isEmpty ? null : collection.gigs.first;
    final imageUrl = gig?.flyerUrl;
    final style = flyerStyles[gig?.flyKey] ?? flyerStyles['paper']!;
    final eyebrow =
        '${collection.gigs.length} SHOW${collection.gigs.length == 1 ? '' : 'S'}';
    final titleStyle = Theme.of(
      context,
    ).textTheme.epDisplayAt(28).copyWith(color: style.fg, height: .95);

    return SizedBox(
      width: 160,
      height: 200,
      child: Semantics(
        button: true,
        label: collection.title,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                Image(image: NetworkImage(imageUrl), fit: BoxFit.cover)
              else
                EpPanel(height: 200, color: style.base, striped: true),
              if (imageUrl != null && imageUrl.isNotEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        context.epColors.background.withValues(alpha: 0),
                        context.epColors.background.withValues(alpha: .86),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EpEyebrow(eyebrow, color: style.fg),
                      const SizedBox(height: 4),
                      Text(
                        collection.title.toUpperCase(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ],
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

/// Image-backed venue card with venue details below the image.
class ExploreVenueTile extends StatelessWidget {
  const ExploreVenueTile({
    super.key,
    required this.entry,
    this.distance,
    this.width = 220,
    required this.onTap,
  });

  final VenueWithShows entry;
  final String? distance;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final venue = entry.venue;
    final area = venue.neighborhood ?? venue.area;
    final nextDate =
        '${entry.next.startsAt.day} '
        '${monthNamesUpper[entry.next.startsAt.month - 1]}';
    final showCount =
        '${entry.gigs.length} SHOW${entry.gigs.length == 1 ? '' : 'S'}';
    final placeholder = EpPanel(
      color: context.epColors.panel,
      child: const Center(child: EpEyebrow('NO PHOTO YET')),
    );
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: venue.name,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: entry.venue.photoUrls.isNotEmpty
                    ? EpNetworkImage(
                        url: entry.venue.photoUrls.first,
                        fit: BoxFit.cover,
                        cacheWidth: width.round(),
                        fallback: placeholder,
                      )
                    : placeholder,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EpDisplay(
                      venue.name,
                      size: 20,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      area,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.epMeta.copyWith(
                        color: context.epColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    EpDisplay(nextDate, size: 20),
                    EpMonoText(showCount, color: context.epColors.muted),
                    if (venue.verified || distance != null) ...[
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (venue.verified)
                              EpBadge(
                                key: Key(
                                  'explore-venue-tile-verified-${venue.id}',
                                ),
                                label: 'Verified',
                                variant: EpBadgeVariant.outline,
                              ),
                            if (venue.verified && distance != null)
                              const SizedBox(width: 6),
                            if (distance != null)
                              EpMonoText(
                                distance!,
                                color: context.epColors.muted,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The public band directory row, preserving the Explore screen behavior.
class ExploreBandRow extends StatelessWidget {
  const ExploreBandRow({super.key, required this.bandId, required this.app});

  final String bandId;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();
    final following = app.follows.contains(bandId);
    final imageUrl = band.profileImageUrl;
    return EpEntityRow(
      key: ValueKey('explore-band-card-$bandId'),
      leading: EpAvatarTile(
        initials: band.initials,
        image: imageUrl == null || imageUrl.isEmpty
            ? null
            : NetworkImage(imageUrl),
      ),
      title: band.name,
      sub: [
        if (band.genreLine.isNotEmpty) band.genreLine,
        '${band.followersLabel} ${band.followers == 1 ? 'fan' : 'fans'}',
      ].join(' · '),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 130),
        child: EpPill(
          key: ValueKey('explore-follow-$bandId'),
          label: following ? 'Following' : 'Follow',
          variant: EpPillVariant.outline,
          selected: following,
          onPressed: () => app.requestFollow(bandId),
        ),
      ),
      onTap: () => app.openBand(bandId),
    );
  }
}

/// The public band directory paging footer, preserving Explore behavior.
class ExploreBandPageStatus extends StatelessWidget {
  const ExploreBandPageStatus({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    if (app.exploreBandsLoading) {
      return Text(
        'Loading bands…',
        key: const Key('explore-bands-loading'),
        style: Theme.of(
          context,
        ).textTheme.epBody.copyWith(color: context.epColors.muted),
      );
    }
    if (app.exploreBandsError != null) {
      return Column(
        children: [
          Text(
            "Couldn't load more bands.",
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.muted),
          ),
          const SizedBox(height: 7),
          TextButton(
            key: const Key('explore-bands-retry'),
            onPressed: app.retryExploreBands,
            child: const EpMonoText('Retry'),
          ),
        ],
      );
    }
    if (app.hasMoreExploreBands) {
      return TextButton(
        key: const Key('explore-bands-load-more'),
        onPressed: app.loadMoreExploreBands,
        child: const EpMonoText('Load more bands'),
      );
    }
    return Text(
      'All bands loaded.',
      key: const Key('explore-bands-end'),
      style: Theme.of(
        context,
      ).textTheme.epBody.copyWith(color: context.epColors.muted),
    );
  }
}
