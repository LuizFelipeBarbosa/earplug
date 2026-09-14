import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_text.dart';

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
    this.previewCount = 4,
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

  @override
  Widget build(BuildContext context) {
    final content = !signedIn
        ? _InfoPanel(
            body: 'See where the people you follow are going.',
            action: EpPill(
              key: const Key('explore-friends-sign-in'),
              label: 'Sign in to see friends',
              onPressed: onSignIn,
            ),
          )
        : !hasFriends
        ? _InfoPanel(
            body:
                'Follow people and, when they follow you back, their weekend plans show up here.',
            action: EpPill(
              key: const Key('explore-find-people'),
              label: 'Find people',
              variant: EpPillVariant.primary,
              onPressed: onFindPeople,
            ),
          )
        : entries.isEmpty
        ? _InfoPanel(
            body: "No friends have RSVP'd for this weekend yet.",
            action: EpPill(
              key: const Key('explore-find-people'),
              label: 'Find people',
              variant: EpPillVariant.primary,
              onPressed: onFindPeople,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EpSectionHeader(
                label: 'THIS WEEKEND · FRIENDS',
                action: onSeeAll != null && entries.length > previewCount
                    ? 'SEE ALL'
                    : null,
                onAction: onSeeAll,
              ),
              for (final entry in entries.take(previewCount))
                EpGigRow(
                  key: Key('explore-friends-gig-${entry.gig.id}'),
                  date: entry.gig.startsAt,
                  title: entry.gig.title,
                  meta: venueLine(entry.gig),
                  sub: _friendsLine(entry.friends),
                  trailing: ExploreAvatarStack(people: entry.friends),
                  onTap: () => onOpenGig(entry.gig.id),
                ),
            ],
          );

    return Container(key: const Key('explore-friends'), child: content);
  }

  String _friendsLine(List<SocialUserCard> friends) {
    if (friends.length == 1) return '${friends[0].name} is going';
    if (friends.length == 2)
      return '${friends[0].name}, ${friends[1].name} going';
    return '${friends[0].name}, ${friends[1].name} +${friends.length - 2} going';
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.body, required this.action});

  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) => EpPanel(
    striped: true,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EpEyebrow('FRIENDS'),
        const SizedBox(height: 10),
        Text(
          body,
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
        ),
        const SizedBox(height: 16),
        action,
      ],
    ),
  );
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
