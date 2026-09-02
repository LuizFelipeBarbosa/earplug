import 'dart:async';

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_profile.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('live history replaces legacy past-show strings', (tester) async {
    final auth = FakeAuthService();
    final history = BandHistory(
      gigs: [DemoData.gigs[1], DemoData.gigs[0]],
      venues: {'v1': DemoData.venues['v1']!, 'v3': DemoData.venues['v3']!},
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: _HistoryRepository(auth: auth, stagedHistory: history),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await tester.scrollUntilVisible(
      find.text('PAST GIGS · 2 PLAYED'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PAST GIGS · 2 PLAYED', skipOffstage: false), findsOne);
    expect(
      find.textContaining(
        'Riptide Release Show · The Foghorn Club',
        skipOffstage: false,
      ),
      findsOne,
    );
    expect(
      find.textContaining('Basement Blowout · Casa Quake', skipOffstage: false),
      findsOne,
    );
    expect(
      find.text('Riptide warmup — Casa Quake', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('demo history falls back to legacy past shows', (tester) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await tester.scrollUntilVisible(
      find.text('PAST GIGS · 4 PLAYED'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PAST GIGS · 4 PLAYED', skipOffstage: false), findsOne);
    for (final show in DemoData.bands['b1']!.past) {
      await tester.scrollUntilVisible(
        find.textContaining(show.title),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining(show.title, skipOffstage: false), findsOne);
    }
  });

  testWidgets('empty history without legacy rows is a quiet normal state', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _BareBandRepository(auth: auth),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await _scrollToPastGigs(tester);
    expect(find.text('No past shows yet.', skipOffstage: false), findsOne);
    expect(find.text('PAST GIGS', skipOffstage: false), findsOne);
    expect(find.text('RETRY', skipOffstage: false), findsNothing);
  });

  testWidgets('history failure waits for RETRY and then renders', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _BareBandRepository(
      auth: auth,
      failuresRemaining: 1,
      stagedHistory: BandHistory(
        gigs: [DemoData.gigs[0]],
        venues: {'v3': DemoData.venues['v3']!},
      ),
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await _scrollToPastGigs(tester);
    expect(
      find.text("Couldn't load past shows.", skipOffstage: false),
      findsOne,
    );
    expect(repository.calls, 1);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repository.calls, 1);

    final retry = find.text('RETRY', skipOffstage: false);
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    await tester.scrollUntilVisible(
      find.textContaining('Basement Blowout · Casa Quake'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Basement Blowout · Casa Quake', skipOffstage: false),
      findsOne,
    );
    expect(
      find.text("Couldn't load past shows.", skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('history shows loading while its first request is gated', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final gate = Completer<void>();
    final repository = _BareBandRepository(auth: auth, gate: gate);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
      pumpFor: Duration.zero,
    );
    await tester.pump();

    await _scrollToPastGigs(tester);
    expect(find.text('Loading past shows…', skipOffstage: false), findsOne);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('No past shows yet.', skipOffstage: false), findsOne);
  });
}

Future<void> _scrollToPastGigs(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('PAST GIGS'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

class _HistoryRepository extends DemoRepository {
  _HistoryRepository({
    required super.auth,
    this.stagedHistory = BandHistory.empty,
  });

  final BandHistory stagedHistory;
  int calls = 0;

  @override
  Future<BandHistory> bandHistory(String bandId) async {
    calls++;
    return stagedHistory;
  }
}

class _BareBandRepository extends DemoRepository {
  _BareBandRepository({
    required super.auth,
    this.stagedHistory = BandHistory.empty,
    this.failuresRemaining = 0,
    this.gate,
  });

  final BandHistory stagedHistory;
  int failuresRemaining;
  final Completer<void>? gate;
  int calls = 0;

  static final _bareBand = Band(
    id: DemoData.bands['b1']!.id,
    name: DemoData.bands['b1']!.name,
    genres: DemoData.bands['b1']!.genres,
    area: DemoData.bands['b1']!.area,
    color: DemoData.bands['b1']!.color,
    initials: DemoData.bands['b1']!.initials,
    followers: DemoData.bands['b1']!.followers,
    bio: DemoData.bands['b1']!.bio,
    linkIg: DemoData.bands['b1']!.linkIg,
    linkBc: DemoData.bands['b1']!.linkBc,
    heroUrl: DemoData.bands['b1']!.heroUrl,
    past: const [],
  );

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(gigs: const [], venues: const {}, bands: {'b1': _bareBand}),
  );

  @override
  Stream<List<BandMembership>> myBands() => const Stream.empty();

  @override
  Future<List<Band>> searchBands(String q) async => [_bareBand];

  @override
  Future<BandHistory> bandHistory(String bandId) async {
    calls++;
    await gate?.future;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw Exception('band history failed');
    }
    return stagedHistory;
  }
}
