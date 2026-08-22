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

Map<String, dynamic> _gigJson({String? ageRequirement}) => {
  '_id': 'g1',
  'title': 'Show',
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
