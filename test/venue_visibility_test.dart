import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';

void main() {
  late _VenueVisibilityRepository repository;
  late AppState app;

  setUp(() {
    final auth = FakeAuthService();
    repository = _VenueVisibilityRepository(auth: auth);
    app = AppState.demo(repository: repository, auth: auth);
  });

  tearDown(() async {
    app.dispose();
    await flushAsyncWork();
    expect(repository.activeDirectorySubscriptions, 0);
    await repository.close();
  });

  test(
    'directory-only venues disappear and return without a feed update',
    () async {
      repository.emitFeed(visible: false);
      app.ensureVenueDirectory();
      await flushAsyncWork();
      expect(app.knownVenue(repository.venue.id), isNotNull);

      repository.emitDirectory([]);
      await flushAsyncWork();
      expect(app.venues, isEmpty);
      expect(app.knownVenue(repository.venue.id), isNull);

      repository.emitDirectory([repository.venue]);
      await flushAsyncWork();
      expect(app.knownVenue(repository.venue.id), isNotNull);
      expect(repository.directoryCalls, 1);
    },
  );

  test('a venue with no upcoming gigs remains in the directory', () async {
    repository.emitFeed(visible: true);
    app.ensureVenueDirectory();
    await flushAsyncWork();

    repository.emitFeed(visible: false);
    await flushAsyncWork();
    expect(app.feed, isEmpty);
    expect(app.venues.single.id, repository.venue.id);
    expect(repository.directoryCalls, 1);
  });

  test(
    'a capped directory does not hide venues supplied by the feed',
    () async {
      repository.directoryRows = [];
      repository.emitFeed(visible: true);
      app.ensureVenueDirectory();
      await flushAsyncWork();

      expect(app.knownVenue(repository.venue.id), isNotNull);
      expect(app.venues.single.id, repository.venue.id);
    },
  );

  test(
    'a directory response pending before a detail miss cannot restore it',
    () async {
      final staleDirectory = Completer<List<Venue>>();
      repository.nextDirectoryLoad = staleDirectory;
      app.ensureVenueDirectory();
      await flushAsyncWork();

      repository.directoryRows = [];
      expect(app.venueDetail(repository.venue.id), isNull);
      await flushAsyncWork();
      expect(repository.directoryCalls, 2);
      expect(app.venueDetailMissing(repository.venue.id), isTrue);
      expect(app.venues, isEmpty);

      staleDirectory.complete([repository.venue]);
      await flushAsyncWork();
      expect(app.knownVenue(repository.venue.id), isNull);
      expect(app.venues, isEmpty);

      repository.emitDirectory([repository.venue]);
      await flushAsyncWork();
      expect(app.venueDetailMissing(repository.venue.id), isFalse);
      expect(app.knownVenue(repository.venue.id), isNotNull);
    },
  );

  test('directory removal invalidates an outstanding venue detail', () async {
    app.ensureVenueDirectory();
    await flushAsyncWork();
    final staleDetail = Completer<VenueDetail?>();
    repository.nextDetailLoad = staleDetail;
    expect(app.venueDetail(repository.venue.id), isNull);
    await flushAsyncWork();

    repository.emitDirectory([]);
    await flushAsyncWork();
    staleDetail.complete(repository.detail);
    await flushAsyncWork();
    expect(app.knownVenue(repository.venue.id), isNull);
    expect(app.venues, isEmpty);
  });

  test(
    'an unavailable detail evicts a cached row and refreshes the stream',
    () async {
      app.ensureVenueDirectory();
      await flushAsyncWork();
      expect(app.knownVenue(repository.venue.id), isNotNull);

      repository.directoryRows = [];
      expect(app.venueDetail(repository.venue.id), isNull);
      await flushAsyncWork();
      expect(repository.directoryCalls, 2);
      expect(repository.activeDirectorySubscriptions, 1);
      expect(app.venueDetailMissing(repository.venue.id), isTrue);
      expect(app.knownVenue(repository.venue.id), isNull);
    },
  );

  test(
    'venue stream errors can be retried with one active subscription',
    () async {
      app.ensureVenueDirectory();
      await flushAsyncWork();
      repository.failDirectory();
      await flushAsyncWork();
      expect(app.venueStatus, DataStatus.error);

      app.retryVenues();
      await flushAsyncWork();
      expect(repository.directoryCalls, 2);
      expect(repository.activeDirectorySubscriptions, 1);
      expect(app.venueStatus, DataStatus.ready);
      expect(app.venueError, isNull);
    },
  );

  test('demo suspension and restoration update venue subscribers', () async {
    final auth = FakeAuthService();
    final demoRepository = DemoRepository(auth: auth);
    final demoApp = AppState.demo(repository: demoRepository, auth: auth);
    addTearDown(demoApp.dispose);
    demoApp.ensureVenueDirectory();
    await flushAsyncWork();
    final managedVenue = demoApp.venues.firstWhere(
      (venue) => venue.managedByOrganizationId == 'org1',
    );

    await demoRepository.setOrganizationSuspended(
      organizationId: 'org1',
      suspended: true,
    );
    await flushAsyncWork();
    expect(demoApp.knownVenue(managedVenue.id), isNull);

    await demoRepository.setOrganizationSuspended(
      organizationId: 'org1',
      suspended: false,
    );
    await flushAsyncWork();
    expect(demoApp.knownVenue(managedVenue.id), isNotNull);
  });
}

class _VenueVisibilityRepository extends DemoRepository {
  _VenueVisibilityRepository({required super.auth}) {
    directoryRows = [venue];
  }

  final _feed = StreamController<FeedSnapshot>.broadcast();
  final _directory = StreamController<List<Venue>>.broadcast();
  final gig = DemoData.gigs.firstWhere((gig) => gig.id == 'g2');
  Venue get venue => DemoData.venues[gig.venueId]!;
  VenueDetail get detail => VenueDetail(
    venue: venue,
    gigs: const [],
    bands: const {},
    truncated: false,
  );
  late List<Venue> directoryRows;
  Completer<List<Venue>>? nextDirectoryLoad;
  Completer<VenueDetail?>? nextDetailLoad;
  var directoryCalls = 0;
  var activeDirectorySubscriptions = 0;

  @override
  Stream<FeedSnapshot> feed() => _feed.stream;

  void emitFeed({required bool visible}) {
    _feed.add(
      FeedSnapshot(
        gigs: visible ? [gig] : [],
        venues: visible ? {venue.id: venue} : {},
        bands: DemoData.bands,
      ),
    );
  }

  void emitDirectory(List<Venue> venues) {
    directoryRows = venues;
    _directory.add(venues);
  }

  void failDirectory() =>
      _directory.addError(StateError('directory unavailable'));

  @override
  Future<List<Venue>> venues() async {
    final pending = nextDirectoryLoad;
    nextDirectoryLoad = null;
    return pending == null ? directoryRows : await pending.future;
  }

  @override
  Stream<List<Venue>> watchVenues() async* {
    directoryCalls++;
    activeDirectorySubscriptions++;
    try {
      yield await venues();
      yield* _directory.stream;
    } finally {
      activeDirectorySubscriptions--;
    }
  }

  @override
  Future<VenueDetail?> venueDetail(String venueId) async {
    final pending = nextDetailLoad;
    nextDetailLoad = null;
    if (pending != null) return pending.future;
    return directoryRows.any((venue) => venue.id == venueId) ? detail : null;
  }

  Future<void> close() async {
    await _feed.close();
    await _directory.close();
  }
}
