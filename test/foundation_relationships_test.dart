import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/convex_repository.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('age requirements', () {
    test('parses wire values, labels them, and defaults legacy gigs', () {
      expect(AgeRequirement.fromJson(null), AgeRequirement.allAges);
      expect(AgeRequirement.fromJson('allAges'), AgeRequirement.allAges);
      expect(AgeRequirement.fromJson('18Plus'), AgeRequirement.eighteenPlus);
      expect(AgeRequirement.fromJson('21Plus'), AgeRequirement.twentyOnePlus);
      expect(AgeRequirement.values.map((value) => value.label), [
        'All ages',
        '18+',
        '21+',
      ]);

      expect(Gig.fromJson(_gigJson()).ageRequirement, AgeRequirement.allAges);
      expect(
        Gig.fromJson(_gigJson(ageRequirement: '21Plus')).ageRequirement,
        AgeRequirement.twentyOnePlus,
      );
    });
  });

  group('relationship payload parsing', () {
    test('preserves standard Convex band page metadata', () {
      final page = parseBandPage({
        'page': [_bandJson('b1', 'Alpha')],
        'continueCursor': 'opaque-end-cursor',
        'isDone': true,
      });

      expect(page.items.single.name, 'Alpha');
      expect(page.continueCursor, 'opaque-end-cursor');
      expect(page.isDone, isTrue);
    });

    test('parses a venue detail and normalizes legacy gig age', () {
      final detail = parseVenueDetail({
        'venue': _venueJson(),
        'gigs': [_gigJson()],
        'bands': [_bandJson('b1', 'Alpha')],
        'truncated': true,
      });

      expect(detail, isNotNull);
      expect(detail!.venue.id, 'v1');
      expect(detail.gigs.single.ageRequirement, AgeRequirement.allAges);
      expect(detail.bands.keys, ['b1']);
      expect(detail.truncated, isTrue);
      expect(parseVenueDetail(null), isNull);
    });

    test('parses hydrated interaction gigs outside the feed payload', () {
      final interactions = parseInteractions({
        'rsvpGigIds': ['outside-feed'],
        'followBandIds': <String>[],
        'savedGigIds': ['outside-feed'],
        'gigs': [_gigJson(id: 'outside-feed')],
        'attendedCount': 7,
      });

      expect(interactions.rsvpGigIds, {'outside-feed'});
      expect(interactions.savedGigIds, {'outside-feed'});
      expect(interactions.gigs.single.id, 'outside-feed');
      expect(interactions.attendedCount, 7);
    });
  });

  test(
    'band pagination retries the same cursor and merges duplicates',
    () async {
      final auth = FakeAuthService();
      final repository = _PagedRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(app.dispose);

      await _flushAsyncWork();
      expect(app.exploreBandIds, ['b1', 'b2']);
      expect(app.hasMoreExploreBands, isTrue);

      app.loadMoreExploreBands();
      await _flushAsyncWork();
      expect(app.exploreBandIds, ['b1', 'b2']);
      expect(app.exploreBandsError, contains('page failed'));
      expect(app.hasMoreExploreBands, isTrue);

      app.retryExploreBands();
      await _flushAsyncWork();
      expect(app.exploreBandIds, ['b1', 'b2', 'b3']);
      expect(app.exploreBandsError, isNull);
      expect(app.hasMoreExploreBands, isFalse);
      expect(repository.cursors, [null, 'page-2', 'page-2']);
    },
  );

  test(
    'band pages preserve live duplicates and add directory-only rows',
    () async {
      final auth = FakeAuthService();
      final repository = _MergePrecedenceRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(app.dispose);

      await _flushAsyncWork();
      expect(app.band('b1')?.past, hasLength(4));

      repository.pageGate.complete();
      await _flushAsyncWork();

      expect(app.exploreBandIds, ['b1', 'directory-only']);
      expect(app.band('b1')?.bio, DemoData.bands['b1']!.bio);
      expect(app.band('b1')?.past, DemoData.bands['b1']!.past);
      expect(app.band('directory-only')?.name, 'Directory Only');
    },
  );

  test(
    'band creation queues a directory restart during an active page',
    () async {
      final auth = FakeAuthService();
      final repository = _QueuedRefreshRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(app.dispose);

      await repository.firstPageStarted.future;
      app.setNbName('Refresh Youth');
      app.toggleNbGenre('punk');
      app.setNbArea('Oakland');

      await app.createBand();
      final createdBandId = app.bandId;
      expect(repository.cursors, [null]);

      repository.releaseFirstPage.complete();
      await _flushAsyncWork();

      expect(repository.cursors, [null, null]);
      expect(app.exploreBandIds, contains(createdBandId));
      expect(app.hasMoreExploreBands, isFalse);
    },
  );

  test('venue detail retries, caches, and supports venue navigation', () async {
    final auth = FakeAuthService();
    final repository = _VenueRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);

    expect(app.venueDetail('v1'), isNull);
    await _flushAsyncWork();
    expect(app.venueDetailError('v1'), contains('detail failed'));

    app.retryVenueDetail('v1');
    await _flushAsyncWork();
    final detail = app.venueDetail('v1');
    expect(detail?.venue.name, DemoData.venues['v1']!.name);
    expect(app.gig('g1'), same(DemoData.gigs.first));
    expect(repository.detailCalls, 2);

    expect(app.venueDetail('v1'), same(detail));
    await _flushAsyncWork();
    expect(repository.detailCalls, 2);

    app.openVenue('v1');
    expect(app.current.screen, Screen.venue);
    expect(app.current.param, 'v1');
    app.back();
    expect(app.current.screen, Screen.home);
  });

  test('feed changes invalidate cached venue details', () async {
    final auth = FakeAuthService();
    final freshGig = Gig.fromJson(
      _gigJson(id: 'fresh-gig', title: 'Just announced'),
    );
    final repository = _RefreshingVenueRepository(
      auth: auth,
      freshGig: freshGig,
    );
    final app = AppState(repository: repository, auth: auth);
    addTearDown(() async {
      app.dispose();
      await repository.dispose();
    });

    repository.emitFeed([repository.oldGig]);
    await _flushAsyncWork();
    expect(app.venueDetail('v1'), isNull);
    await _flushAsyncWork();
    expect(app.venueDetail('v1')?.gigs.map((gig) => gig.id), [
      repository.oldGig.id,
    ]);
    expect(repository.detailCalls, 1);

    repository.emitFeed([repository.oldGig, freshGig]);
    await _flushAsyncWork();
    expect(app.venueDetail('v1'), isNull);
    await _flushAsyncWork();

    expect(app.venueDetail('v1')?.gigs.map((gig) => gig.id), [
      repository.oldGig.id,
      freshGig.id,
    ]);
    expect(repository.detailCalls, 2);
  });

  test(
    'publishing invalidates venue details without a feed emission',
    () async {
      final auth = FakeAuthService();
      final repository = _SilentPublishRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(app.dispose);

      await _flushAsyncWork();
      expect(app.venueDetail('v1'), isNull);
      await _flushAsyncWork();
      expect(repository.detailCalls, 1);

      app.startGigCreate();
      app.setGfName('Beyond the feed');
      app.setGfDate(DateTime.now().add(const Duration(days: 30)));
      app.setGfVenue('v1');
      await app.publishGig();
      expect(app.gfPublished, isTrue);

      expect(app.venueDetail('v1'), isNull);
      await _flushAsyncWork();
      expect(repository.detailCalls, 2);
      expect(
        app.venueDetail('v1')?.gigs.map((gig) => gig.title),
        contains('Beyond the feed'),
      );
    },
  );

  test('save requests require auth and roll back rejected writes', () async {
    final auth = FakeAuthService();
    final repository = _GatedSaveRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);

    app.requestSave('g1');
    expect(app.pending?.kind, PendingKind.save);
    expect(app.current.screen, Screen.auth);
    expect(app.saved, isNot(contains('g1')));

    await auth.signInDemo();
    await _flushAsyncWork();
    app.commitAuth();
    expect(app.saved, contains('g1'));

    repository.saveGate.completeError(StateError('save failed'));
    await _flushAsyncWork();
    expect(app.saved, isNot(contains('g1')));
    expect(app.toast, isNotEmpty);
  });

  test('result type changes do not alter the submitted query', () {
    final auth = FakeAuthService();
    final app = AppState(
      repository: DemoRepository(auth: auth),
      auth: auth,
    );
    addTearDown(app.dispose);

    app.setQuery('  Foghorn  ');
    app.setExploreResultType(ExploreResultType.venues);
    expect(app.query, '  Foghorn  ');
    expect(app.exploreResultType, ExploreResultType.venues);

    app.setQuery('');
    expect(app.exploreResultType, ExploreResultType.all);
  });
}

