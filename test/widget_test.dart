import 'package:flutter_test/flutter_test.dart';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/convex_repository.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';

void main() {
  group('AppState', () {
    test('starts on home feed with all demo gigs', () async {
      final app = await _demoApp();
      expect(app.current.screen, Screen.home);
      expect(app.feed.length, 7);
    });

    test('filters combine: free + tonight', () async {
      final app = await _demoApp();
      app.toggleFree();
      app.toggleDateFilter(DateFilter.tonight);
      expect(app.feed.map((g) => g.id), ['g1']);
    });

    test('RSVP requires auth, then completes the pending action', () async {
      final app = await _demoApp();
      app.openGig('g1');
      app.requestRsvp('g1');
      expect(app.current.screen, Screen.auth);
      await app.login();
      app.finishAuth();
      expect(app.rsvps, contains('g1'));
      expect(app.current.screen, Screen.gig);
    });

    test('publishing a gig adds it to the feed and band gigs', () async {
      final app = await _demoApp();
      app.setGfName('Test Show');
      app.setGfDate('Fri Aug 14');
      app.setGfVenue('v1');
      expect(app.canPublishGig, isTrue);
      await app.publishGig();
      await pumpEventQueue();
      expect(app.allGigs.last.title, 'Test Show');
      expect(app.allGigs.last.lineup, ['b1']);
      expect(app.current.screen, Screen.gigMgr);
    });

    test('band creation switches to band view as admin', () async {
      final app = await _demoApp();
      app.startBandCreate();
      app.setNbName('Static Bloom Two');
      app.nbNext();
      app.addNbInvite('alex');
      await app.createBand();
      await pumpEventQueue();
      expect(app.bandId, 'nb1');
      expect(app.myBand!.initials, 'SB');
      expect(app.myBand!.followers, 2);
      expect(app.current.screen, Screen.bandDash);
    });

    test('failed RSVP mutation reverts its optimistic update', () async {
      final auth = FakeAuthService();
      final app = AppState(repository: _FailingRsvpRepository(), auth: auth);
      addTearDown(app.dispose);

      app.toggleRsvp('g1');
      expect(app.rsvps, contains('g1'));

      await pumpEventQueue();
      expect(app.rsvps, isNot(contains('g1')));
      expect(app.toast, 'Something broke — try again.');
    });
  });

  group('Gig date derivations', () {
    final now = DateTime(2026, 7, 28, 12);

    test('classifies tonight by calendar day', () {
      final sameDay = DateTime(2026, 7, 28, 1).millisecondsSinceEpoch;
      expect(Gig.whenFor(sameDay, now: now), GigWhen.tonight);
      expect(
        Gig.dateLineFor(sameDay, '8PM / 9PM', now: now),
        'TONIGHT · DOORS 8PM',
      );
    });

    test('classifies dates just under seven days away as this week', () {
      final startsAt = now
          .add(const Duration(days: 7))
          .subtract(const Duration(milliseconds: 1))
          .millisecondsSinceEpoch;
      expect(Gig.whenFor(startsAt, now: now), GigWhen.week);
    });

    test('classifies the exact seven-day boundary as later', () {
      final startsAt = now.add(const Duration(days: 7)).millisecondsSinceEpoch;
      expect(Gig.whenFor(startsAt, now: now), GigWhen.later);
    });

    test('classifies dates well beyond a week as later', () {
      final startsAt = now.add(const Duration(days: 30)).millisecondsSinceEpoch;
      expect(Gig.whenFor(startsAt, now: now), GigWhen.later);
    });

    test('formats a short date from its epoch timestamp', () {
      final startsAt = DateTime(2026, 7, 28).millisecondsSinceEpoch;
      expect(Gig.dateShortFor(startsAt), 'TUE JUL 28');
    });
  });

  test('parses a gigs:feed contract payload', () {
    final firstStartsAt = DateTime.now()
        .add(const Duration(days: 2))
        .millisecondsSinceEpoch;
    final secondStartsAt = DateTime.now()
        .add(const Duration(days: 9))
        .millisecondsSinceEpoch;
    final fixture = <String, dynamic>{
      'gigs': [
        {
          '_id': 'g1',
          'title': 'Basement Blowout',
          'venueId': 'v1',
          'price': 0,
          'startsAt': firstStartsAt,
          'doorsTime': '8PM / 9PM',
          'flyKey': 'paper',
          'lineup': ['b1', 'b2'],
          'genres': ['punk'],
          'desc': 'A loud basement show.',
          'ticketing': 'rsvp',
          'externalUrl': null,
          'cap': 'No cap',
          'goingCount': 43,
          'createdByBand': null,
        },
        {
          '_id': 'g2',
          'title': 'Record Release',
          'venueId': 'v2',
          'price': 12,
          'startsAt': secondStartsAt,
          'doorsTime': '7PM / 8PM',
          'flyKey': 'blue',
          'lineup': ['b2'],
          'genres': ['garage'],
          'desc': 'A release show.',
          'ticketing': 'external',
          'externalUrl': 'https://example.com/tickets',
          'cap': '200',
          'goingCount': 18,
          'createdByBand': 'b2',
        },
      ],
      'venues': [
        {
          '_id': 'v1',
          'name': 'The Foghorn Club',
          'area': 'Mission, SF',
          'addr': '2455 Harrison St, San Francisco',
          'distSF': '0.8 mi',
          'distOak': '6.3 mi',
          'lat': 37.7524,
          'lng': -122.4180,
        },
        {
          '_id': 'v2',
          'name': 'Nightcrawler Records',
          'area': 'Temescal, Oakland',
          'addr': '486 40th St, Oakland',
          'distSF': '6.1 mi',
          'distOak': '0.9 mi',
          'lat': 37.8180,
          'lng': -122.2690,
        },
      ],
      'bands': [
        {
          '_id': 'b1',
          'name': 'Foghorn Diet',
          'genres': ['garage', 'surf punk'],
          'area': 'Mission, SF',
          'colorHex': '#7B8FFF',
          'initials': 'FD',
          'followerCount': 486,
          'bio': 'Reverb-soaked garage punk.',
          'linkIg': '@foghorndiet',
          'linkBc': 'foghorndiet.bandcamp.com',
          'pastShows': [
            {'title': 'Casa Quake', 'meta': 'JUL 12'},
          ],
        },
        {
          '_id': 'b2',
          'name': 'Pigeon Court',
          'genres': ['post-punk'],
          'area': 'Temescal, Oakland',
          'colorHex': '#B9C4FF',
          'initials': 'PC',
          'followerCount': 1214,
          'bio': 'Wiry post-punk.',
          'linkIg': null,
          'linkBc': null,
          'pastShows': <Map<String, dynamic>>[],
        },
      ],
    };

    final snapshot = parseFeedSnapshot(fixture);

    expect(snapshot.gigs.map((gig) => gig.id), ['g1', 'g2']);
    expect(snapshot.venues['v2']!.name, 'Nightcrawler Records');
    expect(snapshot.bands['b1']!.past.single.meta, 'JUL 12');
    expect(snapshot.gigs.first.dateShort, Gig.dateShortFor(firstStartsAt));
    expect(
      snapshot.gigs.first.dateLine,
      Gig.dateLineFor(firstStartsAt, '8PM / 9PM'),
    );
    expect(snapshot.gigs.first.when, Gig.whenFor(firstStartsAt));
    expect(snapshot.gigs.last.tix, Ticketing.external);
  });
}

