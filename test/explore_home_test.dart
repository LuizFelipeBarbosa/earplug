import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/date_names.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/explore_friends.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

final _now = DateTime(2026, 1, 5, 10);

class _ExploreRepository extends StubRepository {
  _ExploreRepository({required super.auth, this.social = SocialGraph.empty});
  SocialGraph social;
  FriendsGoing friends = FriendsGoing.empty;
  Interactions interactions = Interactions.empty;
  @override
  Future<SocialGraph> mySocial() async => social;
  @override
  Future<FriendsGoing> friendsGoing({
    required DateTime from,
    required DateTime to,
  }) async => friends;
  @override
  Stream<Interactions> myInteractions() => Stream.value(interactions);
}

final _v1 = Venue(
  id: 'v1',
  name: 'Mission Hall',
  area: 'Mission',
  addr: '123 Valencia St',
  city: 'San Francisco',
  point: const LatLng(37.7676, -122.422),
);
final _v2 = Venue(
  id: 'v2',
  name: 'Oak House',
  area: 'Oakland',
  addr: '2 Broadway',
  city: 'Oakland',
  point: const LatLng(37.8044, -122.2712),
);

Band _band(String id, String name, {List<String> genres = const ['punk']}) =>
    bandFixture(id: id, slug: id, name: name, genres: genres, area: 'Oakland');
UserProfile _profile({List<String> genres = const []}) => UserProfile(
  name: 'Fan',
  email: 'fan@example.com',
  genres: genres,
  attendedCount: 0,
  createdAt: DateTime(2024),
  homeLocation: FanCity.sf,
);
Gig _gig(
  String id,
  DateTime startsAt, {
  String venueId = 'v1',
  String? title,
  List<String> lineup = const [],
  List<String> genres = const ['punk'],
}) => gigFixture(
  id: id,
  title: title ?? id,
  venueId: venueId,
  startsAt: startsAt,
  price: 0,
  lineup: lineup,
  genres: genres,
);
SocialUserCard _friend(String id) =>
    SocialUserCard(userId: id, name: 'Friend $id', isFriend: true);

Future<AppHarness> _pumpExplore(
  WidgetTester tester, {
  required List<Gig> gigs,
  List<Band> bands = const [],
  List<Venue>? venues,
  bool signedIn = false,
  List<String> genres = const [],
  SocialGraph social = SocialGraph.empty,
  FriendsGoing friends = FriendsGoing.empty,
  Set<String> followed = const {},
  Set<String> saved = const {},
  Size size = const Size(402, 900),
  Widget? home,
}) async {
  final auth = FakeAuthService();
  if (signedIn) await auth.signInDemo();
  final resolvedVenues = venues ?? [_v1, _v2];
  final repository = _ExploreRepository(auth: auth, social: social)
    ..friends = friends
    ..interactions = Interactions(
      rsvpGigIds: const {},
      followBandIds: followed,
      savedGigIds: saved,
      attendedCount: 0,
    )
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
    now: () => _now,
    home: home ?? const Scaffold(body: ExploreScreen()),
    beforePump: (app) => app.loadMoreExploreBands(),
  );
}

Finder _browseScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('explore-browse-all')),
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 400, scrollable: _browseScrollable());
  await tester.pumpAndSettle();
}

SocialGraph _social({bool friend = true}) => SocialGraph(
  following: friend ? {'u1'} : {},
  followers: friend ? {'u1'} : {},
  friends: friend ? {'u1'} : {},
  followingCount: friend ? 1 : 0,
  followerCount: friend ? 1 : 0,
  truncated: false,
  shareRsvpsWithFriends: true,
);
FriendsGoing _friendsFor(List<String> ids) => FriendsGoing(
  entries: [
    for (var i = 0; i < ids.length; i++)
      FriendsGoingEntry(
        gigId: ids[i],
        startsAt: _now.add(Duration(days: i + 4)),
        friends: [_friend('u$i')],
      ),
  ],
  truncated: false,
);
List<Gig> get _gigs => [
  _gig('gFollowed', DateTime(2026, 1, 6, 20), lineup: const ['bFollow']),
  _gig('gSaved', DateTime(2026, 1, 7, 20), venueId: 'v2'),
  _gig('gWeekend', DateTime(2026, 1, 10, 20)),
  _gig('gLater', DateTime(2026, 1, 11, 20), venueId: 'v2'),
];
List<Band> get _bands => [
  _band('bFollow', 'Followed Band'),
  _band('bExtra1', 'Extra One', genres: const ['jazz']),
  _band('bExtra2', 'Extra Two', genres: const ['electronic']),
];

