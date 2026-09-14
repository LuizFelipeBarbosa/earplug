import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_text.dart';
import 'explore_tiles.dart';

String friendsGoingLine(List<SocialUserCard> friends) {
  if (friends.isEmpty) return 'No friends are going';
  if (friends.length == 1) return '${friends[0].name} is going';
  if (friends.length == 2) {
    return '${friends[0].name} and ${friends[1].name} are going';
  }
  if (friends.length == 3) {
    return '${friends[0].name}, ${friends[1].name} and ${friends[2].name} are going';
  }
  return '${friends[0].name}, ${friends[1].name} and ${friends.length - 2} others are going';
}

/// "Where your friends are going this weekend" for the Explore page.
class ExploreFriendsSection extends StatelessWidget {
  const ExploreFriendsSection({
    super.key,
    required this.entries,
    required this.signedIn,
    required this.hasFriends,
    required this.onFindPeople,
    required this.onSignIn,
    required this.onOpenGig,
    required this.venueLine,
    this.onSeeAll,
    this.previewCount = 3,
    this.title = 'THIS WEEKEND · FRIENDS',
  });

  final List<({Gig gig, List<SocialUserCard> friends})> entries;
  final bool signedIn;
  final bool hasFriends;
  final VoidCallback onFindPeople;
  final VoidCallback onSignIn;
  final void Function(String gigId) onOpenGig;
  final String Function(Gig gig) venueLine;
  final VoidCallback? onSeeAll;
  final int previewCount;
  final String title;

  @override
  Widget build(BuildContext context) {
    final content = !signedIn
        ? EpMenuRow(
            key: const Key('explore-friends-sign-in'),
            icon: Icons.group_outlined,
            label: 'Sign in to see friends',
            sub: 'Follow people and see their weekend plans.',
            onTap: onSignIn,
          )
        : !hasFriends
        ? EpMenuRow(
            key: const Key('explore-find-people'),
            icon: Icons.group_outlined,
            label: 'Find people',
            sub: 'See where friends are going this weekend.',
            onTap: onFindPeople,
          )
        : entries.isEmpty
        ? EpMenuRow(
            key: const Key('explore-find-people'),
            icon: Icons.group_outlined,
            label: 'Find people',
            sub: 'See where friends are going this weekend.',
            onTap: onFindPeople,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EpSectionHeader(
                label: title,
                action: onSeeAll != null && entries.length > previewCount
                    ? 'SEE ALL'
                    : null,
                onAction: onSeeAll,
              ),
              for (final entry in entries.take(previewCount))
                ExploreEventRow(
                  key: Key('explore-friends-gig-${entry.gig.id}'),
                  gig: entry.gig,
                  venueName: venueLine(entry.gig),
                  trailing: ExploreAvatarStack(people: entry.friends),
                  sub: friendsGoingLine(entry.friends),
                  onTap: () => onOpenGig(entry.gig.id),
                ),
            ],
          );

    return Container(key: const Key('explore-friends'), child: content);
  }
}

class ExploreAvatarStack extends StatelessWidget {
  const ExploreAvatarStack({
    super.key,
    required this.people,
    this.size = 24,
    this.max = 3,
  });

  final List<SocialUserCard> people;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final count = people.length > max ? max : people.length;
    final overflow = people.length - count;
    final slots = count + (overflow > 0 ? 1 : 0);
    return SizedBox(
      width: size + (slots - 1) * size * .66,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * size * .66,
              child: EpFanAvatar(
                name: people[i].name,
                imageUrl: people[i].avatarUrl,
                size: size,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: count * size * .66,
              child: Container(
                width: size,
                height: size,
                color: context.epColors.panel,
                alignment: Alignment.center,
                child: EpMonoText('+$overflow', size: size * .42),
              ),
            ),
        ],
      ),
    );
  }
}