Future<AppState> _demoApp() async {
  final auth = FakeAuthService();
  final app = AppState(
    repository: DemoRepository(auth: auth),
    auth: auth,
  );
  addTearDown(app.dispose);
  await pumpEventQueue();
  return app;
}

class _FailingRsvpRepository implements EarplugRepository {
  @override
  Stream<FeedSnapshot> feed() => const Stream.empty();

  @override
  Stream<Interactions> myInteractions() => const Stream.empty();

  @override
  Stream<List<BandMembership>> myBands() => const Stream.empty();

  @override
  Future<List<VideoClip>> videosFor(String bandId) async => const [];

  @override
  Future<Band?> band(String bandId) async => null;

  @override
  Future<List<Band>> searchBands(String q) async => const [];

  @override
  Future<void> toggleRsvp(String gigId) =>
      Future<void>.error(StateError('RSVP failed'));

  @override
  Future<void> toggleFollow(String bandId) async {}

  @override
  Future<void> toggleSave(String gigId) async {}

  @override
  Future<void> setGenres(List<String> genres) async {}

  @override
  Future<void> ensureUser({String? name}) async {}

  @override
  Future<String> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required List<String> inviteHandles,
  }) async => 'unused';

  @override
  Future<void> updateBandProfile({
    required String bandId,
    String? bio,
    String? linkIg,
    String? linkBc,
  }) async {}

  @override
  Future<String> publishGig({
    required String bandId,
    required String title,
    required int startsAt,
    required String doorsTime,
    required String venueId,
    required int price,
    required Ticketing ticketing,
    String? externalUrl,
    required String cap,
  }) async => 'unused';

  @override
  Future<void> pinVideo(String videoId) async {}

  @override
  Future<void> moveVideo(String videoId, String direction) async {}
}
