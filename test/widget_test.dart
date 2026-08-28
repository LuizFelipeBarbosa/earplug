import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/convex_repository.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart' show Color, TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('AppState', () {
    test('starts on home feed with all demo gigs', () async {
      final app = await _demoApp();
      expect(app.current.screen, Screen.home);
      expect(app.feed.length, 7);
    });

    test('venue directory merges into one sorted, resolvable list', () async {
      final repository = _DirectoryMergeRepository(auth: FakeAuthService());
      final app = await _demoApp(repository: repository);
      final venues = app.venues;
      final ids = venues.map((venue) => venue.id).toList();
      final names = venues.map((venue) => venue.name).toList();
      final sortedNames = List<String>.of(names)..sort();

      expect(ids, contains(_extraVenue.id));
      expect(ids.toSet(), hasLength(ids.length));
      expect(names, orderedEquals(sortedNames));
      expect(app.venue(_extraVenue.id).name, _extraVenue.name);
    });

    test('realtime feed venue wins a directory id conflict', () async {
      final repository = _ConflictingVenueRepository(auth: FakeAuthService());
      final app = await _demoApp(repository: repository);
      final feedVenue = DemoData.venues['v1']!;

      expect(app.venue('v1').name, feedVenue.name);
      expect(
        app.venues.singleWhere((venue) => venue.id == 'v1').name,
        feedVenue.name,
      );
    });

    test('a failed venue directory leaves feed venues intact', () async {
      final repository = _FailedVenueRepository(auth: FakeAuthService());
      final app = await _demoApp(repository: repository);

      expect(app.venueStatus, DataStatus.error);
      expect(app.venueError, isNotNull);
      expect(
        app.venues.map((venue) => venue.id),
        containsAll(DemoData.venues.keys),
      );
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
      await app.finishAuth();
      expect(app.rsvps, contains('g1'));
      expect(app.current.screen, Screen.gig);
    });

    test('publishing a gig adds it to the feed and band gigs', () async {
      final app = await _demoApp();
      app.startGigCreate();
      app.setGfName('Test Show');
      app.setGfDate(DateTime(2026, 8, 14));
      app.setGfDoors(const TimeOfDay(hour: 21, minute: 30));
      app.setGfVenue('v1');
      app.setGfFly('riso');
      expect(app.canPublishGig, isTrue);
      expect(app.gigMissing, isEmpty);

      await app.publishGig();
      await pumpEventQueue();
      final published = app.allGigs.last;
      expect(published.title, 'Test Show');
      expect(published.lineup, ['b1']);
      expect(published.time, '9:30PM / 9PM');
      expect(published.flyKey, 'riso');
      // The form stays put and shows the published flyer.
      expect(app.gfPublished, isTrue);
      expect(app.gfProject?.status, GigProjectStatus.published);
      expect(app.current.screen, Screen.gigCreate);

      app.closeGigCreate();
      expect(app.current.screen, Screen.gigMgr);
      expect(app.gfName, 'Test Show');
      await pumpEventQueue();
    });

    test('gig form reports what is still missing', () async {
      final app = await _demoApp();
      app.startGigCreate();
      expect(app.gigMissing, ['a name', 'a date', 'a venue']);

      app.setGfName('Test Show');
      app.setGfVenue('v1');
      expect(app.gigMissing, ['a date']);
      expect(app.canPublishGig, isFalse);

      // Publishing while incomplete only nudges — nothing is written.
      await app.publishGig();
      expect(app.gfPublished, isFalse);
      expect(app.toast, 'Add a date first.');

      // Tapping the selected day again clears it.
      final date = DateTime(2026, 8, 15);
      app.setGfDate(date);
      expect(app.gfDateLabel, 'Sat Aug 15');
      app.setGfDate(date);
      expect(app.gfDate, isNull);
    });

    test('gig URL and custom flyer overlay handle edge cases', () async {
      final app = await _demoApp();
      expect(app.gigUrl, 'earplug.dev/g/your-gig');

      app.setGfName('!!!');
      expect(app.gigUrl, 'earplug.dev/g/your-gig');
      app.setGfName('Riptide Release');
      expect(app.gigUrl, 'earplug.dev/g/riptide-release');

      app.setGfFly('custom');
      app.toggleGfOverlay();
      expect(app.gfShowOverlay, isFalse);
      app.toggleGfOverlay();
      expect(app.gfShowOverlay, isTrue);
    });

    test('band creation makes you admin of the new band', () async {
      final app = await _demoApp();
      app.startBandCreate();
      app.setNbName('Static Bloom Two');

      // Genres and a home base gate the create; the button explains instead.
      await app.createBand();
      expect(app.nbCreated, isFalse);
      expect(app.toast, 'Add a genre + a home base first. Tap any line.');

      app.toggleNbGenre('punk');
      app.setNbArea('Berkeley');
      await app.createBand();
      await pumpEventQueue();
      expect(app.nbCreated, isTrue);
      expect(app.bandId, 'nb1');
      expect(app.myBand!.initials, 'SB');
      // Only accepted memberships count; legacy handle-shaped drafts do not.
      expect(app.myBand!.followers, 1);
      expect(app.myBand!.area, 'Berkeley');
      expect(app.nbShareSlug, 'static-bloom-two');

      app.postFirstGig();
      expect(app.current.screen, Screen.gigCreate);
    });

    test(
      'rapid create taps and keep-editing never duplicate the band',
      () async {
        final app = await _demoApp();
        app.startBandCreate();
        app.setNbName('Static Bloom Two');
        app.toggleNbGenre('punk');
        app.setNbArea('Berkeley');
        final bandsBefore = app.myBands.length;

        // A double tap fires createBand twice; only one band may land.
        await Future.wait([app.createBand(), app.createBand()]);
        await pumpEventQueue();
        expect(app.myBands.length, bandsBefore + 1);
        final createdId = app.bandId;

        // KEEP EDITING → rename → save updates the same record.
        app.editCreatedBand();
        expect(app.nbEditingCreated, isTrue);
        app.setNbName('Static Gloom');
        await app.createBand();
        await pumpEventQueue();
        expect(app.myBands.length, bandsBefore + 1);
        expect(app.bandId, createdId);
        expect(app.band(createdId)!.name, 'Static Gloom');
        expect(app.band(createdId)!.initials, 'SG');
        // The shared link survives the rename.
        expect(app.nbShareSlug, 'static-bloom-two');

        // A fresh band reusing a taken name gets its own slug.
        app.makeAnotherBand();
        app.setNbName('Static Gloom');
        app.toggleNbGenre('punk');
        app.setNbArea('Berkeley');
        await app.createBand();
        await pumpEventQueue();
        expect(app.myBands.length, bandsBefore + 2);
        expect(app.nbShareSlug, 'static-gloom-2');
      },
    );

    test('a failed create leaves the form open and says so', () async {
      final app = AppState(
        repository: _GatedCreateRepository()..fail = true,
        auth: FakeAuthService(),
      );
      addTearDown(app.dispose);
      _fillBandForm(app);

      await app.createBand();
      await pumpEventQueue();

      expect(app.nbCreated, isFalse);
      expect(app.toast, 'Something broke. Try again.');
      // No half-created band to save onto, so a retry creates rather than
      // updates — and the bar is usable again rather than stuck pending.
      expect(app.nbEditingCreated, isFalse);
      expect(app.nbSaving, isFalse);
    });

    test('an in-flight create is visible and blocks a second one', () async {
      final repository = _GatedCreateRepository();
      final app = AppState(repository: repository, auth: FakeAuthService());
      addTearDown(app.dispose);
      _fillBandForm(app);

      final inFlight = app.createBand();
      expect(app.nbSaving, isTrue); // the bar can show its pending state
      expect(repository.createCalls, 1);

      // A second tap while pending does nothing at all.
      await app.createBand();
      expect(repository.createCalls, 1);
      expect(app.nbCreated, isFalse);

      repository.gate.complete();
      await inFlight;
      expect(app.nbSaving, isFalse);
      expect(app.nbCreated, isTrue);
    });

    test('failed RSVP mutation reverts its optimistic update', () async {
      final auth = FakeAuthService();
      final app = AppState(repository: _FailingRsvpRepository(), auth: auth);
      addTearDown(app.dispose);

      app.toggleRsvp('g1');
      expect(app.rsvps, contains('g1'));

      await pumpEventQueue();
      expect(app.rsvps, isNot(contains('g1')));
      expect(app.toast, 'Something broke. Try again.');
    });

    test('profile fields save together in one atomic update', () async {
      final repository = _CountingProfileRepository(auth: FakeAuthService());
      final app = await _demoApp(repository: repository);
      app.switchToBand('b1');
      final band = app.myBand!;

      await app.saveBandProfile(
        BandProfileUpdate(
          bandId: band.id,
          name: band.name,
          genres: band.genres,
          area: band.area,
          bio: 'We play',
          linkIg: '@weplay',
          linkBc: '',
          linkYt: '',
          credits: 'Recorded by Mara',
        ),
      );

      expect(repository.profileCalls, 1);
      expect(repository.lastBio, 'We play');
      expect(app.bioFor('b1'), 'We play');
    });

    test('single-word band names cache the backend initials', () async {
      final app = await _demoApp();
      app.switchToBand('b1');
      final band = app.myBand!;

      await app.saveBandProfile(
        BandProfileUpdate(
          bandId: band.id,
          name: 'SOBO',
          genres: band.genres,
          area: band.area,
          bio: band.bio,
          linkIg: band.linkIg ?? '',
          linkBc: band.linkBc ?? '',
          linkYt: band.linkYt ?? '',
          credits: band.credits ?? '',
        ),
      );

      expect(app.myBand!.initials, 'SO');
    });

    test('a failed atomic profile save leaves server data visible', () async {
      final repository = _CountingProfileRepository(auth: FakeAuthService())
        ..fail = true;
      final app = await _demoApp(repository: repository);
      app.switchToBand('b1');
      final band = app.myBand!;
      final serverBio = band.bio;

      await expectLater(
        app.saveBandProfile(
          BandProfileUpdate(
            bandId: band.id,
            name: band.name,
            genres: band.genres,
            area: band.area,
            bio: 'never lands',
            linkIg: '',
            linkBc: '',
            linkYt: '',
            credits: '',
          ),
        ),
        throwsException,
      );
      expect(app.bioFor('b1'), serverBio);
    });

    test('starting a band resumes creation after authentication', () async {
      final app = await _demoApp();

      app.requestStartBand();
      expect(app.current.screen, Screen.auth);
      expect(app.pending?.kind, PendingKind.band);

      await app.login();
      await app.finishAuth();

      expect(app.current.screen, Screen.bandCreate);
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
    final nextStartsAt = DateTime.now()
        .add(const Duration(days: 10))
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
      'nextStartsAt': nextStartsAt,
    };

    final snapshot = parseFeedSnapshot(fixture);

    expect(snapshot.gigs.map((gig) => gig.id), ['g1', 'g2']);
    expect(snapshot.venues['v2']!.name, 'Nightcrawler Records');
    expect(snapshot.bands['b1']!.past.single.meta, 'JUL 12');
    expect(snapshot.gigs.first.dateShort, Gig.dateShortFor(firstStartsAt));
    expect(
      snapshot.gigs.first.startsAt,
      DateTime.fromMillisecondsSinceEpoch(firstStartsAt),
    );
    expect(
      snapshot.gigs.first.dateLine,
      Gig.dateLineFor(firstStartsAt, '8PM / 9PM'),
    );
    expect(snapshot.gigs.first.when, Gig.whenFor(firstStartsAt));
    expect(snapshot.gigs.last.tix, Ticketing.external);
    expect(
      snapshot.nextStartsAt,
      DateTime.fromMillisecondsSinceEpoch(nextStartsAt),
    );
  });
}

