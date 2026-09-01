import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('new-fan setup collapses, resumes, syncs, and completes', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _ProfileRepository(
      auth: auth,
      onboarding: const FanOnboarding(
        preferredCity: null,
        genreChoice: FanGenreChoice.pending,
        collapsed: false,
      ),
    );
    final first = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: MyGigsScreen()),
    );
    tester.view.physicalSize = const Size(402, 1600);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fan-setup-expanded')), findsOne);
    await _tapVisible(tester, find.byKey(const Key('fan-city-oak')));
    await tester.pump();
    expect(first.app.city, 'oak');
    expect(repository.onboarding?.preferredCity, FanCity.oak);

    await _tapVisible(tester, find.byKey(const Key('fan-genres-open')));
    await tester.pump();
    expect(repository.onboarding?.genreChoice, FanGenreChoice.open);
    expect(repository.genres, isEmpty);

    await _tapVisible(tester, find.byKey(const Key('fan-setup-not-now')));
    await tester.pump();
    expect(first.app.fanOnboarding?.collapsed, isTrue);
    expect(repository.onboarding?.collapsed, isTrue);

    // A fresh AppState reads the same persisted profile and applies its city.
    final second = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: MyGigsScreen()),
    );
    expect(second.app.city, 'oak');
    tester.view.physicalSize = const Size(402, 1500);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fan-setup-collapsed')), findsOne);

    await _tapVisible(tester, find.byKey(const Key('fan-setup-collapsed')));
    await tester.pump();
    expect(find.byKey(const Key('fan-setup-expanded')), findsOne);
    expect(repository.onboarding?.collapsed, isFalse);

    second.app.requestSave('g1');
    await tester.pump();
    expect(second.app.saved, contains('g1'));
    expect(second.app.fanOnboardingComplete, isTrue);
    expect(find.byKey(const Key('fan-setup-expanded')), findsNothing);
    expect(find.byKey(const Key('fan-setup-collapsed')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('existing fans are not enrolled in setup', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(auth: auth, onboarding: null),
      home: const Scaffold(body: MyGigsScreen()),
    );

    expect(find.byKey(const Key('fan-setup-expanded')), findsNothing);
    expect(find.byKey(const Key('fan-setup-collapsed')), findsNothing);
  });

  testWidgets('zero-band navigation starts creation without profile entries', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _MembershipRepository(auth: auth, count: 0),
      home: const Scaffold(
        body: MyGigsScreen(),
        bottomNavigationBar: FanTabBar(),
      ),
    );

    expect(find.byKey(const Key('band-entry')), findsNothing);
    expect(find.byKey(const Key('create-band-from-profile')), findsNothing);
    expect(find.text('PLAY IN A BAND?'), findsNothing);
    expect(find.text('CREATE BAND'), findsOne);
    await tester.tap(find.text('CREATE BAND'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandCreate);
  });

  testWidgets('public navigation offers Create Band and preserves the intent', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(
        body: SizedBox.shrink(),
        bottomNavigationBar: FanTabBar(),
      ),
    );

    expect(find.text('CREATE BAND'), findsOne);
    await tester.tap(find.text('CREATE BAND'));
    await tester.pump();

    expect(harness.app.current.screen, Screen.auth);
    expect(harness.app.pending?.kind, PendingKind.band);
  });

  testWidgets('band navigation waits for authenticated memberships', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _DeferredMembershipRepository(auth: auth);
    addTearDown(repository.close);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(
        body: SizedBox.shrink(),
        bottomNavigationBar: FanTabBar(),
      ),
    );
    await harness.app.commitAuth();
    await tester.pump();

    expect(find.text('BANDS'), findsOne);
    expect(repository.hasMembershipListener, isTrue);
    await tester.tap(find.text('BANDS'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.home);

    repository.addMemberships([
      BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
    ]);
    await tester.pumpAndSettle();

    expect(harness.app.membershipsLoaded, isTrue);
    expect(harness.app.myBands, ['b1']);
    expect(find.text('SWITCH BAND'), findsOne);
    await tester.tap(find.text('SWITCH BAND'));
    await tester.pumpAndSettle();
    expect(find.text('MANAGE BAND'), findsOne);
    await tester.tap(find.text('FOGHORN DIET'));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bandDash);
    expect(harness.app.bandId, 'b1');

    await harness.app.signOut();
    await tester.pump();
    expect(harness.app.myBands, isEmpty);
    expect(harness.app.membershipsLoaded, isFalse);
    expect(find.text('CREATE BAND'), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('failed city onboarding restores current-location discovery', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _ProfileRepository(
      auth: auth,
      onboarding: const FanOnboarding(
        preferredCity: FanCity.sf,
        genreChoice: FanGenreChoice.pending,
        collapsed: false,
      ),
      failCityUpdates: true,
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: MyGigsScreen()),
    );
    final position = DemoData.venues['v1']!.point;
    harness.app.useCurrentPosition(position);
    harness.app.setDistanceFilter(5);

    harness.app.selectFanCity(FanCity.oak);
    await tester.pump();

    expect(harness.app.city, 'sf');
    expect(harness.app.discoveryLocation, DiscoveryLocation.current);
    expect(harness.app.currentPosition, position);
    expect(harness.app.fMaxDistanceMiles, 5);
    expect(harness.app.fanOnboarding?.preferredCity, FanCity.sf);
    expect(harness.app.toast, "Couldn't save your setup choices. Try again.");

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('one-band navigation opens the existing selector', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _MembershipRepository(auth: auth, count: 1),
      home: const Scaffold(
        body: MyGigsScreen(),
        bottomNavigationBar: FanTabBar(),
      ),
    );

    expect(find.text('SWITCH BAND'), findsOne);
    await tester.tap(find.text('SWITCH BAND'));
    await tester.pumpAndSettle();
    expect(find.text('MANAGE BAND'), findsOne);
    expect(find.text('Personal account'), findsOne);
    await tester.tap(find.text('FOGHORN DIET'));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bandDash);
    expect(harness.app.bandId, 'b1');
  });

  testWidgets('multi-band navigation opens the switcher', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: _MembershipRepository(auth: auth, count: 2),
      home: const Scaffold(
        body: MyGigsScreen(),
        bottomNavigationBar: FanTabBar(),
      ),
    );

    expect(find.text('SWITCH BAND'), findsOne);
    await tester.tap(find.text('SWITCH BAND'));
    await tester.pumpAndSettle();
    expect(find.text('SWITCH BAND'), findsWidgets);
    expect(find.text('PIGEON COURT'), findsWidgets);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

