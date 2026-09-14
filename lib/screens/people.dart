import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';

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
      color: context.epColors.background,
      child: Column(
        key: const Key('people-screen'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              EpLayout.gutter,
              EpLayout.isDesktop(context) ? 0 : headerTopPad(context),
              EpLayout.gutter,
              0,
            ),
            child: EpIconPill(
              key: const ValueKey('people-back-control'),
              icon: Icons.arrow_back,
              semanticLabel: 'Back',
              onPressed: app.back,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              EpLayout.gutter,
              20,
              EpLayout.gutter,
              0,
            ),
            child: EpDisplay('People', size: 44),
          ),
          if (!app.authed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EpLayout.gutter,
                24,
                EpLayout.gutter,
                0,
              ),
              child: EpPanel(
                striped: true,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EpEyebrow('PEOPLE'),
                    const SizedBox(height: 10),
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
                      onPressed: () =>
                          app.needAuth(const PendingAuth(PendingKind.myGigs)),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EpLayout.gutter,
                16,
                EpLayout.gutter,
                0,
              ),
              child: EpUnderlineField(
                fieldKey: const Key('people-search-field'),
                icon: Icons.search,
                hint: 'Search by name or email',
                controller: _controller,
                onChanged: _onQueryChanged,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  EpLayout.gutter,
                  0,
                  EpLayout.gutter,
                  0,
                ),
                children: [
                  if (_query.isEmpty)
                    if (app.friendIds.isEmpty)
                      Text(
                        'No friends yet. Search for people you know.',
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          color: context.epColors.muted,
                        ),
                      )
                    else ...[
                      EpSectionHeader(
                        label: 'YOUR FRIENDS · ${app.friendIds.length}',
                      ),
                      for (final id in app.friendIds) _FriendRow(userId: id),
                    ]
                  else if (app.peopleSearching)
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
        ],
      ),
    );
  }
}

class _FriendRow extends StatefulWidget {
  const _FriendRow({required this.userId});
  final String userId;
  @override
  State<_FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends State<_FriendRow> {
  late final Future<SocialUserDetail?> _future;
  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadUserCard(widget.userId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SocialUserDetail?>(
    future: _future,
    builder: (context, snapshot) {
      final detail = snapshot.data;
      return EpEntityRow(
        key: Key('people-result-${widget.userId}'),
        leading: EpFanAvatar(
          name: detail?.name,
          imageUrl: detail?.avatarUrl,
          size: 40,
        ),
        title: detail?.name ?? '...',
        sub: 'Friends',
      );
    },
  );
}
