part of '../app_state.dart';

mixin _SocialState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  bool get authed;
  Map<String, Gig> get _gigIndex;
  UserProfile? get profile;
  set profile(UserProfile? value);
  void needAuth(PendingAuth p);

  SocialGraph social = SocialGraph.empty;
  bool socialLoaded = false;
  DataStatus friendsStatus = DataStatus.connecting;
  bool friendsGoingTruncated = false;
  List<SocialUserCard> peopleResults = const [];
  bool peopleSearching = false;
  Map<String, KnownAttendees> knownAttendeesByGig = const {};
  final Map<String, Object> _knownAttendeesLoadTokens = {};

  KnownAttendees? knownAttendeesFor(String gigId) => knownAttendeesByGig[gigId];

  List<FriendsGoingEntry> _friendsGoingEntries = const [];
  bool _friendsGoingLoaded = false;
  bool _socialEnsured = false;
  Object _socialSessionToken = Object();
  Object? _socialLoadToken;
  Object? _friendsGoingLoadToken;
  Object? _peopleSearchToken;

  final Memo<
    ({List<FriendsGoingEntry> entries, Map<String, Gig> gigIndex}),
    List<({Gig gig, List<SocialUserCard> friends})>
  >
  _friendsGoingMemo = Memo();

  Set<String> get friendIds => social.friends;
  bool get hasFriends => social.friends.isNotEmpty;
  bool isFollowingUser(String userId) => social.following.contains(userId);

  List<({Gig gig, List<SocialUserCard> friends})> get friendsGoing {
    final inputs = (entries: _friendsGoingEntries, gigIndex: _gigIndex);
    return _friendsGoingMemo(inputs, () {
      final joined = <({Gig gig, List<SocialUserCard> friends})>[];
      for (final entry in inputs.entries) {
        final gig = inputs.gigIndex[entry.gigId];
        if (gig == null) continue;
        joined.add((
          gig: gig,
          friends: List<SocialUserCard>.unmodifiable(entry.friends),
        ));
      }
      joined.sort((a, b) {
        final count = b.friends.length.compareTo(a.friends.length);
        return count == 0 ? a.gig.startsAt.compareTo(b.gig.startsAt) : count;
      });
      return List<({Gig gig, List<SocialUserCard> friends})>.unmodifiable(
        joined,
      );
    });
  }

  void ensureSocial() {
    if (_socialEnsured || _disposed) return;
    _socialEnsured = true;
    unawaited(loadSocial());
    unawaited(loadFriendsGoing());
  }

  Future<void> loadSocial({bool refresh = false}) async {
    if (_disposed || !authed || (socialLoaded && !refresh)) return;
    final sessionToken = _socialSessionToken;
    final loadToken = Object();
    _socialLoadToken = loadToken;
    if (friendsStatus != DataStatus.ready) {
      friendsStatus = DataStatus.connecting;
      notifyListeners();
    }
    try {
      final result = await repository.mySocial();
      if (_disposed ||
          !identical(_socialSessionToken, sessionToken) ||
          !identical(_socialLoadToken, loadToken)) {
        return;
      }
      social = result;
      socialLoaded = true;
      friendsStatus = DataStatus.ready;
      notifyListeners();
    } catch (error) {
      if (_disposed ||
          !identical(_socialSessionToken, sessionToken) ||
          !identical(_socialLoadToken, loadToken)) {
        return;
      }
      logError('mySocial', error);
      friendsStatus = DataStatus.error;
      notifyListeners();
    }
  }

  Future<void> loadFriendsGoing({bool refresh = false}) async {
    if (_disposed || !authed || (_friendsGoingLoaded && !refresh)) return;
    final sessionToken = _socialSessionToken;
    final loadToken = Object();
    _friendsGoingLoadToken = loadToken;
    final now = _now();
    final from = DateTime(now.year, now.month, now.day, now.hour);
    final to = from.add(const Duration(days: 14));
    try {
      final result = await repository.friendsGoing(from: from, to: to);
      if (_disposed ||
          !identical(_socialSessionToken, sessionToken) ||
          !identical(_friendsGoingLoadToken, loadToken)) {
        return;
      }
      _friendsGoingEntries = List<FriendsGoingEntry>.unmodifiable(
        result.entries,
      );
      friendsGoingTruncated = result.truncated;
      _friendsGoingLoaded = true;
      notifyListeners();
    } catch (error) {
      if (_disposed ||
          !identical(_socialSessionToken, sessionToken) ||
          !identical(_friendsGoingLoadToken, loadToken)) {
        return;
      }
      logError('friendsGoing', error);
    }
  }

  Future<KnownAttendees> loadKnownAttendees(String gigId) async {
    final cached = knownAttendeesByGig[gigId];
    if (cached != null) return cached;
    if (_disposed || !authed) return KnownAttendees.empty;
    final sessionToken = _socialSessionToken;
    final token = Object();
    _knownAttendeesLoadTokens[gigId] = token;
    try {
      final result = await repository.knownAttendees(gigId, now: _now());
      if (_disposed ||
          !identical(_socialSessionToken, sessionToken) ||
          !identical(_knownAttendeesLoadTokens[gigId], token)) {
        return knownAttendeesByGig[gigId] ?? result;
      }
      knownAttendeesByGig = {...knownAttendeesByGig, gigId: result};
      notifyListeners();
      return result;
    } catch (error) {
      logError('knownAttendees', error);
      return knownAttendeesByGig[gigId] ?? KnownAttendees.empty;
    }
  }

  void toggleFollowUser(String userId) {
    final previousSocial = social;
    final previousResults = peopleResults;
    final wasOn = social.following.contains(userId);
    final createsFriendship = !wasOn && social.followers.contains(userId);
    final nextFollowing = wasOn
        ? ({...social.following}..remove(userId))
        : {...social.following, userId};
    social = social.copyWith(following: nextFollowing);
    final nowFollowing = !wasOn;
    final nowFriend = social.friends.contains(userId);
    peopleResults = [
      for (final card in peopleResults)
        card.userId == userId
            ? card.copyWith(isFollowing: nowFollowing, isFriend: nowFriend)
            : card,
    ];
    notifyListeners();

    if (createsFriendship) {
      unawaited(loadFriendsGoing(refresh: true));
    }
    final name = peopleResults
        .where((card) => card.userId == userId)
        .map((card) => card.name)
        .firstOrNull;
    unawaited(
      repository
          .toggleFollowUser(userId, on: nowFollowing)
          .then((_) {
            say(
              nowFollowing
                  ? name == null || name.isEmpty
                        ? 'Following.'
                        : 'Following $name.'
                  : 'Unfollowed.',
            );
          })
          .catchError((Object error) {
            logError('toggleFollowUser', error);
            social = previousSocial;
            peopleResults = previousResults;
            say(genericErrorMessage);
          }),
    );
  }

  void requestFollowUser(String userId) {
    authed
        ? toggleFollowUser(userId)
        : needAuth(PendingAuth(PendingKind.followUser, userId));
  }

  Future<void> searchPeople(String q) async {
    final trimmed = q.trim();
    if (trimmed.length < 2) {
      _peopleSearchToken = Object();
      peopleResults = const [];
      peopleSearching = false;
      notifyListeners();
      return;
    }
    final token = Object();
    _peopleSearchToken = token;
    peopleSearching = true;
    notifyListeners();
    try {
      final result = await repository.searchUsers(trimmed);
      if (_disposed || !identical(_peopleSearchToken, token)) return;
      peopleResults = result;
      peopleSearching = false;
      notifyListeners();
    } catch (error) {
      if (_disposed || !identical(_peopleSearchToken, token)) return;
      logError('searchUsers', error);
      peopleSearching = false;
      notifyListeners();
    }
  }

  Future<SocialUserDetail?> loadUserCard(String userId) async {
    try {
      return await repository.userCard(userId);
    } catch (error) {
      logError('userCard', error);
      return null;
    }
  }

  Future<void> setShareRsvps(bool on) async {
    final currentProfile = profile;
    if (currentProfile == null) return;
    final previousSocial = social;
    final previousProfile = currentProfile;
    final sessionToken = _socialSessionToken;
    social = social.copyWith(shareRsvpsWithFriends: on);
    profile = currentProfile.copyWith(shareRsvpsWithFriends: on);
    notifyListeners();
    try {
      await repository.updateFanProfile(
        name: currentProfile.name,
        bio: currentProfile.bio,
        homeLocation: currentProfile.homeLocation,
        genres: currentProfile.genres,
        locationPersonalizationEnabled:
            currentProfile.locationPersonalizationEnabled,
        followedBandUpdatesEnabled: currentProfile.followedBandUpdatesEnabled,
        shareRsvpsWithFriends: on,
      );
    } catch (error) {
      if (_disposed || !identical(_socialSessionToken, sessionToken)) return;
      logError('updateFanProfile', error);
      social = previousSocial;
      profile = previousProfile;
      say(genericErrorMessage);
    }
  }

  @override
  void _clearSocialState() {
    social = SocialGraph.empty;
    socialLoaded = false;
    friendsStatus = DataStatus.connecting;
    _friendsGoingEntries = const [];
    _friendsGoingLoaded = false;
    friendsGoingTruncated = false;
    peopleResults = const [];
    peopleSearching = false;
    knownAttendeesByGig = const {};
    _knownAttendeesLoadTokens.clear();
    _socialEnsured = false;
    _socialSessionToken = Object();
    _socialLoadToken = Object();
    _friendsGoingLoadToken = Object();
    _peopleSearchToken = Object();
  }
}