class _PagedRepository extends DemoRepository {
  _PagedRepository({required super.auth});

  final List<String?> cursors = [];
  var secondPageAttempts = 0;

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async {
    cursors.add(cursor);
    if (cursor == null) {
      return BandPage(
        items: [DemoData.bands['b1']!, DemoData.bands['b2']!],
        continueCursor: 'page-2',
        isDone: false,
      );
    }
    if (secondPageAttempts++ == 0) throw StateError('page failed');
    return BandPage(
      items: [DemoData.bands['b2']!, DemoData.bands['b3']!],
      continueCursor: 'done',
      isDone: true,
    );
  }
}

class _QueuedRefreshRepository extends DemoRepository {
  _QueuedRefreshRepository({required super.auth});

  final firstPageStarted = Completer<void>();
  final releaseFirstPage = Completer<void>();
  final List<String?> cursors = [];
  var _firstCall = true;

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async {
    cursors.add(cursor);
    final page = await super.listBands(cursor: cursor, numItems: numItems);
    if (_firstCall) {
      _firstCall = false;
      firstPageStarted.complete();
      await releaseFirstPage.future;
    }
    return page;
  }
}

class _VenueRepository extends DemoRepository {
  _VenueRepository({required super.auth});

  var detailCalls = 0;

  @override
  Future<VenueDetail?> venueDetail(String venueId) async {
    detailCalls++;
    if (detailCalls == 1) throw StateError('detail failed');
    return VenueDetail(
      venue: DemoData.venues[venueId]!,
      gigs: [DemoData.gigs.first],
      bands: {
        for (final id in DemoData.gigs.first.lineup) id: DemoData.bands[id]!,
      },
      truncated: false,
    );
  }
}

