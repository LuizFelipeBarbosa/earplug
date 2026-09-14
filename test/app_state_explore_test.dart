import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/explore_ranking.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';

Future<AppState> _createApp({
  FakeAuthService? auth,
  DemoRepository? repository,
  bool signedIn = true,
}) async {
  final resolvedAuth = auth ?? FakeAuthService();
  if (signedIn) await resolvedAuth.signInDemo();
  final app = AppState.demo(
    repository: repository ?? DemoRepository(auth: resolvedAuth),
    auth: resolvedAuth,
  );
  addTearDown(app.dispose);
  await flushAsyncWork();
  return app;
}

class _HistoryRepository extends DemoRepository {
  _HistoryRepository({required super.auth, required this.historyItems});

  final List<FanHistoryItem> historyItems;

  @override
  Future<List<FanHistoryItem>> history() async => historyItems;
}

class _ExploreFeedRepository extends DemoRepository {
  _ExploreFeedRepository({required super.auth, required this.gigs});

  final List<Gig> gigs;

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(gigs: gigs, venues: DemoData.venues, bands: DemoData.bands),
  );
}

void main() {
  test(
    'exploreHome keeps its identity across unrelated notifications',
    () async {
      final app = await _createApp();
      final before = app.exploreHome;
      app.say('x');
      expect(app.exploreHome, same(before));
    },
  );

  test('following a band refreshes exploreHome', () async {
    final app = await _createApp();
    final before = app.exploreHome;
    app.toggleFollow('b1');
    expect(app.exploreHome, isNot(same(before)));
  });

  test('exploreHome upcoming excludes tonight and week gigs', () async {
    final app = await _createApp();
    final home = app.exploreHome;
    final grouped = {
      ...home.tonight.map((gig) => gig.id),
      ...home.week.map((gig) => gig.id),
    };
    expect(home.upcoming.every((gig) => !grouped.contains(gig.id)), isTrue);
  });

  test('Explore ignores the filter-sheet genre selection', () async {
    final app = await _createApp();
    app.toggleGenre('noise');

    final home = app.exploreHome;
    final visibleIds = {
      ...home.tonight.map((gig) => gig.id),
      ...home.week.map((gig) => gig.id),
      ...home.upcoming.map((gig) => gig.id),
    };
    final nonNoiseGigIds = DemoData.gigs
        .where((gig) => !gig.genres.map(canonicalGenre).contains('noise'))
        .map((gig) => gig.id)
        .toSet();
    expect(visibleIds.intersection(nonNoiseGigIds), isNotEmpty);

    final expectedCounts = <String, int>{};
    for (final gig in DemoData.gigs) {
      for (final genre in gig.genres.map(canonicalGenre)) {
        if (genre != 'noise') {
          expectedCounts[genre] = (expectedCounts[genre] ?? 0) + 1;
        }
      }
    }
    final chipsByGenre = {
      for (final chip in app.exploreGenres) chip.genre: chip,
    };
    for (final entry in expectedCounts.entries) {
      expect(chipsByGenre[entry.key]?.feedCount, entry.value);
    }
  });

  test(
    'exploreGenres includes feed genres and attended history leads ranking',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final history = FanHistoryItem(
        gigId: 'history-1',
        title: 'History',
        startsAt: DateTime.now().subtract(const Duration(days: 20)),
        venueName: 'Venue',
        bandNames: const [],
        genres: const ['surf'],
        flyKey: 'paper',
        flyerUrl: null,
        status: FanHistoryStatus.rsvped,
      );
      final repository = _HistoryRepository(
        auth: auth,
        historyItems: [history],
      );
      final app = await _createApp(auth: auth, repository: repository);
      final genres = app.exploreGenres;
      final feedGenres = DemoData.gigs
          .expand((gig) => gig.genres)
          .map(canonicalGenre)
          .toSet();
      expect(genres.map((chip) => chip.genre), containsAll(feedGenres));
      final ordered = genres.map((chip) => chip.genre).toList();
      expect(ordered.indexOf('surf'), lessThan(ordered.indexOf('garage')));
    },
  );

  test('setExploreGenre builds matching page and clears it', () async {
    final app = await _createApp();
    app.setExploreGenre('  HARDCORE ');
    final page = app.exploreGenrePage;
    expect(page, isNotNull);
    expect(page!.genre, 'hardcore');
    for (final gig in [...page.tonight, ...page.week, ...page.later]) {
      final direct = gig.genres.any(
        (genre) => canonicalGenre(genre) == 'hardcore',
      );
      final lineup = gig.lineup.any(
        (id) => DemoData.bands[id]!.genres.any(
          (genre) => canonicalGenre(genre) == 'hardcore',
        ),
      );
      expect(direct || lineup, isTrue, reason: gig.id);
    }
    app.setExploreGenre(null);
    expect(app.exploreGenrePage, isNull);
  });

  test(
    'changing fan genres invalidates the selected Explore genre page',
    () async {
      final app = await _createApp();
      app.setExploreGenre('hardcore');
      final before = app.exploreGenrePage;
      expect(before, isNotNull);

      final profile = app.profile!;
      final replacementGenre = app.userGenres.contains('noise')
          ? 'punk'
          : 'noise';
      final saved = await app.saveFanProfile(
        name: profile.name,
        bio: profile.bio,
        homeLocation: profile.homeLocation,
        genres: [replacementGenre],
        locationPersonalizationEnabled: profile.locationPersonalizationEnabled,
        followedBandUpdatesEnabled: profile.followedBandUpdatesEnabled,
        shareRsvpsWithFriends: profile.shareRsvpsWithFriends,
      );
      expect(saved, isTrue);
      await flushAsyncWork();

      expect(app.exploreGenrePage, isNot(same(before)));
    },
  );

  test('followed lineup band ranks ahead within a shared day', () async {
    final first = DemoData.gigs
        .firstWhere((gig) => gig.id == 'g2')
        .copyWith(genres: const ['noise']);
    final second = DemoData.gigs
        .firstWhere((gig) => gig.id == 'g3')
        .copyWith(startsAt: first.startsAt, when: GigWhen.week);
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _ExploreFeedRepository(
      auth: auth,
      gigs: [first, second],
    );
    final app = await _createApp(auth: auth, repository: repository);
    app.toggleFollow('b1');
    app.setExploreGenre('noise');
    final page = app.exploreGenrePage!;
    expect(page.week.first.id, 'g2');
  });

  test('exploreCollection resolves synthetic and known collections', () async {
    final app = await _createApp();
    final home = app.exploreHome;
    final tonight = app.exploreCollection('tonight');
    final week = app.exploreCollection('week');
    expect(tonight, isNotNull);
    expect(week, isNotNull);
    expect(
      tonight!.gigs.map((gig) => gig.id),
      home.tonight.map((gig) => gig.id),
    );
    expect(week!.gigs.map((gig) => gig.id), home.week.map((gig) => gig.id));
    expect(app.exploreCollection('does-not-exist'), isNull);
  });

  test(
    'signed out exploreHome is not personalised but recommends bands',
    () async {
      final auth = FakeAuthService();
      final app = await _createApp(auth: auth, signedIn: false);
      expect(app.exploreHome.personalised, isFalse);
      expect(app.exploreHome.recommendedBandIds, isNotEmpty);
    },
  );
}