Future<AppState> _demoApp({DemoRepository? repository}) async {
  final auth = FakeAuthService();
  final app = AppState(
    repository: repository ?? DemoRepository(auth: auth),
    auth: auth,
  );
  addTearDown(app.dispose);
  await pumpEventQueue();
  return app;
}

const _extraVenue = Venue(
  id: 'v-extra',
  name: 'Derby Street House',
  area: 'South Berkeley',
  addr: '2863 Derby St, Berkeley',
  distSF: '10.2 mi',
  distOak: '4.8 mi',
  point: LatLng(37.8614, -122.2508),
);

class _DirectoryMergeRepository extends DemoRepository {
  _DirectoryMergeRepository({required super.auth});

  @override
  Future<List<Venue>> venues() async => [
    ...DemoData.venues.values,
    _extraVenue,
  ];
}

class _ConflictingVenueRepository extends DemoRepository {
  _ConflictingVenueRepository({required super.auth});

  static const _directoryVersion = Venue(
    id: 'v1',
    name: 'Stale Directory Name',
    area: 'Mission, SF',
    addr: '2455 Harrison St, San Francisco',
    distSF: '0.8 mi',
    distOak: '6.3 mi',
    point: LatLng(37.7524, -122.4180),
  );

  @override
  Future<List<Venue>> venues() async => [
    for (final venue in DemoData.venues.values)
      if (venue.id == 'v1') _directoryVersion else venue,
  ];
}

