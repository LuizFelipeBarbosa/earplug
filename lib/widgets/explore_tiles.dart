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
        if (constraints.maxWidth.isFinite) {
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
            while (count > 0 &&
                used + 12 + seeAllWidth > constraints.maxWidth) {
              count--;
              used -= widths[count] + (count == 0 ? 0 : 12);
            }
          }
        }
        final visible = bands.take(count).toList();
        // Force the first band only when its avatar and a legible slice of its
        // name fit beside "See all"; otherwise the link stands alone.
        final firstChipOverflows =
            !allFit &&
            visible.isEmpty &&
            constraints.maxWidth >= 26 + 40 + 12 + seeAllWidth;
        final chips = <Widget>[
          if (firstChipOverflows)
            SizedBox(
              width: (constraints.maxWidth - 12 - seeAllWidth).clamp(
                0.0,
                double.infinity,
              ),
              child: _ExploreLineupChip(
                band: bands.first,
                textColor: tint,
                allowOverflow: true,
                shrinkToFit: true,
              ),
            ),
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            _ExploreLineupChip(
              band: visible[i],
              textColor: tint,
              allowOverflow: false,
            ),
          ],
        ];
        // The chip group sits in a non-scrolling horizontal viewport so a
        // font-metric mismatch between measurement and layout clips instead
        // of overflowing the row.
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            if (chips.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(mainAxisSize: MainAxisSize.min, children: chips),
                ),
              ),
            if (!allFit) ...[
              if (chips.isNotEmpty) const SizedBox(width: 12),
              // Scales down rather than overflowing when the slot is narrower
              // than the link at large text sizes.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    key: const Key('lineup-see-all'),
                    onTap: onSeeAll,
                    child: Text('See all', style: seeAllStyle),
                  ),
                ),
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
    final metricSpans = <TextSpan>[
      TextSpan(
        text: info.dateTime,
        style: label.copyWith(
          color: context.epColors.ink,
          fontWeight: FontWeight.bold,
        ),
      ),
      if (info.distance != null)
        TextSpan(
          text: info.distance,
          style: label.copyWith(color: context.epColors.ink),
        ),
      if (info.price != null)
        TextSpan(
          text: info.price,
          style: label.copyWith(
            color: context.epColors.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
    ];
    final spans = <InlineSpan>[];
    for (var i = 0; i < metricSpans.length; i++) {
      if (i > 0) spans.add(TextSpan(text: ' · ', style: muted));
      spans.add(metricSpans[i]);
    }
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
    this.shrinkToFit = false,
  });

  final ExploreLineupBand band;
  final Color? textColor;
  final bool allowOverflow;
  final bool shrinkToFit;

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
        SizedBox(width: shrinkToFit ? 4 : 6),
        if (allowOverflow && shrinkToFit)
          Flexible(
            child: Text(
              band.name,
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textColor == null
                  ? textStyle
                  : textStyle.copyWith(color: textColor),
            ),
          )
        else
          Text(
            band.name,
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.clip,
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
    this.actions,
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
  final List<Widget>? actions;
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
    final showChevron =
        (actions == null || actions!.isEmpty) && trailing == null;
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
    return _ExploreHairlineRow(
      semanticLabel: gig.title,
      onTap: onTap,
      minHeight: 44,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            poster,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (gig.lifecycle == GigLifecycle.cancelled) ...[
                    EpMonoText(
                      'CANCELLED',
                      key: ValueKey('gig-cancelled-${gig.id}'),
                      color: context.epColors.destructive,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EpDisplay(
                        gig.title,
                        size: 18,
                        overflow: TextOverflow.clip,
                      ),
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
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions!.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        SizedBox.square(
                          dimension: 28,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: actions![i],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
            if (trailing != null || showChevron) ...[
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

/// Layout constants shared by [ExploreVenueTile] and
/// [exploreVenueRailHeight], so the venues rail stays tall enough for the
/// tile's tallest possible content.
const _venueTileWidth = 220.0;
const _venueTileImageAspectRatio = 4 / 3;
const _venueTilePaddingHorizontal = 8.0;
const _venueTilePaddingTop = 6.0;
const _venueTilePaddingBottom = 4.0;
const _venueTileNameSize = 20.0;
const _venueTileNameMaxLines = 2;
const _venueTileDateSize = 20.0;
const _venueTileLineGap = 2.0;
const _venueTileInlineGap = 6.0;
const _venueTileAreaSeparator = ' · ';
const _venueTileAreaMinChars = 3;
// EpBadge wraps its mono label in two pixels of vertical padding and a
// one-pixel border on each side.
const _venueTileBadgeVerticalPadding = 4.0;
const _venueTileBadgeBorderHeight = 2.0;

/// The height a VENUES rail needs to show a default [ExploreVenueTile] with
/// its name fully wrapped, its metadata line with the Verified badge, and its
/// next-show line at the current text scale.
///
/// Each line is derived from the widgets the tile renders: the name is
/// [_venueTileNameMaxLines] display lines, the metadata line is the taller of
/// the meta text and the badge, and the next-show line is the taller of the
/// display date and the mono show count. Both rows centre their children, so
/// each row is exactly as tall as its tallest child.
double exploreVenueRailHeight(BuildContext context) {
  final textTheme = Theme.of(context).textTheme;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  // The text engine rounds each line box to whole pixels, so round each line
  // up rather than the total: a fractional total can land a pixel short.
  double lineHeight(TextStyle style) =>
      (style.fontSize! * style.height! * scale).ceilToDouble();

  const imageHeight = _venueTileWidth / _venueTileImageAspectRatio;
  final nameHeight =
      lineHeight(textTheme.epDisplayAt(_venueTileNameSize)) *
      _venueTileNameMaxLines;
  final monoHeight = lineHeight(textTheme.epChipLabel);
  final badgeHeight =
      monoHeight + _venueTileBadgeVerticalPadding + _venueTileBadgeBorderHeight;
  final metaHeight = lineHeight(textTheme.epMeta);
  final areaLineHeight = metaHeight > badgeHeight ? metaHeight : badgeHeight;
  final dateHeight = lineHeight(textTheme.epDisplayAt(_venueTileDateSize));
  final showsLineHeight = dateHeight > monoHeight ? dateHeight : monoHeight;

  return imageHeight +
      _venueTilePaddingTop +
      nameHeight +
      _venueTileLineGap +
      areaLineHeight +
      _venueTileLineGap +
      showsLineHeight +
      _venueTilePaddingBottom;
}

/// Image-backed venue card with venue details below the image.
class ExploreVenueTile extends StatelessWidget {
  const ExploreVenueTile({
    super.key,
    required this.entry,
    this.distance,
    this.width = _venueTileWidth,
    required this.onTap,
  });

  final VenueWithShows entry;
  final String? distance;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final venue = entry.venue;
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
                aspectRatio: _venueTileImageAspectRatio,
                child: venue.photoUrls.isNotEmpty
                    ? EpNetworkImage(
                        url: venue.photoUrls.first,
                        fit: BoxFit.cover,
                        cacheWidth: width.round(),
                        fallback: placeholder,
                      )
                    : placeholder,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  _venueTilePaddingHorizontal,
                  _venueTilePaddingTop,
                  _venueTilePaddingHorizontal,
                  _venueTilePaddingBottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EpDisplay(
                      venue.name,
                      size: _venueTileNameSize,
                      maxLines: _venueTileNameMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: _venueTileLineGap),
                    _VenueTileAreaLine(venue: venue, distance: distance),
                    const SizedBox(height: _venueTileLineGap),
                    _VenueTileShowsLine(
                      entry: entry,
                      maxWidth: width - 2 * _venueTilePaddingHorizontal,
                    ),
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

/// Area or neighbourhood, the distance, and the Verified badge on one line.
///
/// The area yields first when space runs out, down to its first
/// [_venueTileAreaMinChars] characters and an ellipsis; when even that leaves
/// no room beside the badge, the distance and its separator are dropped so
/// the row never overflows.
class _VenueTileAreaLine extends StatelessWidget {
  const _VenueTileAreaLine({required this.venue, required this.distance});

  final Venue venue;
  final String? distance;

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
    final area = venue.neighborhood ?? venue.area;
    final muted = Theme.of(
      context,
    ).textTheme.epMeta.copyWith(color: context.epColors.muted);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trailingWidth = distance == null
                  ? 0.0
                  : _textWidth(context, _venueTileAreaSeparator, muted) +
                        _textWidth(context, distance!, muted);
              final minAreaWidth = _textWidth(
                context,
                '${area.characters.take(_venueTileAreaMinChars)}…',
                muted,
              );
              final showDistance =
                  distance != null &&
                  trailingWidth + minAreaWidth <= constraints.maxWidth;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      area,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ),
                  if (showDistance) ...[
                    Text(_venueTileAreaSeparator, style: muted),
                    Text(distance!, style: muted),
                  ],
                ],
              );
            },
          ),
        ),
        if (venue.verified) ...[
          const SizedBox(width: _venueTileInlineGap),
          EpBadge(
            key: Key('explore-venue-tile-verified-${venue.id}'),
            label: 'Verified',
            variant: EpBadgeVariant.outline,
          ),
        ],
      ],
    );
  }
}

/// Bold next-show date left, mono show count right-aligned, on one line.
/// The date keeps its natural width up to [maxWidth]; the count yields first.
class _VenueTileShowsLine extends StatelessWidget {
  const _VenueTileShowsLine({required this.entry, required this.maxWidth});

  final VenueWithShows entry;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final next = entry.next.startsAt;
    final nextDate = '${next.day} ${monthNamesUpper[next.month - 1]}';
    final showCount =
        '${entry.gigs.length} SHOW${entry.gigs.length == 1 ? '' : 'S'}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Row children without a flex factor get an unbounded width, so the
        // date is capped explicitly to ellipsize instead of overflowing.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: EpDisplay(
            nextDate,
            size: _venueTileDateSize,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(left: _venueTileInlineGap),
            child: Text(
              showCount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.epChipLabel.copyWith(color: context.epColors.muted),
            ),
          ),
        ),
      ],
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
