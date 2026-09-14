import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/errors.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';

class _SocialRepository extends DemoRepository {
  _SocialRepository({required FakeAuthService auth})
    : authService = auth,
      super(auth: auth);

  final FakeAuthService authService;

  int mySocialCalls = 0;
  int friendsGoingCalls = 0;
  int knownAttendeesCalls = 0;
  bool failToggle = false;
  bool failProfile = false;
  FriendsGoing friendsGoingResult = FriendsGoing.empty;
  KnownAttendees? knownAttendeesResult;
  DateTime? lastFriendsGoingFrom;
  DateTime? lastFriendsGoingTo;
  final Map<String, Completer<List<SocialUserCard>>> searchGates = {};

  @override
  Future<SocialGraph> mySocial() async {
    mySocialCalls++;
    return super.mySocial();
  }

  @override
  Future<FriendsGoing> friendsGoing({
    required DateTime from,
    required DateTime to,
  }) async {
    friendsGoingCalls++;
    lastFriendsGoingFrom = from;
    lastFriendsGoingTo = to;
    return friendsGoingResult.entries.isEmpty && !friendsGoingResult.truncated
        ? super.friendsGoing(from: from, to: to)
        : friendsGoingResult;
  }

  @override
  Future<KnownAttendees> knownAttendees(
    String gigId, {
    required DateTime now,
  }) async {
    knownAttendeesCalls++;
    return knownAttendeesResult ?? super.knownAttendees(gigId, now: now);
  }

  @override
  Future<void> toggleFollowUser(String userId, {bool? on}) {
    if (failToggle) return Future<void>.error(Exception('toggle failed'));
    return super.toggleFollowUser(userId, on: on);
  }

  @override
  Future<List<SocialUserCard>> searchUsers(String q) {
    final gate = searchGates[q];
    return gate == null ? super.searchUsers(q) : gate.future;
  }

  @override
  Future<void> updateFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
    bool? shareRsvpsWithFriends,
  }) {
    if (failProfile) return Future<void>.error(Exception('profile failed'));
    return super.updateFanProfile(
      name: name,
      bio: bio,
      homeLocation: homeLocation,
      genres: genres,
      locationPersonalizationEnabled: locationPersonalizationEnabled,
      followedBandUpdatesEnabled: followedBandUpdatesEnabled,
      shareRsvpsWithFriends: shareRsvpsWithFriends,
    );
  }
}

Future<AppState> _signedInApp(_SocialRepository repository) async {
  final auth = repository.authService;
  await auth.signInDemo();
  final app = AppState.demo(repository: repository, auth: auth);
  addTearDown(app.dispose);
  return app;
}

