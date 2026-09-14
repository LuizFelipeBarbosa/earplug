import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/explore_friends.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

class _ExploreRepository extends StubRepository {
  _ExploreRepository({required super.auth, this.social = SocialGraph.empty})
    : super();

  SocialGraph social;
  FriendsGoing friends = FriendsGoing.empty;

  @override
  Future<SocialGraph> mySocial() async => social;

  @override
  Future<FriendsGoing> friendsGoing({
    required DateTime from,
    required DateTime to,
  }) async => friends;
}

final _v1 = Venue(
  id: 'v1',
  name: 'The Chapel',
  area: 'Mission',
  addr: '123 Valencia St',
  point: const LatLng(37.7676, -122.422),
);
final _v2 = Venue(
  id: 'v2',
  name: 'The Other Room',
  area: 'Oakland',
  addr: '2 Broadway',
  point: const LatLng(37.8044, -122.2712),
);

Band _band(String id, String name) => bandFixture(
  id: id,
  slug: id,
  name: name,
  genres: const ['punk'],
);

UserProfile _profile({List<String> genres = const []}) => UserProfile(
  name: 'Fan',
  email: 'fan@example.com',
  genres: genres,
  attendedCount: 0,
  createdAt: DateTime(2024),
);

Future<AppHarness> _pumpExplore(
  WidgetTester tester, {
  required List<Gig> gigs,
  List<Band> bands = const [],
  List<Venue>? venues,
  bool signedIn = false,
  List<String> genres = const [],
  SocialGraph social = SocialGraph.empty,
  FriendsGoing friends = FriendsGoing.empty,
  Size size = const Size(402, 900),
}) async {
  final auth = FakeAuthService();
  if (signedIn) await auth.signInDemo();
  final resolvedVenues = venues ?? [_v1, _v2];
  final repository = _ExploreRepository(auth: auth, social: social)
    ..friends = friends
    ..returnsStream(
      'feed',
      () => Stream.value(
        FeedSnapshot(
          gigs: gigs,
          venues: {for (final venue in resolvedVenues) venue.id: venue},
          bands: {for (final band in bands) band.id: band},
        ),
      ),
    )
    ..returns('venues', resolvedVenues)
    ..returns('me', signedIn ? _profile(genres: genres) : null)
    ..returns(
      'listBands',
      BandPage(items: bands, continueCursor: null, isDone: true),
    );
  return pumpApp(
    tester,
    auth: auth,
    repository: repository,
    size: size,
    home: const Scaffold(body: ExploreScreen()),
    beforePump: (app) => app.loadMoreExploreBands(),
  );
}

Gig _gig(String id, {GigWhen when = GigWhen.tonight, String venueId = 'v1', bool free = true, List<String> genres = const ['punk']}) => gigFixture(
  id: id,
  title: id,
  venueId: venueId,
  when: when,
  price: free ? 0 : 12,
  startsAt: DateTime(2026, 9, 18, 20),
  genres: genres,
);

Finder _scopeTab(String label) => find.descendant(
  of: find.byKey(const Key('explore-result-tabs')),
  matching: find.text(label),
);

Finder _browseScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('explore-browse-'),
);

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(target, 500, scrollable: _browseScrollable());
  await tester.ensureVisible(target);
  await tester.pump();
}

