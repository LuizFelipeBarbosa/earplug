import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/explore_collection.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('gig collection lists shows and back returns to Explore', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(
        body: ExploreCollectionScreen(collectionKey: 'tonight'),
      ),
    );
    harness.app.go(Screen.explore);
    harness.app.go(Screen.exploreCollection, 'tonight');
    await tester.pumpAndSettle();

    final collection = harness.app.exploreCollection('tonight')!;
    expect(collection.gigs, isNotEmpty);
    expect(
      find.text(collection.gigs.first.title.toUpperCase()),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    expect(harness.app.current.screen, Screen.explore);
  });

  testWidgets('band directory pages and deduplicates bands', (tester) async {
    final auth = FakeAuthService();
    final repository = _PagedBandsRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(
        body: ExploreCollectionScreen(collectionKey: 'bands'),
      ),
    );
    harness.app.go(Screen.exploreCollection, 'bands');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-all-bands')), findsOneWidget);
    expect(find.byKey(const Key('explore-bands-load-more')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-bands-load-more')));
    await tester.pumpAndSettle();

    expect(repository.bandCalls, 2);
    expect(find.text('PIGEON COURT', skipOffstage: false), findsOneWidget);
    expect(find.text('MISSION CREEP', skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('explore-bands-end')), findsOneWidget);
  });

  testWidgets(
    'venues collection excludes venues without upcoming shows and opens a venue',
    (tester) async {
      final auth = FakeAuthService();
      final gigs = DemoData.gigs.where((gig) => gig.venueId != 'v6').toList();
      final stubbed = _FeedRepository(auth: auth, gigs: gigs);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: stubbed,
        home: const Scaffold(
          body: ExploreCollectionScreen(collectionKey: 'venues'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('explore-venue-v1')), findsOneWidget);
      expect(find.byKey(const Key('explore-venue-v6')), findsNothing);
      await tester.tap(find.byKey(const Key('explore-venue-v1')));
      await tester.pump();
      expect(harness.app.current.screen, Screen.venue);
      expect(harness.app.current.param, 'v1');
    },
  );

  testWidgets('friends collection lists friend-going entries', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _SocialRepository(auth: auth);
    final gig = DemoData.gigs.first;
    repository.result = FriendsGoing(
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
      ],
      truncated: false,
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(
        body: ExploreCollectionScreen(collectionKey: 'friends'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('explore-friends-gig-${gig.id}')), findsOneWidget);
    expect(find.text(gig.title.toUpperCase()), findsOneWidget);
    await tester.tap(find.byKey(Key('explore-friends-gig-${gig.id}')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, gig.id);
  });

  testWidgets('empty friends collection offers Find people', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _SocialRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(
        body: ExploreCollectionScreen(collectionKey: 'friends'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("No friends have RSVP'd for this weekend yet."),
      findsOneWidget,
    );
    await tester.tap(find.text('FIND PEOPLE'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.people);
  });

  testWidgets('unknown and null keys render unavailable state', (tester) async {
    await pumpApp(
      tester,
      home: const Scaffold(
        body: ExploreCollectionScreen(collectionKey: 'not-a-real-key'),
      ),
    );
    expect(find.text("This collection isn't available."), findsOneWidget);

    await pumpApp(
      tester,
      home: const Scaffold(body: ExploreCollectionScreen(collectionKey: null)),
    );
    expect(find.text("This collection isn't available."), findsOneWidget);
  });
}

class _PagedBandsRepository extends DemoRepository {
  _PagedBandsRepository({required super.auth});

  int bandCalls = 0;

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async {
    bandCalls++;
    if (cursor == null) {
      return BandPage(
        items: [DemoData.bands['b1']!, DemoData.bands['b2']!],
        continueCursor: 'next',
        isDone: false,
      );
    }
    return BandPage(
      items: [DemoData.bands['b2']!, DemoData.bands['b3']!],
      continueCursor: null,
      isDone: true,
    );
  }
}

class _FeedRepository extends DemoRepository {
  _FeedRepository({required super.auth, required this.gigs});

  final List<Gig> gigs;

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(gigs: gigs, venues: DemoData.venues, bands: DemoData.bands),
  );
}

class _SocialRepository extends DemoRepository {
  _SocialRepository({required super.auth});

  FriendsGoing result = FriendsGoing.empty;

  @override
  Future<FriendsGoing> friendsGoing({
    required DateTime from,
    required DateTime to,
  }) async => result;
}