class _FailedVenueRepository extends DemoRepository {
  _FailedVenueRepository({required super.auth});

  @override
  Future<List<Venue>> venues() async => throw Exception('venues failed');
}

/// Counts atomic profile writes and can fail them on request.
class _CountingProfileRepository extends DemoRepository {
  _CountingProfileRepository({required super.auth});

  int profileCalls = 0;
  String? lastBio;
  bool fail = false;

  @override
  Future<void> updateBandProfile(BandProfileUpdate update) async {
    profileCalls++;
    if (fail) throw Exception('updateBandProfile failed');
    lastBio = update.bio;
    return super.updateBandProfile(update);
  }
}

/// The minimum the create bar needs before it will fire.
void _fillBandForm(AppState app) {
  app.startBandCreate();
  app.setNbName('Static Bloom');
  app.toggleNbGenre('punk');
  app.setNbArea('Berkeley');
}

/// A create that only finishes when the test says so — or fails, on request.
/// `Exception`, not `Error`, because that is what ConvexService surfaces.
class _GatedCreateRepository extends _FailingRsvpRepository {
  final gate = Completer<void>();
  bool fail = false;
  int createCalls = 0;

  @override
  Future<({Band band, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required String area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
    String? credits,
  }) async {
    createCalls++;
    if (fail) throw Exception('createBand failed');
    await gate.future;
    return (
      band: _bandFixture(id: 'nb1', name: name, genres: genres, area: area),
      slug: 'static-bloom',
    );
  }
}

