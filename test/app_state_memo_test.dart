import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feed is stable until the next notification', () async {
    final app = await _createApp();

    final before = app.feed;
    expect(app.feed, same(before));

    app.setPriceFilter(PriceFilter.free);
    final filtered = app.feed;
    expect(filtered, isNot(same(before)));
    expect(filtered.map((gig) => gig.id), unorderedEquals(['g1', 'g5']));
    expect(filtered.every((gig) => gig.free), isTrue);

    final filteredIds = filtered.map((gig) => gig.id).toList();
    app.say('Unrelated notification');
    final refreshed = app.feed;
    expect(refreshed, isNot(same(filtered)));
    expect(refreshed.map((gig) => gig.id), filteredIds);
  });

  test('derived collection getters reuse their cached instances', () async {
    final app = await _createApp();

    final venues = app.venues;
    final upcomingRsvps = app.upcomingRsvpGigs;
    final followedShows = app.followedBandShows;
    final bandGigs = app.myBandGigs;

    expect(app.venues, same(venues));
    expect(app.upcomingRsvpGigs, same(upcomingRsvps));
    expect(app.followedBandShows, same(followedShows));
    expect(app.myBandGigs, same(bandGigs));
  });

  test(
    'cached discovery boost membership matches explicit computation',
    () async {
      final app = await _createApp();

      for (final gig in app.feed) {
        final expected = app.isDiscoveryBoosted(gig, now: DateTime.now());
        expect(app.isDiscoveryBoosted(gig), expected, reason: gig.id);
      }
    },
  );

  test('gig lookup resolves feed and RSVP-derived gigs', () async {
    final app = await _createApp();

    final feedGig = app.feed.first;
    expect(app.gig(feedGig.id), same(feedGig));

    // This covers the RSVP interaction path; DemoRepository keeps its
    // followed-band shows in the same discovery feed.
    app.toggleRsvp('g2');
    await _flushAsyncWork();
    expect(app.upcomingRsvpGigs.map((gig) => gig.id), contains('g2'));
    expect(app.gig('g2')?.id, 'g2');
  });

  test(
    'followed-band gig streams run only while the feed is truncated',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _SubscriptionSpyRepository(auth: auth);
      final app = AppState.demo(repository: repository, auth: auth);
      addTearDown(() async {
        app.dispose();
        await _flushAsyncWork();
        await repository.close();
      });

      repository.emitFeed();
      await _flushAsyncWork();
      expect(repository.upcomingBandIds, isEmpty);

      repository.emitFeed(
        nextStartsAt: DateTime.now().add(const Duration(days: 30)),
      );
      await _flushAsyncWork();
      expect(repository.upcomingBandIds, unorderedEquals(['b2', 'b4']));
      expect(repository.activeUpcomingSubscriptions, 2);

      repository.emitFeed();
      await _flushAsyncWork();
      expect(repository.activeUpcomingSubscriptions, 0);
    },
  );

  test('unchanged feed updates preserve band object identity', () async {
    final auth = FakeAuthService();
    final repository = _SubscriptionSpyRepository(auth: auth);
    final app = AppState.demo(repository: repository, auth: auth);
    addTearDown(() async {
      app.dispose();
      await repository.close();
    });

    repository.emitFeed();
    await _flushAsyncWork();
    final band = app.band('b1');

    repository.emitFeed();
    await _flushAsyncWork();
    expect(app.band('b1'), same(band));
  });

  test(
    'feed summaries merge into full bands without clobbering them',
    () async {
      final auth = FakeAuthService();
      final repository = _SubscriptionSpyRepository(auth: auth);
      final app = AppState.demo(repository: repository, auth: auth);
      addTearDown(() async {
        app.dispose();
        await repository.close();
      });
      final fullBand = DemoData.bands['b1']!;
      repository.emitFeed(bands: {fullBand.id: fullBand});
      await _flushAsyncWork();

      final summary = Band.fromJson({
        '_id': fullBand.id,
        'slug': 'foghorn-diet-live',
        'name': 'Foghorn Diet Live',
        'genres': ['garage', 'punk'],
        'area': 'Oakland',
        'colorHex': '#123456',
        'initials': 'FL',
        'followerCount': fullBand.followers + 12,
        'avatarUrl': 'https://example.com/foghorn.jpg',
        'profileComplete': true,
        'discoveryProfileReady': true,
      });
      expect(summary.isSummary, isTrue);

      repository.emitFeed(bands: {fullBand.id: summary});
      await _flushAsyncWork();
      final merged = app.band(fullBand.id)!;
      expect(merged.name, summary.name);
      expect(merged.followers, summary.followers);
      expect(merged.color, summary.color);
      expect(merged.bio, fullBand.bio);
      expect(merged.past, fullBand.past);
      expect(merged.isSummary, isFalse);

      repository.emitFeed(bands: {fullBand.id: summary});
      await _flushAsyncWork();
      expect(app.band(fullBand.id), same(merged));

      repository.emitFeed(
        gigs: [
          for (final gig in DemoData.gigs)
            if (gig.id != 'g7') gig,
        ],
        bands: {fullBand.id: summary},
      );
      await _flushAsyncWork();
      final updatedUpcoming = app.band(fullBand.id)!;
      expect(updatedUpcoming.upcoming, ['g2']);
      expect(updatedUpcoming.bio, fullBand.bio);
      expect(updatedUpcoming.past, fullBand.past);
      expect(updatedUpcoming.isSummary, isFalse);
    },
  );

  test('going counts update RSVP totals without a new feed snapshot', () async {
    final auth = FakeAuthService();
    final repository = _SubscriptionSpyRepository(auth: auth);
    final app = AppState.demo(repository: repository, auth: auth);
    addTearDown(() async {
      app.dispose();
      await repository.close();
    });

    repository.emitFeed();
    await _flushAsyncWork();
    final gig = app.feed.first;
    final updatedCount = gig.going + 7;

    repository.emitGoingCounts({gig.id: updatedCount});
    await _flushAsyncWork();

    expect(app.rsvpCount(gig), updatedCount);
  });

  test('equal going count updates notify listeners only once', () async {
    final auth = FakeAuthService();
    final repository = _SubscriptionSpyRepository(auth: auth);
    final app = AppState.demo(repository: repository, auth: auth);
    addTearDown(() async {
      app.dispose();
      await repository.close();
    });
    await _flushAsyncWork();
    var notifications = 0;
    app.addListener(() => notifications++);

    repository.emitGoingCounts(const {'g1': 12});
    await _flushAsyncWork();
    repository.emitGoingCounts(const {'g1': 12});
    await _flushAsyncWork();

    expect(notifications, 1);
  });

  test('opening a summary band loads the full band exactly once', () async {
    final auth = FakeAuthService();
    final repository = _SummaryBandRepository(auth: auth);
    final app = AppState.demo(repository: repository, auth: auth);
    addTearDown(() async {
      app.dispose();
      await repository.close();
    });
    final fullBand = DemoData.bands['b1']!;
    final summaryBand = fullBand.copyWith(isSummary: true);
    repository.bandValue = fullBand;
    repository.emitFeed(bands: {summaryBand.id: summaryBand});
    await _flushAsyncWork();

    app.openBand(summaryBand.id);
    app.openBand(summaryBand.id);
    await _flushAsyncWork();

    expect(repository.bandCalls, 1);
    expect(app.band(summaryBand.id)?.isSummary, isFalse);
  });

  test(
    'leaving a gig cancels its stream but keeps the fetched gig cached',
    () async {
      final auth = FakeAuthService();
      final repository = _SubscriptionSpyRepository(auth: auth);
      final app = AppState.demo(repository: repository, auth: auth);
      addTearDown(() async {
        app.dispose();
        await _flushAsyncWork();
        await repository.close();
      });

      repository.emitFeed();
      await _flushAsyncWork();
      final streamedGig = DemoData.gigs.first.copyWith(
        going: DemoData.gigs.first.going + 10,
      );
      repository.publicGigValue = streamedGig;

      app.openGig(streamedGig.id);
      await _flushAsyncWork();
      expect(repository.publicGigCalls, 1);
      expect(app.gig(streamedGig.id), same(streamedGig));

      app.back();
      await _flushAsyncWork();
      expect(repository.publicGigCancellations, 1);
      expect(app.gig(streamedGig.id), same(streamedGig));
      await _flushAsyncWork();
      expect(repository.publicGigCalls, 1);
    },
  );
}

