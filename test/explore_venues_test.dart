import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/harness.dart';

const _directoryOnlyVenue = Venue(
  id: 'v-derby',
  name: 'Derby Street House',
  area: 'South Berkeley',
  addr: '2863 Derby St, Berkeley',
  distSF: '10.2 mi',
  distOak: '4.8 mi',
  point: LatLng(37.8614, -122.2508),
);

void main() {
  testWidgets('browse lists a venue absent from the feed', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _DirectoryRepository(auth: auth),
      home: const Scaffold(body: ExploreScreen()),
    );

    expect(find.text('VENUES', skipOffstage: false), findsOne);
    expect(
      find.text(_directoryOnlyVenue.name.toUpperCase(), skipOffstage: false),
      findsOne,
    );
  });

  testWidgets('search finds a venue that has no gigs', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _DirectoryRepository(auth: auth),
      home: const Scaffold(body: ExploreScreen()),
    );

    harness.app.setQuery(_directoryOnlyVenue.name);
    await tester.pumpAndSettle();

    expect(find.text('VENUES'), findsOne);
    expect(find.text(_directoryOnlyVenue.name.toUpperCase()), findsOne);
    expect(find.text('No gigs found.'), findsOne);
  });

  testWidgets('an empty failed directory can be retried', (tester) async {
    final auth = FakeAuthService();
    final repository = _RetryDirectoryRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: ExploreScreen()),
    );

    expect(find.text("Couldn't load venues.", skipOffstage: false), findsOne);
    final retry = find.text('RETRY', skipOffstage: false);
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    await tester.scrollUntilVisible(
      find.text(_directoryOnlyVenue.name.toUpperCase()),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(_directoryOnlyVenue.name.toUpperCase(), skipOffstage: false),
      findsOne,
    );
    expect(
      find.text("Couldn't load venues.", skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('a failed directory never blanks feed venues', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _FeedVenueDirectoryFailureRepository(auth: auth),
      home: const Scaffold(body: ExploreScreen()),
    );

    expect(
      find.text(DemoData.venues['v1']!.name.toUpperCase(), skipOffstage: false),
      findsOne,
    );
    expect(
      find.text("Couldn't load venues.", skipOffstage: false),
      findsNothing,
    );
  });
}

class _DirectoryRepository extends DemoRepository {
  _DirectoryRepository({required super.auth});

  @override
  Future<List<Venue>> venues() async => [
    ...DemoData.venues.values,
    _directoryOnlyVenue,
  ];
}

class _RetryDirectoryRepository extends DemoRepository {
  _RetryDirectoryRepository({required super.auth});

  int calls = 0;

  @override
  Stream<FeedSnapshot> feed() =>
      Stream.value(const FeedSnapshot(gigs: [], venues: {}, bands: {}));

  @override
  Future<List<Venue>> venues() async {
    calls++;
    if (calls == 1) throw Exception('venue directory failed');
    return const [_directoryOnlyVenue];
  }
}

class _FeedVenueDirectoryFailureRepository extends DemoRepository {
  _FeedVenueDirectoryFailureRepository({required super.auth});

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: const [],
      venues: {'v1': DemoData.venues['v1']!},
      bands: const {},
    ),
  );

  @override
  Future<List<Venue>> venues() async =>
      throw Exception('venue directory failed');
}