class _RefreshingVenueRepository extends DemoRepository {
  _RefreshingVenueRepository({required super.auth, required this.freshGig});

  final Gig freshGig;
  final oldGig = DemoData.gigs.firstWhere((gig) => gig.venueId == 'v1');
  final _feedController = StreamController<FeedSnapshot>.broadcast();
  var detailCalls = 0;

  @override
  Stream<FeedSnapshot> feed() => _feedController.stream;

  void emitFeed(List<Gig> gigs) {
    _feedController.add(
      FeedSnapshot(gigs: gigs, venues: DemoData.venues, bands: DemoData.bands),
    );
  }

  @override
  Future<VenueDetail?> venueDetail(String venueId) async {
    detailCalls++;
    return VenueDetail(
      venue: DemoData.venues[venueId]!,
      gigs: detailCalls == 1 ? [oldGig] : [oldGig, freshGig],
      bands: const {},
      truncated: false,
    );
  }

  Future<void> dispose() => _feedController.close();
}

class _SilentPublishRepository extends DemoRepository {
  _SilentPublishRepository({required super.auth});

  var detailCalls = 0;

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: DemoData.gigs,
      venues: DemoData.venues,
      bands: DemoData.bands,
    ),
  );

  @override
  Future<VenueDetail?> venueDetail(String venueId) {
    detailCalls++;
    return super.venueDetail(venueId);
  }
}

class _MergePrecedenceRepository extends DemoRepository {
  _MergePrecedenceRepository({required super.auth});

  final pageGate = Completer<void>();

  static final _staleDuplicate = Band(
    id: DemoData.bands['b1']!.id,
    name: DemoData.bands['b1']!.name,
    genres: DemoData.bands['b1']!.genres,
    area: DemoData.bands['b1']!.area,
    color: DemoData.bands['b1']!.color,
    initials: DemoData.bands['b1']!.initials,
    followers: DemoData.bands['b1']!.followers,
    bio: 'Stale directory bio.',
    past: const [],
  );

  static const _directoryOnly = Band(
    id: 'directory-only',
    name: 'Directory Only',
    genres: ['punk'],
    area: 'Mission, SF',
    color: Color(0xFF1435F0),
    initials: 'DO',
    followers: 1,
    bio: 'Only returned by pagination.',
  );

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async {
    await pageGate.future;
    return BandPage(
      items: [_staleDuplicate, _directoryOnly],
      continueCursor: 'done',
      isDone: true,
    );
  }
}

class _GatedSaveRepository extends DemoRepository {
  _GatedSaveRepository({required super.auth});

  final saveGate = Completer<void>();

  @override
  Future<void> toggleSave(String gigId) => saveGate.future;
}

Future<void> _flushAsyncWork() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> _venueJson() => {
  '_id': 'v1',
  'name': 'Room One',
  'area': 'Mission, SF',
  'addr': '1 Main St',
  'distSF': '1.0 mi',
  'distOak': '8.0 mi',
  'lat': 37.75,
  'lng': -122.42,
};

Map<String, dynamic> _bandJson(String id, String name) => {
  '_id': id,
  'name': name,
  'genres': ['punk'],
  'area': 'Mission, SF',
  'colorHex': '#1435F0',
  'initials': 'A',
  'followerCount': 3,
  'bio': 'Loud.',
};

Map<String, dynamic> _gigJson({
  String id = 'g1',
  String title = 'Show',
  String? ageRequirement,
}) => {
  '_id': id,
  'title': title,
  'venueId': 'v1',
  'price': 0,
  'startsAt': DateTime.now()
      .add(const Duration(days: 1))
      .millisecondsSinceEpoch,
  'doorsTime': '8PM / 9PM',
  'flyKey': 'paper',
  'lineup': ['b1'],
  'goingCount': 4,
  'genres': ['punk'],
  'desc': 'Loud.',
  'ticketing': 'rsvp',
  'cap': 'No cap',
  'ageRequirement': ?ageRequirement,
};
