import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/home.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
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
    home: home ?? const Scaffold(body: HomeScreen()),
    beforePump: (app) {
      app.setMapMode(false);
      app.loadMoreExploreBands();
    },
  );
}

Finder _browseScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('feed-browse-all')),
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 400, scrollable: _browseScrollable());
  await tester.pumpAndSettle();
}

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
      final rail = find.byKey(const Key('feed-featured'));
      expect(rail, findsOneWidget);
      Finder featuredCard(String id) => find.byWidgetPredicate(
        (widget) =>
            widget is ExploreFeaturedCard &&
            widget.key == Key('feed-featured-$id'),
      );
      expect(featuredCard('gFollowed'), findsOneWidget);
      final followedCard = featuredCard('gFollowed');
      final cardRect = tester.getRect(followedCard);
      for (final action in ['save', 'share']) {
        final button = find.descendant(
          of: followedCard,
          matching: find.byKey(ValueKey('$action-gFollowed')),
        );
        expect(button, findsOneWidget);
        expect(tester.widget<ExploreCardIconButton>(button).ring, isFalse);
        final glyph = tester.widget<Icon>(
          find.descendant(
            of: button,
            matching: find.byIcon(
              action == 'save' ? Icons.bookmark_border : Icons.ios_share,
            ),
          ),
        );
        expect(glyph.color, Ep.ink);
        expect(glyph.shadows, isNull);
        final rect = tester.getRect(button);
        expect(rect.size, const Size(36, 36));
        expect(rect.top - cardRect.top, closeTo(8, 1));
        expect(
          cardRect.right - rect.right,
          closeTo(action == 'save' ? 8 : 8 + 36 + 4, 1),
        );
        expect(rect.right, greaterThan(cardRect.center.dx));
      }
      final gig = _gigs.first;
      expect(
        find.descendant(
          of: followedCard,
          matching: find.text('TUE, JAN 6 AT ${gig.doorsLabel}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: followedCard,
          matching: find.byKey(ValueKey('gig-price-${gig.id}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: followedCard, matching: find.text('FREE')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: followedCard,
          matching: find.text(gig.title.toUpperCase()),
        ),
        findsOneWidget,
      );
      expect(featuredCard('gSaved'), findsOneWidget);
      expect(featuredCard('gWeekend'), findsNothing);

      // One landscape card spans the width; the next one peeks in on the right.
      final viewportWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final first = tester.getSize(followedCard);
      expect(first.width, closeTo(viewportWidth - EpLayout.gutter - 36, 1));
      expect(first.height, lessThan(first.width));
      final secondLeft = tester.getTopLeft(featuredCard('gSaved')).dx;
      expect(secondLeft, lessThan(viewportWidth));

      await tester.tap(followedCard);
      expect(h.app.current.screen, Screen.gig);
      expect(h.app.current.param, 'gFollowed');
    },
  );

  testWidgets(
    'featured carousel is omitted when the feed is empty and the empty copy shows',
    (tester) async {
      await _pumpExplore(tester, signedIn: true, gigs: const [], bands: _bands);
      expect(find.byKey(const Key('feed-featured')), findsNothing);
      expect(find.byKey(const Key('feed-empty')), findsOneWidget);
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
      await _scrollTo(tester, find.byKey(const Key('feed-for-you-gWeekend')));
      expect(find.byKey(const Key('feed-for-you-gWeekend')), findsOneWidget);
      expect(find.byKey(const Key('feed-for-you-gLater')), findsOneWidget);
      expect(find.byKey(const Key('feed-for-you-gFollowed')), findsNothing);
      expect(find.byKey(const Key('feed-for-you-gSaved')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const Key('feed-for-you-gWeekend'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('feed-for-you-gLater'))).dy,
        ),
      );
      final row = find.byKey(const Key('feed-for-you-gWeekend'));
      expect(
        find.descendant(of: row, matching: find.byType(EpAvatarTile)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(weekendGig.title.toUpperCase()),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('SAT, JAN 10 AT ${weekendGig.doorsLabel}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining(weekendGig.priceLabel),
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
    await _scrollTo(tester, find.byKey(const Key('feed-for-you-gWeekend')));
    await tester.tap(find.byKey(const Key('feed-for-you-gWeekend')));
    expect(h.app.current.screen, Screen.gig);
    expect(h.app.current.param, 'gWeekend');
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
    await _scrollTo(tester, find.byKey(const Key('feed-venues')));
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
    await _scrollTo(tester, find.byKey(const Key('feed-bands')));
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

  testWidgets(
    'bands rail hugs its tiles and header sits 32 under the venues rail',
    (tester) async {
      await _pumpExplore(tester, signedIn: true, gigs: _gigs, bands: _bands);
      final rail = find.byKey(const Key('feed-bands'));
      final allBands = find.byKey(const Key('feed-toggle-bands'));
      final findPeople = find.byKey(const Key('feed-find-people'));
      await _scrollTo(tester, findPeople);
      expect(rail, findsOneWidget);
      final railRect = tester.getRect(rail);
      expect(railRect.height, exploreBandRailHeight(tester.element(rail)));
      // The first avatar starts on the gutter, under the heading's left edge.
      final heading = find.text('BANDS');
      expect(
        tester
            .getTopLeft(find.byKey(const Key('explore-band-card-bFollow')))
            .dx,
        tester.getTopLeft(heading).dx,
      );
      expect(find.widgetWithText(EpMenuRow, 'All venues'), findsNothing);
      expect(find.widgetWithText(EpMenuRow, 'All bands'), findsNothing);
      expect(find.text('VENUES'), findsOneWidget);
      expect(heading, findsOneWidget);

      final allVenues = find.byKey(const Key('feed-toggle-venues'));
      for (final action in [allVenues, allBands]) {
        expect(tester.widget(action), isA<TextButton>());
        expect(
          find.descendant(of: action, matching: find.text('SEE MORE')),
          findsOneWidget,
        );
        final header = find.ancestor(
          of: action,
          matching: find.byType(EpSectionHeader),
        );
        final label = find.descendant(
          of: header,
          matching: find.byType(EpEyebrow),
        );
        expect(
          (tester.getCenter(action).dy - tester.getCenter(label).dy).abs(),
          lessThan(4),
        );
        final headerRect = tester.getRect(header);
        expect(
          tester.getRect(action).right,
          inInclusiveRange(headerRect.right - 4, headerRect.right),
        );
        expect(
          headerRect.right,
          tester.getRect(find.byType(HomeScreen)).right - EpLayout.gutter,
        );
      }

      // The venues rail, divider, and header padding sit between actions.
      // After accounting for them, the BANDS header still has 32px above its row.
      final venuesHeader = tester.widget<EpSectionHeader>(
        find.ancestor(of: allVenues, matching: find.byType(EpSectionHeader)),
      );
      final dividerRect = tester.getRect(
        find.byKey(const Key('feed-venues-bands-divider')),
      );
      expect(
        tester.getTopLeft(allBands).dy -
            tester.getRect(allVenues).bottom -
            tester.getRect(find.byKey(const Key('feed-venues'))).height -
            venuesHeader.padding.bottom -
            dividerRect.height,
        EpLayout.formSectionGap,
      );
      expect(
        tester.getTopLeft(findPeople).dy - railRect.bottom,
        EpLayout.formSectionGap,
      );
      final bottomBlock = find.ancestor(
        of: findPeople,
        matching: find.byType(SliverToBoxAdapter),
      );
      // The first hairline separates the rail; the menu row has its own below.
      final hairline = find
          .descendant(of: bottomBlock, matching: find.byType(EpHairline))
          .first;
      expect(hairline, findsOneWidget);
      expect(tester.getRect(hairline).height, 1);
      expect(tester.getTopLeft(hairline).dy, greaterThan(railRect.bottom));
      expect(
        tester.getRect(hairline).bottom,
        lessThan(tester.getTopLeft(findPeople).dy),
      );
      final bottomColumn = find.ancestor(
        of: findPeople,
        matching: find.byType(Column),
      );
      expect(
        tester.getRect(bottomColumn.first).bottom -
            tester.getRect(findPeople).bottom,
        24,
      );
    },
  );

  testWidgets('venues and bands have a hairline divider between them', (
    tester,
  ) async {
    await _pumpExplore(tester, gigs: _gigs, bands: _bands);
    final divider = find.byKey(const Key('feed-venues-bands-divider'));
    await _scrollTo(tester, divider);

    expect(divider, findsOneWidget);
    expect(
      find.descendant(of: divider, matching: find.byType(EpHairline)),
      findsOneWidget,
    );
    final dividerRect = tester.getRect(divider);
    expect(
      dividerRect.top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const Key('feed-venues'))).bottom,
      ),
    );
    expect(
      dividerRect.bottom,
      lessThanOrEqualTo(tester.getRect(find.text('BANDS')).top),
    );
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
    final findPeople = find.byKey(const Key('feed-find-people'));
    await _scrollTo(tester, findPeople);
    expect(h.app.current.screen, Screen.home);
    await tester.tap(findPeople);
    expect(h.app.current.screen, Screen.people);
  });

  testWidgets('sign-in row appears at the bottom when signed out', (
    tester,
  ) async {
    final h = await _pumpExplore(tester, gigs: _gigs, bands: _bands);
    final signIn = find.byKey(const Key('feed-friends-sign-in'));
    await _scrollTo(tester, signIn);
    await tester.tap(signIn);
    expect(h.app.pending?.kind, PendingKind.myGigs);
  });

  testWidgets('all bands and all venues rows open their collections', (
    tester,
  ) async {
    final h = await _pumpExplore(tester, gigs: _gigs, bands: _bands);
    await _scrollTo(tester, find.byKey(const Key('feed-toggle-bands')));
    await tester.tap(find.byKey(const Key('feed-toggle-bands')));
    expect(h.app.current.screen, Screen.exploreCollection);
    expect(h.app.current.param, 'bands');
    h.app.go(Screen.home);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('feed-toggle-venues')));
    await tester.tap(find.byKey(const Key('feed-toggle-venues')));
    expect(h.app.current.screen, Screen.exploreCollection);
    expect(h.app.current.param, 'venues');
  });

  testWidgets(
    'selecting a genre chip switches to the genre page and All restores the feed',
    (tester) async {
      await _pumpExplore(tester, gigs: _gigs, bands: _bands);
      final chip = find.byKey(const Key('feed-genre-punk'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('explore-genre-page')), findsOneWidget);
      expect(find.byKey(const Key('feed-browse-all')), findsNothing);
      await tester.tap(find.byKey(const Key('explore-genre-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feed-browse-all')), findsOneWidget);
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
    expect(find.byKey(const Key('feed-featured')), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('feed-find-people')));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('feed-find-people')), findsOneWidget);
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
          child: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _scrollTo(tester, find.byKey(const Key('feed-find-people')));
    expect(find.byKey(const Key('feed-find-people')), findsOneWidget);
  });
}
