import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_search_field.dart';
import '../widgets/ep_text.dart';
import '../widgets/friend_row.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _controller = TextEditingController();
  Timer? _searchTimer;
  String _query = '';

  @override
  void initState() {
    super.initState();
    context.read<AppState>().ensureSocial();
    unawaited(context.read<AppState>().loadSuggestedPeople());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _searchTimer?.cancel();
    setState(() => _query = value.trim());
    final app = context.read<AppState>();
    _searchTimer = Timer(
      const Duration(milliseconds: 250),
      () => app.searchPeople(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Material(
      key: const Key('people-screen'),
      color: context.epColors.background,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                EpLayout.gutter,
                EpLayout.isDesktop(context) ? 0 : 22,
                EpLayout.gutter,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      EpIconPill(
                        key: const Key('people-back-control'),
                        icon: Icons.arrow_back,
                        semanticLabel: 'Back',
                        onPressed: app.back,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const EpDisplay('Find people', size: 44),
                  if (app.authed) ...[
                    const SizedBox(height: 16),
                    EpSearchField(
                      fieldKey: const Key('people-search-field'),
                      clearKey: const Key('people-search-clear'),
                      controller: _controller,
                      hint: 'Search by name or email',
                      onChanged: _onQueryChanged,
                      onClear: () {
                        _controller.clear();
                        _onQueryChanged('');
                      },
                      radius: EpLayout.pillRadius,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: EpLayout.gutter,
                ),
                children: [
                  if (!app.authed)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sign in to find and follow people.',
                            style: Theme.of(context).textTheme.epBody.copyWith(
                              color: context.epColors.muted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          EpPill(
                            key: const Key('people-sign-in'),
                            label: 'Sign in',
                            variant: EpPillVariant.primary,
                            onPressed: () => app.needAuth(
                              const PendingAuth(PendingKind.myGigs),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_query.isEmpty) ...[
                    if (app.suggestedPeople.isNotEmpty) ...[
                      EpSectionHeader(
                        label: 'SUGGESTED · ${app.suggestedPeople.length}',
                      ),
                      for (final person in app.suggestedPeople)
                        EpEntityRow(
                          key: Key('people-suggested-${person.userId}'),
                          leading: EpFanAvatar(
                            name: person.name,
                            imageUrl: person.avatarUrl,
                            size: 40,
                          ),
                          title: person.name,
                          sub: _suggestedSub(person),
                          trailing: EpPill(
                            key: Key('people-follow-${person.userId}'),
                            label: 'Follow',
                            variant: EpPillVariant.outline,
                            onPressed: () =>
                                app.requestFollowUser(person.userId),
                          ),
                        ),
                    ],
                    EpSectionHeader(
                      label: 'YOUR FRIENDS · ${app.friendIds.length}',
                    ),
                    if (app.friendIds.isEmpty)
                      Text(
                        'No friends yet. Follow people you go to shows with.',
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          color: context.epColors.muted,
                        ),
                      )
                    else
                      for (final id in app.friendIds)
                        FriendRow(
                          userId: id,
                          rowKey: Key('people-result-$id'),
                          sub: 'Friends',
                        ),
                  ] else if (app.peopleSearching)
                    Text(
                      'Searching…',
                      style: Theme.of(context).textTheme.epBody.copyWith(
                        color: context.epColors.muted,
                      ),
                    )
                  else
                    for (final card in app.peopleResults)
                      EpEntityRow(
                        key: Key('people-result-${card.userId}'),
                        leading: EpFanAvatar(
                          name: card.name,
                          imageUrl: card.avatarUrl,
                          size: 40,
                        ),
                        title: card.name,
                        sub: card.isFriend
                            ? 'Friends'
                            : (card.followsMe ? 'Follows you' : null),
                        trailing: EpPill(
                          key: Key('people-follow-${card.userId}'),
                          label: card.isFollowing ? 'Following' : 'Follow',
                          variant: EpPillVariant.outline,
                          selected: card.isFollowing,
                          onPressed: () => app.requestFollowUser(card.userId),
                        ),
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

String? _suggestedSub(SuggestedPerson person) {
  final shows = person.sharedShows > 0
      ? '${person.sharedShows} ${person.sharedShows == 1 ? 'show' : 'shows'} together'
      : null;
  final friends = person.mutualFriends > 0
      ? '${person.mutualFriends} mutual ${person.mutualFriends == 1 ? 'friend' : 'friends'}'
      : null;
  if (shows != null && friends != null) return '$shows · $friends';
  return shows ?? friends;
}
