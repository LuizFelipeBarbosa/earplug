import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/explore_friends.dart';
import '../widgets/explore_tiles.dart';
import '../widgets/fan_event_card.dart';

class ExploreCollectionScreen extends StatefulWidget {
  const ExploreCollectionScreen({super.key, required this.collectionKey});

  final String? collectionKey;

  @override
  State<ExploreCollectionScreen> createState() =>
      _ExploreCollectionScreenState();
}

class _ExploreCollectionScreenState extends State<ExploreCollectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      if (widget.collectionKey == 'bands') app.ensureExploreBands();
      if (widget.collectionKey == 'friends') app.ensureSocial();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final key = widget.collectionKey;
    final content = key == 'bands'
        ? _CollectionContent(
            title: 'All bands',
            subtitle: _countLabel(app.exploreBandIds.length, 'band'),
            body: _bandsBody(app),
          )
        : key == 'venues'
        ? _CollectionContent(
            title: 'Venues with shows',
            subtitle: _countLabel(app.exploreHome.venues.length, 'venue'),
            body: _venuesBody(app),
          )
        : key == 'friends'
        ? _CollectionContent(
            title: 'Friends this weekend',
            subtitle: _countLabel(app.friendsGoing.length, 'show'),
            body: _friendsBody(app),
          )
        : _gigCollection(app, key);

    return Column(
      key: const Key('explore-collection-screen'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            EpLayout.gutter,
            EpLayout.isDesktop(context) ? 0 : headerTopPad(context),
            EpLayout.gutter,
            0,
          ),
          child: Row(
            children: [
              EpIconPill(
                key: const ValueKey('explore-collection-back-control'),
                icon: Icons.arrow_back,
                semanticLabel: 'Back',
                onPressed: app.back,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EpLayout.gutter,
            20,
            EpLayout.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EpDisplay(content.title, size: 32),
              const SizedBox(height: 12),
              EpEyebrow(content.subtitle),
            ],
          ),
        ),
        Expanded(child: content.body),
      ],
    );
  }

  _CollectionContent _gigCollection(AppState app, String? key) {
    final collection = key == null ? null : app.exploreCollection(key);
    if (collection == null) {
      return const _CollectionContent(
        title: 'Collection',
        subtitle: '',
        body: _MutedMessage("This collection isn't available."),
      );
    }
    return _CollectionContent(
      title: collection.title,
      subtitle: _countLabel(collection.gigs.length, 'show'),
      body: collection.gigs.isEmpty
          ? const _MutedMessage('Nothing here right now.')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                EpLayout.gutter,
                20,
                EpLayout.gutter,
                0,
              ),
              itemCount: collection.gigs.length + 1,
              itemBuilder: (context, index) => index == collection.gigs.length
                  ? const SizedBox(height: tabBarClearance)
                  : FanEventCard(
                      gig: collection.gigs[index],
                      app: app,
                      showDistance: true,
                    ),
            ),
    );
  }

  Widget _bandsBody(AppState app) => ListView.builder(
    key: const Key('explore-all-bands'),
    padding: const EdgeInsets.fromLTRB(EpLayout.gutter, 20, EpLayout.gutter, 0),
    itemCount: app.exploreBandIds.length + 2,
    itemBuilder: (context, index) {
      if (index == app.exploreBandIds.length + 1) {
        return const SizedBox(height: tabBarClearance);
      }
      if (index == app.exploreBandIds.length) {
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ExploreBandPageStatus(app: app),
        );
      }
      return ExploreBandRow(bandId: app.exploreBandIds[index], app: app);
    },
  );

  Widget _venuesBody(AppState app) {
    final venues = app.exploreHome.venues;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        EpLayout.gutter,
        20,
        EpLayout.gutter,
        0,
      ),
      itemCount: venues.length + 1,
      itemBuilder: (context, index) {
        if (index == venues.length) {
          return const SizedBox(height: tabBarClearance);
        }
        final entry = venues[index];
        final venue = entry.venue;
        final next = entry.next.startsAt;
        return EpEntityRow(
          key: Key('explore-venue-${venue.id}'),
          leading: const SizedBox.shrink(),
          title: venue.name,
          sub:
              '${venue.neighborhood ?? venue.area} · next ${weekdayNamesUpper[next.weekday - 1]} ${next.day}',
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (venue.verified) ...[
                const EpBadge(
                  label: 'Verified',
                  variant: EpBadgeVariant.outline,
                ),
                const SizedBox(height: 4),
              ],
              EpMonoText(app.distanceOf(venue), color: context.epColors.muted),
            ],
          ),
          onTap: () => app.openVenue(venue.id),
        );
      },
    );
  }

  Widget _friendsBody(AppState app) {
    final entries = app.friendsGoing;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          EpLayout.gutter,
          20,
          EpLayout.gutter,
          tabBarClearance,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _MutedMessage("No friends have RSVP'd for this weekend yet."),
            const SizedBox(height: 16),
            EpPill(
              label: 'Find people',
              onPressed: () => app.go(Screen.people),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        EpLayout.gutter,
        20,
        EpLayout.gutter,
        0,
      ),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return const SizedBox(height: tabBarClearance);
        }
        final entry = entries[index];
        return EpGigRow(
          key: Key('explore-friends-gig-${entry.gig.id}'),
          date: entry.gig.startsAt,
          title: entry.gig.title,
          meta: app.venue(entry.gig.venueId).name,
          sub: _friendsLine(entry.friends),
          trailing: ExploreAvatarStack(people: entry.friends),
          onTap: () => app.openGig(entry.gig.id),
        );
      },
    );
  }

  String _friendsLine(List<SocialUserCard> friends) {
    if (friends.length == 1) return '${friends.first.name} going';
    if (friends.length == 2) {
      return '${friends[0].name}, ${friends[1].name} going';
    }
    return '${friends.first.name}, ${friends[1].name} +${friends.length - 2} going';
  }

  String _countLabel(int count, String noun) =>
      '$count $noun${count == 1 ? '' : 's'}';
}

class _CollectionContent {
  const _CollectionContent({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final Widget body;
}

class _MutedMessage extends StatelessWidget {
  const _MutedMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      EpLayout.gutter,
      20,
      EpLayout.gutter,
      tabBarClearance,
    ),
    child: Text(
      message,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.epBody.copyWith(color: context.epColors.muted),
    ),
  );
}
