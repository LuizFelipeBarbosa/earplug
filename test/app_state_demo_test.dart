import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fixtures.dart';

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
      app.venues;
      await pumpEventQueue();
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

      app.venues;
      await pumpEventQueue();
      expect(app.venue('v1').name, feedVenue.name);
      expect(
        app.venues.singleWhere((venue) => venue.id == 'v1').name,
        feedVenue.name,
      );
    });

    test('a failed venue directory leaves feed venues intact', () async {
      final repository = _FailedVenueRepository(auth: FakeAuthService());
      final app = await _demoApp(repository: repository);

      app.venues;
      await pumpEventQueue();
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
      expect(app.gigUrl, 'earplug.app/g/your-gig');

      app.setGfName('!!!');
      expect(app.gigUrl, 'earplug.app/g/your-gig');
      app.setGfName('Riptide Release');
      expect(app.gigUrl, 'earplug.app/g/riptide-release');

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
      final auth = FakeAuthService();
      final app = AppState.demo(
        repository: _GatedCreateRepository(auth: auth)..fail = true,
        auth: auth,
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
      final auth = FakeAuthService();
      final repository = _GatedCreateRepository(auth: auth);
      final app = AppState.demo(repository: repository, auth: auth);
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
      final app = AppState.demo(
        repository: _FailingRsvpRepository(auth: auth),
        auth: auth,
      );
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
}

Future<AppState> _demoApp({DemoRepository? repository}) async {
  final auth = FakeAuthService();
  final app = AppState.demo(
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
class _GatedCreateRepository extends DemoRepository {
  _GatedCreateRepository({required super.auth});

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
      band: bandFixture(id: 'nb1', name: name, genres: genres, area: area),
      slug: 'static-bloom',
    );
  }
}

class _FailingRsvpRepository extends DemoRepository {
  _FailingRsvpRepository({required super.auth});

  @override
  Future<void> toggleRsvp(String gigId, {bool? on}) =>
      Future<void>.error(StateError('RSVP failed'));
}