void main() {
  testWidgets(
    'featured carousel shows the two most relevant events and opens the gig on tap',
    (tester) async {
      final h = await _pumpExplore(
        tester,
        signedIn: true,
        gigs: _gigs,
        bands: _bands,
        genres: const ['punk'],
        followed: const {'bFollow'},
        saved: const {'gSaved'},
      );
      final rail = find.byKey(const Key('explore-featured'));
      expect(rail, findsOneWidget);
      expect(
        find.byKey(const Key('explore-featured-gFollowed')),
        findsOneWidget,
      );
      final followedCard = find.byKey(const Key('explore-featured-gFollowed'));
      expect(
        find.descendant(
          of: followedCard,
          matching: find.textContaining('FREE'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: followedCard, matching: find.text('Followed Band')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('explore-featured-gSaved')), findsOneWidget);
      expect(find.byKey(const Key('explore-featured-gWeekend')), findsNothing);

      // One landscape card spans the width; the next one peeks in on the right.
      final viewportWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final first = tester.getSize(
        find.byKey(const Key('explore-featured-gFollowed')),
      );
      expect(first.width, closeTo(viewportWidth - EpLayout.gutter - 36, 1));
      expect(first.height, lessThan(first.width));
      final secondLeft = tester
          .getTopLeft(find.byKey(const Key('explore-featured-gSaved')))
          .dx;
      expect(secondLeft, lessThan(viewportWidth));

      await tester.tap(find.byKey(const Key('explore-featured-gFollowed')));
      expect(h.app.current.screen, Screen.gig);
      expect(h.app.current.param, 'gFollowed');
    },
  );

  testWidgets(
    'featured carousel is omitted when the feed is empty and the empty copy shows',
    (tester) async {
      await _pumpExplore(tester, signedIn: true, gigs: const [], bands: _bands);
      expect(find.byKey(const Key('explore-featured')), findsNothing);
      expect(find.byKey(const Key('explore-empty')), findsOneWidget);
      expect(find.text('No upcoming events yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'just for you lists the remaining events in date order without the featured pair',
    (tester) async {
      final gigs = [
        for (final gig in _gigs)
          if (gig.id == 'gWeekend')
            _gig(gig.id, gig.startsAt, lineup: const ['bFollow'])
          else
            gig,
      ];
      final weekendGig = gigs.firstWhere((gig) => gig.id == 'gWeekend');
      await _pumpExplore(
        tester,
        signedIn: true,
        gigs: gigs,
        bands: _bands,
        followed: const {'bFollow'},
        saved: const {'gSaved'},
      );
      await _scrollTo(
        tester,
        find.byKey(const Key('explore-for-you-gWeekend')),
      );
      expect(find.byKey(const Key('explore-for-you-gWeekend')), findsOneWidget);
      expect(find.byKey(const Key('explore-for-you-gLater')), findsOneWidget);
      expect(find.byKey(const Key('explore-for-you-gFollowed')), findsNothing);
      expect(find.byKey(const Key('explore-for-you-gSaved')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const Key('explore-for-you-gWeekend'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('explore-for-you-gLater'))).dy,
        ),
      );
      final row = find.byKey(const Key('explore-for-you-gWeekend'));
      expect(
        find.descendant(of: row, matching: find.byType(EpAvatarTile)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Followed Band')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining(
            '${weekendGig.startsAt.day} '
            '${monthNamesUpper[weekendGig.startsAt.month - 1]} · '
            '${weekendGig.doorsLabel} · ${weekendGig.priceLabel}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining(_v1.name)),
        findsNothing,
      );
    },
  );

  testWidgets('just for you rows open the gig', (tester) async {
    final h = await _pumpExplore(
      tester,
      signedIn: true,
      gigs: _gigs,
      bands: _bands,
      followed: const {'bFollow'},
      saved: const {'gSaved'},
    );
    await _scrollTo(tester, find.byKey(const Key('explore-for-you-gWeekend')));
    await tester.tap(find.byKey(const Key('explore-for-you-gWeekend')));
    expect(h.app.current.screen, Screen.gig);
    expect(h.app.current.param, 'gWeekend');
  });

  testWidgets('featured card shows a friends cue', (tester) async {
    await _pumpExplore(
      tester,
      signedIn: true,
      gigs: _gigs,
      bands: _bands,
      social: _social(),
      friends: _friendsFor(const ['gWeekend']),
    );
    final card = find.byKey(const Key('explore-featured-gWeekend'));
    await _scrollTo(tester, card);
    expect(
      find.descendant(of: card, matching: find.byType(ExploreAvatarStack)),
      findsOneWidget,
    );
  });

  testWidgets('just for you row shows a friends cue', (tester) async {
    // Friends attend the featured pair too, so the +6 friend weight cannot
    // promote gLater out of Just for you.
    final h = await _pumpExplore(
      tester,
      signedIn: true,
      gigs: _gigs,
      bands: _bands,
      followed: const {'bFollow'},
      saved: const {'gSaved'},
      friends: _friendsFor(const ['gFollowed', 'gSaved', 'gLater']),
    );
    expect(h.app.exploreHome.forYou.map((gig) => gig.id), contains('gLater'));
    final row = find.byKey(const Key('explore-for-you-gLater'));
    await _scrollTo(tester, row);
    expect(
      find.descendant(of: row, matching: find.byType(ExploreAvatarStack)),
      findsOneWidget,
    );
  });

  testWidgets('a friends attending gig outranks an otherwise equal gig', (
    tester,
  ) async {
    final gigs = [
      _gig('gPlain', DateTime(2026, 1, 8, 20)),
      _gig('gFriend', DateTime(2026, 1, 8, 20), venueId: 'v2'),
    ];
    final h = await _pumpExplore(
      tester,
      signedIn: true,
      gigs: gigs,
      friends: _friendsFor(const ['gFriend']),
    );
    final home = h.app.exploreHome;
    final ordered = [...home.featured, ...home.forYou];
    expect(ordered.indexWhere((gig) => gig.id == 'gFriend'), 0);
  });

  testWidgets('venues rail lists scheduled venues and opens a venue', (
    tester,
  ) async {
    final h = await _pumpExplore(tester, gigs: _gigs, bands: _bands);
    await _scrollTo(tester, find.byKey(const Key('explore-venues')));
    expect(find.byKey(const Key('explore-venue-tile-v1')), findsOneWidget);
    expect(find.byKey(const Key('explore-venue-tile-v2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-venue-tile-v1')));
    expect(h.app.current.screen, Screen.venue);
    expect(h.app.current.param, 'v1');
  });

  testWidgets('bands rail shows recommended bands and opens a band', (
    tester,
  ) async {
    // Recommendations exclude followed bands, so the fan's genre affinity is
    // what ranks the punk band first.
    final h = await _pumpExplore(
      tester,
      signedIn: true,
      gigs: _gigs,
      bands: _bands,
      genres: const ['punk'],
    );
    expect(h.app.exploreHome.recommendedBandIds.first, 'bFollow');
    await _scrollTo(tester, find.byKey(const Key('explore-bands')));
    final band = find.byKey(const Key('explore-band-card-bFollow'));
    expect(band, findsOneWidget);
    expect(
      find.descendant(of: band, matching: find.text('punk')),
      findsOneWidget,
    );
    await tester.tap(band);
    expect(h.app.current.screen, Screen.band);
    expect(h.app.current.param, 'bFollow');
  });

  testWidgets('bands rail hugs its tiles and sits 32 under the venues row', (
    tester,
  ) async {
    await _pumpExplore(tester, signedIn: true, gigs: _gigs, bands: _bands);
    final rail = find.byKey(const Key('explore-bands'));
    final allBands = find.byKey(const Key('explore-toggle-bands'));
    await _scrollTo(tester, allBands);
    expect(rail, findsOneWidget);
    final railRect = tester.getRect(rail);
    expect(railRect.height, exploreBandRailHeight(tester.element(rail)));
    // The first avatar starts on the gutter, under the heading's left edge.
    final heading = find.text('BANDS');
    expect(
      tester.getTopLeft(find.byKey(const Key('explore-band-card-bFollow'))).dx,
      tester.getTopLeft(heading).dx,
    );
    // No dead space between the rail and the All bands row.
    expect(tester.getTopLeft(allBands).dy, railRect.bottom);
    // The heading keeps 32px clear of the All venues row above it.
    final allVenues = find.byKey(const Key('explore-toggle-venues'));
    expect(
      tester.getTopLeft(heading).dy - tester.getRect(allVenues).bottom,
      32,
    );
  });

  testWidgets('pinned genre rail stays below the status bar when scrolled', (
    tester,
  ) async {
    const statusBar = 47.0;
    await _pumpExplore(
      tester,
      gigs: _gigs,
      bands: _bands,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(top: statusBar)),
          child: const Scaffold(body: ExploreScreen()),
        ),
      ),
    );
    final chips = find.byKey(const Key('explore-genre-rail'));
    // At rest the chips sit 12px under the search field's hairline.
    final fieldBottom = tester.getRect(find.byType(EpUnderlineField)).bottom;
    expect(tester.getTopLeft(chips).dy - fieldBottom, 12);
    expect(tester.getTopLeft(find.text('EXPLORE')).dy, greaterThan(statusBar));

    await _scrollTo(tester, find.byKey(const Key('explore-toggle-bands')));
    expect(find.text('EXPLORE'), findsNothing);
    expect(tester.getTopLeft(chips).dy, statusBar + 12);
    expect(tester.getTopLeft(chips).dy, greaterThanOrEqualTo(12));
  });

  testWidgets('find people row is at the bottom and opens People', (
    tester,
  ) async {
    final h = await _pumpExplore(
      tester,
      signedIn: true,
      gigs: _gigs,
      bands: _bands,
    );
    final findPeople = find.byKey(const Key('explore-find-people'));
    await _scrollTo(tester, findPeople);
    expect(h.app.current.screen, Screen.home);
    await tester.tap(findPeople);
    expect(h.app.current.screen, Screen.people);
  });

  testWidgets('sign-in row appears at the bottom when signed out', (
    tester,
  ) async {
    final h = await _pumpExplore(tester, gigs: _gigs, bands: _bands);
    final signIn = find.byKey(const Key('explore-friends-sign-in'));
    await _scrollTo(tester, signIn);
    await tester.tap(signIn);
    expect(h.app.pending?.kind, PendingKind.myGigs);
  });

  testWidgets('all bands and all venues rows open their collections', (
    tester,
  ) async {
    final h = await _pumpExplore(tester, gigs: _gigs, bands: _bands);
    await _scrollTo(tester, find.byKey(const Key('explore-toggle-bands')));
    await tester.tap(find.byKey(const Key('explore-toggle-bands')));
    expect(h.app.current.screen, Screen.exploreCollection);
    expect(h.app.current.param, 'bands');
    h.app.go(Screen.home);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('explore-toggle-venues')));
    await tester.tap(find.byKey(const Key('explore-toggle-venues')));
    expect(h.app.current.screen, Screen.exploreCollection);
    expect(h.app.current.param, 'venues');
  });

  testWidgets(
    'selecting a genre chip switches to the genre page and All restores the feed',
    (tester) async {
      await _pumpExplore(tester, gigs: _gigs, bands: _bands);
      final chip = find.byKey(const Key('explore-genre-punk'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('explore-genre-page')), findsOneWidget);
      expect(find.byKey(const Key('explore-browse-all')), findsNothing);
      await tester.tap(find.byKey(const Key('explore-genre-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('explore-browse-all')), findsOneWidget);
    },
  );

  testWidgets(
    'search shows location, event, band and venue groups and a location result sets the city',
    (tester) async {
      final venue = Venue(
        id: 'oak-v',
        name: 'Oak Venue',
        area: 'Oakland',
        addr: 'Oak Ave',
        city: 'Oakland',
        point: const LatLng(37.8044, -122.2712),
      );
      final band = _band('oak-b', 'Oak Band');
      final gig = _gig(
        'oak-g',
        DateTime(2026, 1, 6, 20),
        venueId: 'oak-v',
        title: 'Oak Event',
        lineup: const ['oak-b'],
      );
      final h = await _pumpExplore(
        tester,
        gigs: [gig],
        bands: [band],
        venues: [venue],
        signedIn: true,
      );
      await tester.enterText(
        find.byKey(const Key('explore-search-field')),
        'oak',
      );
      await tester.tap(find.byKey(const Key('explore-search-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('LOCATIONS ·'), findsOneWidget);
      expect(find.textContaining('EVENTS ·'), findsOneWidget);
      expect(find.textContaining('BANDS ·'), findsOneWidget);
      expect(find.textContaining('VENUES ·'), findsOneWidget);
      await tester.tap(find.byKey(const Key('explore-location-oak')));
      expect(h.app.discoveryLocation, DiscoveryLocation.oak);
      expect(h.app.query, isEmpty);
    },
  );

  testWidgets('desktop width renders without overflow', (tester) async {
    await _pumpExplore(
      tester,
      signedIn: true,
      size: const Size(1280, 900),
      gigs: _gigs,
      bands: _bands,
      followed: const {'bFollow'},
      saved: const {'gSaved'},
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('explore-featured')), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('explore-find-people')));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('explore-find-people')), findsOneWidget);
  });

  testWidgets('large text scale wraps the rails and renders without overflow', (
    tester,
  ) async {
    await _pumpExplore(
      tester,
      signedIn: true,
      size: const Size(360, 800),
      gigs: _gigs,
      bands: _bands,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: const Scaffold(body: ExploreScreen()),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _scrollTo(tester, find.byKey(const Key('explore-find-people')));
    expect(find.byKey(const Key('explore-find-people')), findsOneWidget);
  });
}
