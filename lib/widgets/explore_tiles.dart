import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../explore_ranking.dart';
import '../flyer_styles.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_text.dart';
import 'fan_event_card.dart' show GigCardLines;
import 'venue_mini_map.dart';

/// A gig-card action with a 36px ring or circle and a centered 44px target.
class ExploreCardIconButton extends StatelessWidget {
  const ExploreCardIconButton({
    super.key,
    required this.icon,
    this.fillIcon,
    required this.semanticLabel,
    required this.onPressed,
    this.ring = false,
    this.circle = false,
    this.active = false,
    this.color,
    this.iconShadows,
  });

  final IconData icon;
  final IconData? fillIcon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool ring;
  final bool circle;
  final bool active;
  final Color? color;
  final List<Shadow>? iconShadows;

  @override
  Widget build(BuildContext context) {
    final colors = context.epColors;
    final ink = onPressed == null ? colors.contentDisabled : colors.ink;
    final visualSize = ring || circle ? 36.0 : 28.0;
    final iconSize = ring || circle ? 20.0 : 16.0;
    final button = SizedBox.square(
      dimension: visualSize,
      child: OverflowBox(
        minWidth: 44,
        maxWidth: 44,
        minHeight: 44,
        maxHeight: 44,
        child: _ExploreCardActionTarget(
          child: Material(
            color: colors.background.withValues(alpha: 0),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Semantics(
                button: true,
                enabled: onPressed != null,
                label: semanticLabel,
                child: Center(
                  child: Container(
                    width: visualSize,
                    height: visualSize,
                    decoration: circle
                        ? const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Ep.background,
                          )
                        : ring
                        ? ShapeDecoration(
                            shape: CircleBorder(
                              side: BorderSide(color: colors.line, width: 1),
                            ),
                          )
                        : null,
                    child: Center(
                      child: SizedBox.square(
                        dimension: iconSize,
                        child: circle
                            ? Icon(icon, size: 20, color: Ep.ink)
                            : ring
                            ? Icon(
                                icon,
                                size: 20,
                                color: onPressed == null
                                    ? colors.contentDisabled
                                    : active
                                    ? colors.accent
                                    : colors.muted,
                              )
                            : Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (fillIcon != null)
                                    Icon(
                                      fillIcon,
                                      size: 16,
                                      color: active
                                          ? (color ?? colors.accent).withValues(
                                              alpha: 0.60,
                                            )
                                          : (color ?? colors.ink).withValues(
                                              alpha: 0.22,
                                            ),
                                    ),
                                  Icon(
                                    icon,
                                    size: 16,
                                    color: color ?? ink,
                                    shadows: iconShadows,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return _ExploreCardActionHitRegion(child: button);
  }
}

// OverflowBox expands painting and semantics, but its smaller ancestors still
// reject out-of-bounds pointers. At the card boundary, hit-test the actual
// 44px targets first so the surrounding layout cannot discard those taps.
class _ExploreCardActionHitRegion extends SingleChildRenderObjectWidget {
  const _ExploreCardActionHitRegion({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExploreCardActionHitRegion();
}

class _RenderExploreCardActionHitRegion extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    _RenderExploreCardActionTarget? nearest;
    var nearestDistance = double.infinity;
    void findTarget(RenderObject object) {
      if (object is _RenderExploreCardActionTarget) {
        final bounds = MatrixUtils.transformRect(
          object.getTransformTo(this),
          Offset.zero & object.size,
        );
        final distance = (bounds.center - position).distanceSquared;
        // Adjacent targets overlap; let the closest button own the tap.
        if (bounds.contains(position) && distance < nearestDistance) {
          nearest = object;
          nearestDistance = distance;
        }
      } else {
        object.visitChildren(findTarget);
      }
    }

    visitChildren(findTarget);
    final target = nearest;
    if (target != null &&
        result.addWithPaintTransform(
          transform: target.getTransformTo(this),
          position: position,
          hitTest: (result, position) =>
              target.hitTest(result, position: position),
        )) {
      return true;
    }
    return super.hitTest(result, position: position);
  }
}

class _ExploreCardActionTarget extends SingleChildRenderObjectWidget {
  const _ExploreCardActionTarget({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExploreCardActionTarget();
}

class _RenderExploreCardActionTarget extends RenderProxyBox {}

class _ExploreHairlineRow extends StatelessWidget {
  const _ExploreHairlineRow({
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.minHeight = 44,
    this.showHairline = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double minHeight;
  final bool showHairline;

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
        if (showHairline) const EpHairline(),
      ],
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Compact recommendation-feed event row.
class ExploreEventRow extends StatelessWidget {
  const ExploreEventRow({
    super.key,
    required this.gig,
    required this.venueName,
    required this.lines,
    required this.onTap,
    this.saveAction,
    this.sub,
    this.thumbnailSize = 96,
    this.showHairline = true,
  });

  final Gig gig;
  final String venueName;
  final GigCardLines lines;
  final VoidCallback onTap;
  final Widget? saveAction;
  final String? sub;
  final double thumbnailSize;
  final bool showHairline;

  @override
  Widget build(BuildContext context) {
    final style = flyerStyles[gig.flyKey] ?? flyerStyles['paper']!;
    final imageUrl = gig.flyerUrl;
    final poster = SizedBox(
      width: thumbnailSize,
      // The row stretches the poster to the text height; the poster must not
      // contribute its own height during the intrinsic measurement.
      height: 0,
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
    return _EventRowBody(
      id: gig.id,
      title: gig.title,
      lines: lines,
      cancelled: gig.lifecycle == GigLifecycle.cancelled,
      thumbnail: poster,
      priceChip: _GigPriceChip(gig: gig, price: lines.price),
      saveAction: saveAction,
      sub: sub,
      onTap: onTap,
      showHairline: showHairline,
    );
  }
}

/// Snapshot counterpart to [ExploreEventRow], without saved-event controls.
class ExploreEventSnapshotRow extends StatelessWidget {
  const ExploreEventSnapshotRow({
    super.key,
    required this.id,
    required this.lines,
    this.flyerUrl,
    this.flyKey,
    this.onTap,
  });

  final String id;
  final GigCardLines lines;
  final String? flyerUrl;
  final String? flyKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const thumbnailSize = 96.0;
    final style = flyerStyles[flyKey] ?? flyerStyles['paper']!;
    final poster = SizedBox(
      width: thumbnailSize,
      height: 0,
      child: EpNetworkImage(
        url: flyerUrl,
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
                child: FlyerBox(style: style),
              ),
            ),
          ),
        ),
      ),
    );
    return _EventRowBody(
      id: id,
      title: lines.title,
      lines: lines,
      cancelled: false,
      thumbnail: poster,
      priceChip: lines.price.isEmpty
          ? null
          : Text(
              lines.price.toUpperCase(),
              key: ValueKey('snapshot-price-$id'),
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.epChipLabel.copyWith(fontSize: 13),
            ),
      onTap: onTap,
    );
  }
}

/// Shared layout for full gigs and historical event snapshots.
class _EventRowBody extends StatelessWidget {
  const _EventRowBody({
    required this.id,
    required this.title,
    required this.lines,
    required this.cancelled,
    required this.thumbnail,
    required this.onTap,
    this.priceChip,
    this.saveAction,
    this.sub,
    this.showHairline = true,
  });

  final String id;
  final String title;
  final GigCardLines lines;
  final bool cancelled;
  final Widget thumbnail;
  final VoidCallback? onTap;
  final Widget? priceChip;
  final Widget? saveAction;
  final String? sub;
  final bool showHairline;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dateLine = Text(
      lines.dateLine,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.epLabel.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: context.epColors.muted,
      ),
    );
    final textColumn = Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cancelled) ...[
          EpMonoText(
            'CANCELLED',
            key: ValueKey('gig-cancelled-$id'),
            color: context.epColors.destructive,
          ),
          const SizedBox(height: 4),
        ],
        if (saveAction != null)
          Padding(padding: const EdgeInsets.only(right: 44), child: dateLine)
        else
          dateLine,
        const SizedBox(height: 8),
        if (saveAction != null)
          Padding(
            padding: const EdgeInsets.only(right: 44),
            child: EpDisplay(title, size: 18, overflow: TextOverflow.clip),
          )
        else
          EpDisplay(title, size: 18, overflow: TextOverflow.clip),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                lines.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.epCaption.copyWith(
                  color: context.epColors.muted,
                ),
              ),
            ),
            if (priceChip != null) ...[const SizedBox(width: 8), priceChip!],
          ],
        ),
        if (sub != null) ...[
          const SizedBox(height: 8),
          Text(
            sub!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.epBody.copyWith(color: context.epColors.muted),
          ),
        ],
      ],
    );
    final row = _ExploreHairlineRow(
      semanticLabel: title,
      onTap: onTap,
      minHeight: 44,
      showHairline: showHairline,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            thumbnail,
            const SizedBox(width: 12),
            Expanded(
              child: saveAction == null
                  ? textColumn
                  : Stack(
                      clipBehavior: Clip.none,
                      children: [
                        textColumn,
                        Positioned(top: 0, right: 0, child: saveAction!),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
    return _ExploreCardActionHitRegion(child: row);
  }
}

class _GigPriceChip extends StatelessWidget {
  const _GigPriceChip({required this.gig, required this.price});

  final Gig gig;
  final String price;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.epChipLabel;
    final colors = context.epColors;
    return Container(
      key: ValueKey('gig-price-${gig.id}'),
      color: colors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        price.toUpperCase(),
        style: labelStyle.copyWith(fontSize: 13, color: colors.onAccent),
      ),
    );
  }
}

/// Large featured card shared by Home and the Explore recommendation carousel.
class ExploreFeaturedCard extends StatelessWidget {
  const ExploreFeaturedCard({
    super.key,
    required this.gig,
    required this.venueName,
    required this.onTap,
    required this.lines,
    this.actions = const [],
    this.width = 300,
    this.height = 380,
  });

  final Gig gig;
  final String venueName;
  final VoidCallback onTap;
  final GigCardLines lines;
  final List<Widget> actions;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = flyerStyles[gig.flyKey] ?? flyerStyles['paper']!;
    final imageUrl = gig.flyerUrl;
    final textTheme = Theme.of(context).textTheme;
    final card = SizedBox(
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
                      Ep.background.withValues(alpha: 0),
                      Ep.background.withValues(alpha: .94),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lines.dateLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.epLabel.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Ep.ink.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    EpDisplay(
                      gig.title,
                      size: 24,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      color: Ep.ink,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lines.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.epBody.copyWith(
                              color: Ep.ink.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _GigPriceChip(gig: gig, price: lines.price),
                      ],
                    ),
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        actions[i],
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return _ExploreCardActionHitRegion(child: card);
  }
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

/// Layout constants for [ExploreBandTile.compact] and
/// [exploreCompactBandRailHeight]: a 56px avatar over a single name line.
const exploreCompactBandTileWidth = 88.0;
const exploreCompactBandTileAvatarSize = 56.0;
const _compactBandTileAvatarGap = 4.0;
const _compactBandTileNameSize = 11.0;

/// The height a rail of [ExploreBandTile.compact] tiles needs at the current
/// text scale: the avatar, its gap, and one line of the name.
double exploreCompactBandRailHeight(BuildContext context) {
  final nameStyle = Theme.of(context).textTheme.epLabel;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final nameLine = (_compactBandTileNameSize * nameStyle.height! * scale)
      .ceilToDouble();
  return exploreCompactBandTileAvatarSize +
      _compactBandTileAvatarGap +
      nameLine;
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
  }) : compact = false;

  /// The scaled-down tile for the Explore rail: 56px avatar and the name on
  /// one line, no genres.
  const ExploreBandTile.compact({
    super.key,
    required this.band,
    required this.onTap,
  }) : width = exploreCompactBandTileWidth,
       avatarSize = exploreCompactBandTileAvatarSize,
       compact = true;

  final Band band;
  final VoidCallback onTap;
  final double width;
  final double avatarSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final imageUrl = band.profileImageUrl;
    final genres = compact ? '' : band.genres.join(' · ');
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
              if (compact) ...[
                const SizedBox(height: _compactBandTileAvatarGap),
                EpMonoText(
                  band.name,
                  size: _compactBandTileNameSize,
                  weight: FontWeight.w500,
                  keepCase: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else ...[
                const SizedBox(height: _bandTileAvatarGap),
                Text(
                  band.name,
                  maxLines: _bandTileNameMaxLines,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: Theme.of(context).textTheme.epLabel,
                ),
              ],
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

/// Layout constants shared by [ExploreVenueTile] and
/// [exploreVenueRailHeight], so the venues rail matches the tile's fixed slots.
const _venueTileWidth = 220.0;
const _venueTileMapAspectRatio = 2.0;
const _venueTileMapTextGap = 14.0;
const _venueTilePaddingBottom = 4.0;
const _venueTileNameSize = 20.0;
const _venueTileNameMaxLines = 2;
const _venueTileLineGap = 2.0;
const _venueTileAreaSeparator = ' · ';
const _venueTileAreaMinChars = 3;

({double nameHeight, double areaHeight}) _venueTileTextHeights(
  BuildContext context,
) {
  final textTheme = Theme.of(context).textTheme;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  // The text engine rounds each line box to whole pixels, so round each line
  // up rather than the total: a fractional total can land a pixel short.
  double lineHeight(TextStyle style) =>
      (style.fontSize! * style.height! * scale).ceilToDouble();

  return (
    nameHeight:
        lineHeight(textTheme.epDisplayAt(_venueTileNameSize)) *
        _venueTileNameMaxLines,
    areaHeight: lineHeight(textTheme.epMeta),
  );
}

/// The exact height of a default-width [ExploreVenueTile] at the current text
/// scale, computed from the same fixed text slots the tile renders.
double exploreVenueRailHeight(BuildContext context) {
  final heights = _venueTileTextHeights(context);
  const mapHeight = _venueTileWidth / _venueTileMapAspectRatio;

  return mapHeight +
      _venueTileMapTextGap +
      heights.nameHeight +
      _venueTileLineGap +
      heights.areaHeight +
      _venueTilePaddingBottom;
}

/// Venue map with the show count above the name and area/distance rows.
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
    final venueLabel = venue.name.trim().isEmpty ? venue.addr : venue.name;
    final heights = _venueTileTextHeights(context);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: venueLabel,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VenueMapPreview(
                key: const Key('venue-tile-map'),
                venue: venue,
                showAttribution: false,
                height: width / _venueTileMapAspectRatio,
                overlayLabel:
                    '${entry.gigs.length} SHOW${entry.gigs.length == 1 ? '' : 'S'}',
              ),
              Padding(
                padding: const EdgeInsets.only(
                  top: _venueTileMapTextGap,
                  bottom: _venueTilePaddingBottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: heights.nameHeight,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: EpDisplay(
                          venueLabel,
                          size: _venueTileNameSize,
                          maxLines: _venueTileNameMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: _venueTileLineGap),
                    SizedBox(
                      height: heights.areaHeight,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _VenueTileAreaLine(
                          venue: venue,
                          distance: distance,
                        ),
                      ),
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

/// Area or neighbourhood and the distance on one line.
///
/// The area yields first when space runs out, down to its first
/// [_venueTileAreaMinChars] characters and an ellipsis; when even that leaves
/// no room for the distance, it and its separator are dropped so the row
/// never overflows.
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
    return LayoutBuilder(
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
              Text(
                _venueTileAreaSeparator,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
              Text(
                distance!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ],
          ],
        );
      },
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