void main() {
  test(
    'ensureSocial loads the graph once and exposes Maya as the only friend',
    () async {
      final auth = FakeAuthService();
      final repository = _SocialRepository(auth: auth);
      final app = await _signedInApp(repository);
      await flushAsyncWork();
      repository.mySocialCalls = 0;

      app.ensureSocial();
      await flushAsyncWork();
      expect(app.socialLoaded, isTrue);
      expect(app.friendIds, {'u-maya'});
      final social = app.social;
      app.ensureSocial();
      await flushAsyncWork();
      expect(identical(app.social, social), isTrue);
      expect(repository.mySocialCalls, 0);
    },
  );

  test('friendsGoing joins known gigs and drops unknown ids', () async {
    final auth = FakeAuthService();
    final repository = _SocialRepository(auth: auth);
    final gig = DemoData.gigs.first;
    repository.friendsGoingResult = FriendsGoing(
      entries: [
        FriendsGoingEntry(
          gigId: gig.id,
          startsAt: gig.startsAt,
          friends: const [
            SocialUserCard(
              userId: 'u-maya',
              name: 'Maya Okafor',
              isFriend: true,
            ),
          ],
        ),
        FriendsGoingEntry(
          gigId: 'no-such-gig',
          startsAt: gig.startsAt,
          friends: const [],
        ),
      ],
      truncated: false,
    );
    final app = await _signedInApp(repository);
    app.ensureSocial();
    await flushAsyncWork();
    expect(app.friendsGoing, hasLength(1));
    expect(app.friendsGoing.single.gig.id, gig.id);
  });

  test(
    'loadFriendsGoing requests a 14-day window that includes an entry 10 days out',
    () async {
      final auth = FakeAuthService();
      final repository = _SocialRepository(auth: auth);
      final gig = DemoData.gigs.first;
      final tenDaysOut = DateTime.now().add(const Duration(days: 10));
      repository.friendsGoingResult = FriendsGoing(
        entries: [
          FriendsGoingEntry(
            gigId: gig.id,
            startsAt: tenDaysOut,
            friends: const [
              SocialUserCard(
                userId: 'u-maya',
                name: 'Maya Okafor',
                isFriend: true,
              ),
            ],
          ),
        ],
        truncated: false,
      );
      final app = await _signedInApp(repository);
      app.ensureSocial();
      await flushAsyncWork();
      expect(app.friendsGoing, hasLength(1));
      final from = repository.lastFriendsGoingFrom!;
      final to = repository.lastFriendsGoingTo!;
      expect(to.difference(from).inDays, 14);
      expect(tenDaysOut.isAfter(from) && tenDaysOut.isBefore(to), isTrue);
    },
  );

  test('loadKnownAttendees caches per gig and clears on sign-out', () async {
    final auth = FakeAuthService();
    final repository = _SocialRepository(auth: auth);
    final app = await _signedInApp(repository);
    await flushAsyncWork();
    final first = await app.loadKnownAttendees('g9');
    expect(first.people.map((person) => person.userId), contains('u-maya'));
    expect(repository.knownAttendeesCalls, 1);
    final second = await app.loadKnownAttendees('g9');
    expect(second, same(first));
    expect(repository.knownAttendeesCalls, 1);
    expect(app.knownAttendeesFor('g9'), same(first));
    await app.signOut();
    expect(app.knownAttendeesFor('g9'), isNull);
  });

  test(
    'DemoRepository.knownAttendees lists Maya as a friend on her gig',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final result = await repository.knownAttendees(
        'g9',
        now: DateTime.now(),
      );
      final maya = result.people.firstWhere((person) => person.userId == 'u-maya');
      expect(maya.relation, KnownRelation.friend);
      final theo = result.people.firstWhere((person) => person.userId == 'u-theo');
      expect(theo.relation, KnownRelation.seen);
      expect(theo.sharedShows, 2);
    },
  );

  test(
    'friendsGoing memo survives notifications and invalidates on reload',
    () async {
      final auth = FakeAuthService();
      final repository = _SocialRepository(auth: auth);
      final gig = DemoData.gigs.first;
      repository.friendsGoingResult = FriendsGoing(
        entries: [
          FriendsGoingEntry(
            gigId: gig.id,
            startsAt: gig.startsAt,
            friends: const [],
          ),
        ],
        truncated: false,
      );
      final app = await _signedInApp(repository);
      app.ensureSocial();
      await flushAsyncWork();
      final first = app.friendsGoing;
      app.say('unrelated');
      expect(identical(app.friendsGoing, first), isTrue);
      repository.friendsGoingResult = FriendsGoing(
        entries: const [],
        truncated: false,
      );
      await app.loadFriendsGoing(refresh: true);
      expect(identical(app.friendsGoing, first), isFalse);
    },
  );

  test('toggleFollowUser rolls back when persistence fails', () async {
    final auth = FakeAuthService();
    final repository = _SocialRepository(auth: auth)..failToggle = true;
    final app = await _signedInApp(repository);
    app.ensureSocial();
    await flushAsyncWork();
    app.toggleFollowUser('u-lina');
    expect(app.isFollowingUser('u-lina'), isTrue);
    await flushAsyncWork();
    expect(app.isFollowingUser('u-lina'), isFalse);
    expect(app.toast, genericErrorMessage);
  });

  test('following a follower creates a friendship', () async {
    final auth = FakeAuthService();
    final repository = _SocialRepository(auth: auth);
    final app = await _signedInApp(repository);
    app.ensureSocial();
    await flushAsyncWork();
    app.toggleFollowUser('u-lina');
    expect(app.friendIds, contains('u-lina'));
    await flushAsyncWork();
  });

  test('requestFollowUser records and resolves pending auth', () async {
    final auth = FakeAuthService();
    final app = AppState.demo(
      repository: DemoRepository(auth: auth),
      auth: auth,
    );
    addTearDown(app.dispose);
    app.requestFollowUser('u-lina');
    expect(app.pending?.kind, PendingKind.followUser);
    expect(app.pending?.id, 'u-lina');
    expect(app.current.screen, Screen.auth);
    await auth.signInDemo();
    await flushAsyncWork();
    await app.commitAuth();
    await flushAsyncWork();
    expect(app.isFollowingUser('u-lina'), isTrue);
  });

  test('searchPeople ignores a stale response', () async {
    final auth = FakeAuthService();
    final repository = _SocialRepository(auth: auth);
    final first = Completer<List<SocialUserCard>>();
    final second = Completer<List<SocialUserCard>>();
    repository.searchGates['Maya'] = first;
    repository.searchGates['Lina'] = second;
    final app = await _signedInApp(repository);
    const maya = SocialUserCard(userId: 'u-maya', name: 'Maya Okafor');
    const lina = SocialUserCard(userId: 'u-lina', name: 'Lina');
    final firstSearch = app.searchPeople('Maya');
    final secondSearch = app.searchPeople('Lina');
    second.complete([lina]);
    await secondSearch;
    first.complete([maya]);
    await firstSearch;
    expect(app.peopleResults.single.userId, 'u-lina');
    expect(app.peopleSearching, isFalse);
  });

  test('setShareRsvps rolls back on error', () async {
    final auth = FakeAuthService();
    final repository = _SocialRepository(auth: auth)..failProfile = true;
    final app = await _signedInApp(repository);
    await flushAsyncWork();
    expect(app.profile, isNotNull);
    unawaited(app.setShareRsvps(false));
    expect(app.social.shareRsvpsWithFriends, isFalse);
    expect(app.profile!.shareRsvpsWithFriends, isFalse);
    await flushAsyncWork();
    expect(app.social.shareRsvpsWithFriends, isTrue);
    expect(app.profile!.shareRsvpsWithFriends, isTrue);
    expect(app.toast, genericErrorMessage);
  });

  test('signing out clears social state', () async {
    final auth = FakeAuthService();
    final repository = _SocialRepository(auth: auth);
    final app = await _signedInApp(repository);
    app.ensureSocial();
    await app.searchPeople('Ma');
    await flushAsyncWork();
    expect(app.socialLoaded, isTrue);
    expect(app.peopleResults, isNotEmpty);
    await app.signOut();
    expect(app.social, SocialGraph.empty);
    expect(app.socialLoaded, isFalse);
    expect(app.peopleResults, isEmpty);
  });
}
