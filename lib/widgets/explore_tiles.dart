import 'package:flutter/material.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../explore_ranking.dart';
import '../flyer_styles.dart';
import '../models.dart';
import '../theme.dart';
import 'ep_rows.dart';
import 'ep_text.dart';

/// Square avatar + name + genre line, for RECOMMENDED / BANDS rails.
/// Total width 88 wrapping a 72px avatar column by default.
class ExploreBandTile extends StatelessWidget {
  const ExploreBandTile({
    super.key,
    required this.band,
    required this.onTap,
    this.avatarSize = 72,
  });

  final Band band;
  final VoidCallback onTap;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final imageUrl = band.profileImageUrl;
    final genres = band.genres.take(2).join(' · ');
    return SizedBox(
      width: 88,
      child: Semantics(
        button: true,
        label: band.name,
        child: GestureDetector(
          onTap: onTap,
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
              const SizedBox(height: 6),
              Text(
                band.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.epLabel,
              ),
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  genres,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

/// 168x120 typographic venue tile.
class ExploreVenueTile extends StatelessWidget {
  const ExploreVenueTile({
    super.key,
    required this.entry,
    this.distance,
    required this.onTap,
  });

  final VenueWithShows entry;
  final String? distance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final venue = entry.venue;
    final area = venue.neighborhood ?? venue.area;
    final nextLine =
        '${weekdayNamesUpper[entry.next.startsAt.weekday - 1]} '
        '${entry.next.startsAt.day} · ${entry.gigs.length} SHOW'
        '${entry.gigs.length == 1 ? '' : 'S'}';
    return SizedBox(
      width: 168,
      height: 120,
      child: Semantics(
        button: true,
        label: venue.name,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    8,
                    8,
                    venue.verified || distance != null ? 30 : 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: EpDisplay(
                          venue.name,
                          size: 20,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                      FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: EpMonoText(
                          nextLine,
                          color: context.epColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (venue.verified || distance != null)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (venue.verified)
                          EpBadge(
                            key: Key('explore-venue-tile-verified-${venue.id}'),
                            label: 'Verified',
                            variant: EpBadgeVariant.outline,
                          ),
                        if (venue.verified && distance != null)
                          const SizedBox(width: 6),
                        if (distance != null)
                          EpMonoText(distance!, color: context.epColors.muted),
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