class _FailingRsvpRepository implements EarplugRepository {
  @override
  Future<void> refreshAuth() async {}

  @override
  Future<UserProfile?> me() async => null;

  @override
  Stream<FeedSnapshot> feed() => const Stream.empty();

  @override
  Stream<Gig?> publicGig(String gigId) => const Stream.empty();

  @override
  Stream<List<Gig>> upcomingGigsForBand(String bandId) => const Stream.empty();

  @override
  Stream<Interactions> myInteractions() => const Stream.empty();

  @override
  Stream<List<BandMembership>> myBands() => const Stream.empty();

  @override
  Future<List<BandMedia>> mediaFor(String bandId) async => const [];

  @override
  Future<String> generateMediaUploadUrl(String bandId) async => 'unused';

  @override
  Future<String> addBandMedia({
    required String bandId,
    required MediaKind kind,
    required String storageId,
    required String title,
    String? caption,
    int? lengthSec,
  }) async => 'unused';

  @override
  Future<void> deleteBandMedia(String mediaId) async {}

  @override
  Future<void> pinBandMedia(String mediaId) async {}

  @override
  Future<void> moveBandMedia(String mediaId, String direction) async {}

  @override
  Future<void> setBandPhoto({
    required String bandId,
    required String mediaId,
  }) async {}

  @override
  Future<void> clearBandPhoto(String bandId) async {}

  @override
  Future<List<FanHistoryItem>> history() async => const [];

  @override
  Future<BandHistory> bandHistory(String bandId) async => BandHistory.empty;

  @override
  Future<BandRecap> bandRecap(String bandId) async => BandRecap.empty;

  @override
  Future<List<Venue>> venues() async => const [];

  @override
  Future<VenueDetail?> venueDetail(String venueId) async => null;

  @override
  Future<Band?> band(String bandId) async => null;

  @override
  Future<List<Band>> searchBands(String q) async => const [];

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async =>
      const BandPage(items: [], continueCursor: null, isDone: true);

  @override
  Future<void> toggleRsvp(String gigId) =>
      Future<void>.error(StateError('RSVP failed'));

  @override
  Future<void> toggleFollow(String bandId) async {}

  @override
  Future<void> toggleSave(String gigId) async {}

  @override
  Future<void> ensureRsvp(String gigId) async {}

  @override
  Future<void> ensureFollow(String bandId) async {}

  @override
  Future<void> ensureSave(String gigId) async {}

  @override
  Future<void> setGenres(List<String> genres) async {}