Future<AppState> _createApp() async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final app = AppState.demo(
    repository: DemoRepository(auth: auth),
    auth: auth,
  );
  addTearDown(app.dispose);
  await _flushAsyncWork();
  return app;
}

Future<void> _flushAsyncWork() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _SubscriptionSpyRepository extends DemoRepository {
  _SubscriptionSpyRepository({required super.auth});

  final _feedController = StreamController<FeedSnapshot>.broadcast();
  final _goingCountsController = StreamController<Map<String, int>>.broadcast();
  final List<StreamController<List<Gig>>> _upcomingControllers = [];
  final List<StreamController<Gig?>> _publicGigControllers = [];
  final List<String> upcomingBandIds = [];
  var activeUpcomingSubscriptions = 0;
  var publicGigCalls = 0;
  var publicGigCancellations = 0;
  var bandCalls = 0;
  Gig? publicGigValue;
  Band? bandValue;

  @override
  Stream<FeedSnapshot> feed() => _feedController.stream;

  @override
  Stream<Map<String, int>> goingCounts() => _goingCountsController.stream;

  void emitFeed({
    DateTime? nextStartsAt,
    List<Gig>? gigs,
    Map<String, Band>? bands,
  }) {
    _feedController.add(
      FeedSnapshot(
        gigs: gigs ?? DemoData.gigs,
        venues: DemoData.venues,
        bands: bands ?? DemoData.bands,
        nextStartsAt: nextStartsAt,
      ),
    );
  }

  void emitGoingCounts(Map<String, int> goingCounts) {
    _goingCountsController.add(goingCounts);
  }

  @override
  Future<Band?> band(String bandId) async {
    bandCalls++;
    return bandValue ?? super.band(bandId);
  }

  @override
  Stream<List<Gig>> upcomingGigsForBand(String bandId) {
    upcomingBandIds.add(bandId);
    late final StreamController<List<Gig>> controller;
    controller = StreamController<List<Gig>>(
      onListen: () {
        activeUpcomingSubscriptions++;
        controller.add([
          for (final gig in DemoData.gigs)
            if (gig.lineup.contains(bandId)) gig,
        ]);
      },
      onCancel: () => activeUpcomingSubscriptions--,
    );
    _upcomingControllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<Gig?> publicGig(String gigId) {
    publicGigCalls++;
    late final StreamController<Gig?> controller;
    controller = StreamController<Gig?>(
      onListen: () => controller.add(publicGigValue),
      onCancel: () => publicGigCancellations++,
    );
    _publicGigControllers.add(controller);
    return controller.stream;
  }

  Future<void> close() async {
    await _feedController.close();
    await _goingCountsController.close();
    for (final controller in _upcomingControllers) {
      if (!controller.isClosed) await controller.close();
    }
    for (final controller in _publicGigControllers) {
      if (!controller.isClosed) await controller.close();
    }
  }
}

class _SummaryBandRepository extends _SubscriptionSpyRepository {
  _SummaryBandRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() => const Stream.empty();
}