void main() {
  testWidgets('recommended rail renders band tiles and opens the band on tap', (tester) async {
    final harness = await _pumpExplore(
      tester,
      signedIn: true,
      bands: [_band('b1', 'Noise Club')],
      gigs: [_gig('g1', genres: const ['punk'])],
      social: const SocialGraph(following: {'b1'}, followers: {}, friends: {}, followingCount: 1, followerCount: 0, truncated: false, shareRsvpsWithFriends: true),
    );
    expect(find.byKey(const Key('explore-recommended')), findsOneWidget);
    expect(find.byKey(const Key('explore-recommended-b1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-recommended-b1')));
    expect(harness.app.current.screen, Screen.band);
    expect(harness.app.current.param, 'b1');
  });

  testWidgets('recommended rail says BANDS TO KNOW when signed out and RECOMMENDED FOR YOU for a fan with genres', (tester) async {
    await _pumpExplore(tester, bands: [_band('b1', 'Noise Club')], gigs: [_gig('g1')]);
    expect(find.text('BANDS TO KNOW'), findsOneWidget);
    await _pumpExplore(tester, signedIn: true, genres: const ['punk'], bands: [_band('b1', 'Noise Club')], gigs: [_gig('g1')]);
    expect(find.text('RECOMMENDED FOR YOU'), findsOneWidget);
  });

  testWidgets('collections rail shows tonight and free-this-week cards and opens the collection screen', (tester) async {
    final harness = await _pumpExplore(tester, gigs: [_gig('g1', when: GigWhen.tonight), _gig('g2', when: GigWhen.week)]);
    await _scrollTo(tester, find.byKey(const Key('explore-collection-tonight')));
    expect(find.byKey(const Key('explore-collection-tonight')), findsOneWidget);
    expect(find.byKey(const Key('explore-collection-free')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-collection-tonight')));
    expect(harness.app.current.screen, Screen.exploreCollection);
    expect(harness.app.current.param, 'tonight');
  });

  testWidgets('events block caps tonight at three and links SEE ALL to the tonight collection', (tester) async {
    final harness = await _pumpExplore(tester, gigs: [for (var i = 0; i < 4; i++) _gig('g$i')]);
    await _scrollTo(tester, find.byKey(const ValueKey('fan-event-g2')));
    expect(find.byType(FanEventCard), findsNWidgets(3));
    final seeAll = find.descendant(of: find.byKey(const Key('explore-events-tonight')), matching: find.text('SEE ALL'));
    await _scrollTo(tester, seeAll);
    await tester.tap(seeAll);
    expect(harness.app.current.screen, Screen.exploreCollection);
    expect(harness.app.current.param, 'tonight');
  });

  testWidgets('venues-with-shows rail lists only venues that have feed gigs and opens the venue', (tester) async {
    final harness = await _pumpExplore(tester, gigs: [_gig('g1', venueId: 'v1')]);
    await _scrollTo(tester, find.byKey(const Key('explore-venue-tile-v1')));
    expect(find.byKey(const Key('explore-venue-tile-v1')), findsOneWidget);
    expect(find.byKey(const Key('explore-venue-tile-v2')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('explore-venue-tile-v1')));
    await tester.tap(find.byKey(const Key('explore-venue-tile-v1')));
    expect(harness.app.current.screen, Screen.venue);
    expect(harness.app.current.param, 'v1');
  });

  testWidgets('venues SEE ALL opens the venues collection', (tester) async {
    final harness = await _pumpExplore(tester, gigs: [_gig('g1')]);
    await _scrollTo(tester, find.byKey(const Key('explore-toggle-venues')));
    await tester.ensureVisible(find.byKey(const Key('explore-toggle-venues')));
    await tester.tap(find.byKey(const Key('explore-toggle-venues')));
    expect(harness.app.current.screen, Screen.exploreCollection);
    expect(harness.app.current.param, 'venues');
  });

  testWidgets('bands rail excludes recommended bands and the All bands row opens the directory collection', (tester) async {
    final harness = await _pumpExplore(tester, signedIn: true, bands: [_band('b1', 'Followed'), _band('b2', 'Other')], gigs: [_gig('g1')], social: const SocialGraph(following: {'b1'}, followers: {}, friends: {}, followingCount: 1, followerCount: 0, truncated: false, shareRsvpsWithFriends: true));
    await _scrollTo(tester, find.byKey(const Key('explore-bands')));
    expect(find.descendant(of: find.byKey(const Key('explore-bands')), matching: find.byKey(const Key('explore-band-card-b2'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('explore-bands')), matching: find.byKey(const Key('explore-band-card-b1'))), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('explore-toggle-bands')));
    await tester.tap(find.byKey(const Key('explore-toggle-bands')));
    expect(harness.app.current.screen, Screen.exploreCollection);
    expect(harness.app.current.param, 'bands');
  });

  testWidgets('friends section shows Find people when the fan has no friends and opens People', (tester) async {
    final harness = await _pumpExplore(tester, signedIn: true, gigs: [_gig('g1')]);
    await _scrollTo(tester, find.byKey(const Key('explore-find-people')));
    await tester.tap(find.byKey(const Key('explore-find-people')));
    expect(harness.app.current.screen, Screen.people);
  });

  testWidgets("friends section lists a friend's weekend gig with an avatar stack and opens the gig", (tester) async {
    final harness = await _pumpExplore(tester, signedIn: true, gigs: [_gig('g1')], social: const SocialGraph(following: {'u1'}, followers: {'u1'}, friends: {'u1'}, followingCount: 1, followerCount: 1, truncated: false, shareRsvpsWithFriends: true), friends: FriendsGoing(entries: [FriendsGoingEntry(gigId: 'g1', startsAt: DateTime(2026, 9, 18, 20), friends: [SocialUserCard(userId: 'u1', name: 'Maya', isFriend: true)])], truncated: false));
    final row = find.byKey(const Key('explore-friends-gig-g1'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byType(ExploreAvatarStack)), findsOneWidget);
    await tester.tap(row);
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, 'g1');
  });

  testWidgets('friends section gates behind sign-in when signed out', (tester) async {
    final harness = await _pumpExplore(tester, gigs: [_gig('g1')]);
    await _scrollTo(tester, find.byKey(const Key('explore-friends-sign-in')));
    expect(find.byKey(const Key('explore-friends-sign-in')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-friends-sign-in')));
    expect(harness.app.pending?.kind, PendingKind.myGigs);
  });

  testWidgets('EVENTS scope hides bands and venues rails, BANDS scope hides events, VENUES scope lists venues as rows', (tester) async {
    await _pumpExplore(tester, bands: [_band('b1', 'Band')], gigs: [_gig('g1')]);
    await tester.tap(_scopeTab('EVENTS'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('explore-bands')), findsNothing);
    expect(find.byKey(const Key('explore-venues')), findsNothing);
    await tester.tap(_scopeTab('BANDS'));
    await tester.pump(const Duration(milliseconds: 250));
    await _scrollTo(tester, find.byKey(const Key('explore-bands')));
    expect(find.byKey(const Key('explore-events-tonight')), findsNothing);
    expect(find.byKey(const Key('explore-bands')), findsOneWidget);
    await tester.tap(_scopeTab('VENUES'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('explore-venues')), findsNothing);
    expect(find.text('The Chapel'), findsOneWidget);
    expect(find.byKey(const Key('explore-bands')), findsNothing);
  });

  testWidgets('empty feed shows the no-nearby-events copy but still renders the bands rail', (tester) async {
    await _pumpExplore(tester, bands: [_band('b1', 'Band')], gigs: []);
    expect(find.text('No nearby events in the loaded feed.'), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('explore-bands')));
    expect(find.byKey(const Key('explore-bands')), findsOneWidget);
  });

  testWidgets('selecting a genre chip switches to the genre page and All restores the browse blocks', (tester) async {
    await _pumpExplore(tester, bands: [_band('b1', 'Band')], gigs: [_gig('g1', genres: const ['punk'])]);
    final chip = find.byKey(const Key('explore-genre-punk'));
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explore-genre-page')), findsOneWidget);
    expect(find.byKey(const Key('explore-browse-all')), findsNothing);
    await tester.tap(find.byKey(const Key('explore-genre-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explore-browse-all')), findsOneWidget);
    expect(find.byKey(const Key('explore-genre-page')), findsNothing);
  });

  testWidgets('desktop width lays the blocks out in two columns without overflow', (tester) async {
    await _pumpExplore(tester, size: const Size(1280, 900), bands: [_band('b1', 'Band')], gigs: [_gig('g1')]);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('explore-recommended')), findsOneWidget);
    expect(find.byKey(const Key('explore-friends')), findsOneWidget);
  });

  testWidgets('large text scale wraps the rails and renders without overflow', (tester) async {
    final auth = FakeAuthService();
    final repo = _ExploreRepository(auth: auth)
      ..returnsStream('feed', () => Stream.value(FeedSnapshot(gigs: [_gig('g1')], venues: {'v1': _v1}, bands: {'b1': _band('b1', 'Band')})))
      ..returns('venues', [_v1])
      ..returns('listBands', BandPage(items: [_band('b1', 'Band')], continueCursor: null, isDone: true));
    final harness = await pumpApp(tester, auth: auth, repository: repo, size: const Size(360, 800), home: Builder(builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)), child: const Scaffold(body: ExploreScreen()))), beforePump: (app) => app.loadMoreExploreBands());
    expect(tester.takeException(), isNull);
    await _scrollTo(tester, find.byKey(const Key('explore-friends')));
    expect(find.byKey(const Key('explore-friends')), findsOneWidget);
    expect(harness.app.current.screen, Screen.home);
  });
}