class _ProfileRepository extends DemoRepository {
  _ProfileRepository({
    required super.auth,
    required this.onboarding,
    this.failCityUpdates = false,
  });

  FanOnboarding? onboarding;
  List<String> genres = const [];
  final bool failCityUpdates;

  @override
  Stream<Interactions> myInteractions() => Stream.value(Interactions.empty);

  @override
  Future<UserProfile?> me() async => UserProfile(
    name: 'Avery Fan',
    email: 'avery@example.com',
    genres: genres,
    attendedCount: 0,
    createdAt: DateTime(2026, 8, 23),
    fanOnboarding: onboarding,
  );

  @override
  Future<void> setGenres(List<String> nextGenres) async {
    genres = List.of(nextGenres);
  }

  @override
  Future<void> updateFanOnboarding({
    FanCity? preferredCity,
    FanGenreChoice? genreChoice,
    bool? collapsed,
    List<String>? genres,
  }) async {
    if (failCityUpdates && preferredCity != null) {
      throw StateError('city update failed');
    }
    final current = onboarding;
    if (current == null) return;
    if (genres != null) this.genres = List.of(genres);
    onboarding = FanOnboarding(
      preferredCity: preferredCity ?? current.preferredCity,
      genreChoice: genreChoice ?? current.genreChoice,
      collapsed: collapsed ?? current.collapsed,
    );
  }
}

class _DeferredMembershipRepository extends DemoRepository {
  _DeferredMembershipRepository({required super.auth});

  final _memberships = StreamController<List<BandMembership>>.broadcast();

  @override
  Stream<List<BandMembership>> myBands() => _memberships.stream;

  void addMemberships(List<BandMembership> memberships) {
    _memberships.add(memberships);
  }

  bool get hasMembershipListener => _memberships.hasListener;

  Future<void> close() => _memberships.close();
}

class _MembershipRepository extends DemoRepository {
  _MembershipRepository({required super.auth, required this.count});

  final int count;

  @override
  Stream<List<BandMembership>> myBands() => Stream.value([
    if (count >= 1) BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
    if (count >= 2) BandMembership(band: DemoData.bands['b2']!, role: 'member'),
  ]);
}