  @override
  Future<void> updateFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  }) async {}

  @override
  Future<String> generateAvatarUploadUrl() async => 'unused';

  @override
  Future<void> setAvatar(String storageId) async {}

  @override
  Future<void> clearAvatar() async {}

  @override
  Future<void> setProfileTutorialCompleted(bool completed) async {}

  @override
  Future<void> updateFanOnboarding({
    FanCity? preferredCity,
    FanGenreChoice? genreChoice,
    bool? collapsed,
    List<String>? genres,
  }) async {}

  @override
  Future<void> ensureUser({String? name}) async {}

  @override
  Future<void> deleteCurrentUser() async {}

  @override
  Future<({Band band, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required String area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
    String? credits,
  }) async => (
    band: _bandFixture(id: 'unused', name: name, genres: genres, area: area),
    slug: 'unused',
  );

  @override
  Future<void> updateBandProfile(BandProfileUpdate update) async {}

  @override
  Future<BandProfileDetails> bandProfileDetails(String bandId) async =>
      BandProfileDetails.empty;

  @override
  Future<BandSetupStatus> bandSetupStatus(String bandId) async =>
      const BandSetupStatus(
        profileComplete: false,
        profileImageAdded: false,
        musicAdded: false,
        socialLinksAdded: false,
        firstGigCreated: false,
        membersInvited: false,
        publicProfilePreviewed: false,
      );

  @override
  Future<BandDiscoveryReadiness> bandDiscoveryReadiness(
    String bandId, {
    DateTime? now,
  }) async => const BandDiscoveryReadiness(
    profileComplete: false,
    profileImageReady: false,
    clipReady: false,
    publishedShowReady: false,
    venuePosterReady: false,
    publishedRevisionCurrent: false,
  );

  @override
  Future<void> markBandPreviewed(String bandId) async {}

  @override
  Future<BandInvite?> bandInvite(String bandId) async => null;

  @override
  Future<BandInvite> createBandInvite(String bandId) =>
      throw UnimplementedError();

  @override
  Future<BandInvite> rotateBandInvite(String bandId) =>
      throw UnimplementedError();

  @override
  Future<void> revokeBandInvite(String bandId) async {}

  @override
  Future<BandInviteResolution?> resolveBandInvite(String token) async => null;

  @override
  Future<BandInviteAcceptance> acceptBandInvite(String token) =>
      throw UnimplementedError();

  @override
  Future<PerformerInviteResolution?> resolvePerformerInvite(
    String token,
  ) async => null;

  @override
  Future<String> claimPerformerInvite({
    required String token,
    required String bandId,
  }) => throw UnimplementedError();

  @override
  Future<List<GigProject>> manageGigs(String bandId) async => const [];

  @override
  Future<GigProject> createGigDraft(String bandId) =>
      throw UnimplementedError();

  @override
  Future<GigProject> getGigProject(String projectId) =>
      throw UnimplementedError();

  @override
  Future<int> saveGigDraft({
    required String projectId,
    required int revision,
    required String? title,
    required DateTime? doorsAt,
    required DateTime? startsAt,
    required String? venueId,
    required int price,
    required String flyKey,
    required String? flyStorageId,
    required bool overlay,
    required String desc,
    required Ticketing ticketing,
    required AgeRequirement ageRequirement,
    required String? externalUrl,
    required String cap,
  }) => throw UnimplementedError();

  @override
  Future<GigProject> addGigPerformer({
    required String projectId,
    required GigPerformerKind kind,
    required GigPerformerRole role,
    String? name,
    String? bandId,
  }) => throw UnimplementedError();

  @override
  Future<GigProject> updateGigPerformer({
    required String performerId,
    String? name,
    GigPerformerRole? role,
  }) => throw UnimplementedError();

  @override
  Future<GigProject> removeGigPerformer(String performerId) =>
      throw UnimplementedError();

  @override
  Future<GigProject> reorderGigPerformers(
    String projectId,
    List<String> performerIds,
  ) => throw UnimplementedError();

  @override
  Future<String> publishGigDraft(String projectId) =>
      throw UnimplementedError();

  @override
  Future<GigProject> duplicateGig(String projectId) =>
      throw UnimplementedError();

  @override
  Future<void> unpublishGig(String projectId) async {}

  @override
  Future<void> cancelGig(String projectId) async {}

  @override
  Future<void> deleteGig(String projectId) async {}

  @override
  Future<String> publishGig({
    required String bandId,
    required String title,
    required int startsAt,
    required String doorsTime,
    required String venueId,
    required int price,
    required String flyKey,
    String? flyStorageId,
    required Ticketing ticketing,
    required AgeRequirement ageRequirement,
    String? externalUrl,
    required String cap,
  }) async => 'unused';
}

Band _bandFixture({
  required String id,
  required String name,
  required List<String> genres,
  String? area,
}) => Band(
  id: id,
  name: name,
  genres: genres,
  area: area ?? 'San Francisco',
  color: const Color(0xFF222222),
  initials: name
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0])
      .take(2)
      .join()
      .toUpperCase(),
  followers: 0,
  bio: '',
);
