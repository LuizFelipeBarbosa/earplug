import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listing edits invalidate the affected cached venue detail', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _FeedTransitionRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(() async {
      app.dispose();
      await _flushAsyncWork();
      await repository.close();
    });

    final gig = DemoData.gigs.firstWhere((gig) => gig.id == 'g2');
    repository.emitFeed(gigs: [gig]);
    await _flushAsyncWork();

    expect(app.venueDetail(gig.venueId), isNull);
    expect(app.venueDetailLoading(gig.venueId), isTrue);
    await _flushAsyncWork();
    final cached = app.venueDetail(gig.venueId);
    expect(cached?.gigs.single.title, gig.title);

    final renamed = gig.copyWith(title: '${gig.title} — Late Set');
    repository.emitFeed(gigs: [renamed]);
    await _flushAsyncWork();

    expect(app.venueDetail(gig.venueId), isNull);
    expect(app.venueDetailLoading(gig.venueId), isTrue);
    await _flushAsyncWork();
    expect(app.venueDetail(gig.venueId)?.gigs.single.title, renamed.title);
  });

  test(
    'feed summary clears a full band avatar without losing its bio',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _FeedTransitionRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(() async {
        app.dispose();
        await _flushAsyncWork();
        await repository.close();
      });

      final gig = DemoData.gigs.firstWhere((gig) => gig.id == 'g2');
      final fullBand = Band.fromJson({
        ..._bandJson(),
        'bio': 'The original full-profile bio.',
        'avatarUrl': 'https://example.com/original-avatar.jpg',
        'bannerUrl': 'https://example.com/original-banner.jpg',
        'pastShows': const <Map<String, String>>[],
      });
      repository.emitFeed(gigs: [gig], bands: {fullBand.id: fullBand});
      await _flushAsyncWork();

      final summary = Band.fromJson({..._bandJson(), 'avatarUrl': null});
      expect(summary.isSummary, isTrue);
      expect(summary.avatarUrlResolved, isTrue);
      repository.emitFeed(gigs: [gig], bands: {summary.id: summary});
      await _flushAsyncWork();

      final merged = app.band(fullBand.id)!;
      expect(merged.avatarUrl, isNull);
      expect(merged.bio, fullBand.bio);
      expect(merged.isSummary, isFalse);

      repository.emitFeed(gigs: [gig], bands: {summary.id: summary});
      await _flushAsyncWork();
      expect(app.band(fullBand.id), same(merged));
    },
  );

  test(
    'truncated feed retains relationship gigs but removes dropped gigs',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _FeedTransitionRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(() async {
        app.dispose();
        await _flushAsyncWork();
        await repository.close();
      });

      final feedGig = DemoData.gigs.firstWhere((gig) => gig.id == 'g2');
      final outsideGig = DemoData.gigs.firstWhere((gig) => gig.id == 'g7');
      final band = DemoData.bands['b1']!;
      final nextStartsAt = DateTime.now().add(const Duration(days: 30));
      repository.emitFeed(
        gigs: [feedGig],
        bands: {band.id: band},
        nextStartsAt: nextStartsAt,
      );
      await _flushAsyncWork();

      repository.detailGigs = [feedGig, outsideGig];
      expect(app.venueDetail(feedGig.venueId), isNull);
      await _flushAsyncWork();
      expect(app.band(band.id)?.upcoming, [feedGig.id, outsideGig.id]);

      repository.emitFeed(
        gigs: [feedGig],
        bands: {band.id: band},
        nextStartsAt: nextStartsAt,
      );
      await _flushAsyncWork();
      expect(app.band(band.id)?.upcoming, [feedGig.id, outsideGig.id]);

      repository.emitFeed(
        gigs: const [],
        bands: {band.id: band},
        nextStartsAt: nextStartsAt,
      );
      await _flushAsyncWork();
      expect(app.band(band.id)?.upcoming, [outsideGig.id]);
    },
  );

  test('readiness waits for counts and count emissions merge', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _FeedTransitionRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(() async {
      app.dispose();
      await _flushAsyncWork();
      await repository.close();
    });

    app.retry();
    await _flushAsyncWork();
    final gig = DemoData.gigs
        .firstWhere((gig) => gig.id == 'g2')
        .copyWith(going: 0);
    repository.emitFeed(gigs: [gig]);
    await _flushAsyncWork();
    expect(app.dataStatus, DataStatus.connecting);

    repository.emitGoingCounts({gig.id: 41});
    await _flushAsyncWork();
    expect(app.rsvpCount(gig), 41);
    expect(app.dataStatus, DataStatus.ready);

    repository.emitGoingCounts(const {});
    await _flushAsyncWork();
    expect(app.rsvpCount(gig), 41);
  });

  test(
    'a going-counts error settles readiness after the feed arrives',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _FeedTransitionRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(() async {
        app.dispose();
        await _flushAsyncWork();
        await repository.close();
      });

      app.retry();
      await _flushAsyncWork();
      final gig = DemoData.gigs.firstWhere((gig) => gig.id == 'g2');
      repository.emitFeed(gigs: [gig]);
      await _flushAsyncWork();
      expect(app.dataStatus, DataStatus.connecting);

      repository.emitGoingCountsError(StateError('counts unavailable'));
      await _flushAsyncWork();
      expect(app.dataStatus, DataStatus.ready);
    },
  );
}

class _FeedTransitionRepository extends DemoRepository {
  _FeedTransitionRepository({required super.auth});

  final _feedController = StreamController<FeedSnapshot>.broadcast();
  final _goingCountsController = StreamController<Map<String, int>>.broadcast();
  List<Gig> _currentGigs = const [];
  List<Gig>? detailGigs;

  @override
  Stream<FeedSnapshot> feed() => _feedController.stream;

  @override
  Stream<Map<String, int>> goingCounts() => _goingCountsController.stream;

  @override
  Stream<List<BandMembership>> myBands() => const Stream.empty();

  void emitFeed({
    required List<Gig> gigs,
    Map<String, Band>? bands,
    DateTime? nextStartsAt,
  }) {
    _currentGigs = List<Gig>.of(gigs);
    _feedController.add(
      FeedSnapshot(
        gigs: gigs,
        venues: DemoData.venues,
        bands: bands ?? DemoData.bands,
        nextStartsAt: nextStartsAt,
      ),
    );
  }

  void emitGoingCounts(Map<String, int> goingCounts) {
    _goingCountsController.add(goingCounts);
  }

  void emitGoingCountsError(Object error) {
    _goingCountsController.addError(error);
  }

  @override
  Future<VenueDetail?> venueDetail(String venueId) async {
    final gigs = detailGigs ?? _currentGigs;
    return VenueDetail(
      venue: DemoData.venues[venueId]!,
      gigs: [
        for (final gig in gigs)
          if (gig.venueId == venueId) gig,
      ],
      bands: {
        for (final gig in gigs)
          if (gig.venueId == venueId)
            for (final bandId in gig.lineup)
              if (DemoData.bands[bandId] case final Band band) bandId: band,
      },
      truncated: false,
    );
  }

  Future<void> close() async {
    await _feedController.close();
    await _goingCountsController.close();
  }
}

Map<String, dynamic> _bandJson() => <String, dynamic>{
  '_id': 'b1',
  'slug': 'foghorn-diet',
  'name': 'Foghorn Diet',
  'genres': ['garage', 'surf punk'],
  'area': 'Mission, SF',
  'colorHex': '#7B8FFF',
  'initials': 'FD',
  'followerCount': 486,
  'profileComplete': true,
  'discoveryProfileReady': true,
};

Future<void> _flushAsyncWork() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
