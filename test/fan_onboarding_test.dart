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
import 'support/stub_repository.dart';

void main() {
  testWidgets('zero-band navigation offers creation without profile entries', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _membershipRepository(auth: auth, count: 0),
      home: const Scaffold(
        body: MyGigsScreen(),
        bottomNavigationBar: FanTabBar(),
      ),
    );

    expect(find.byKey(const Key('band-entry')), findsNothing);
    expect(find.byKey(const Key('create-band-from-profile')), findsNothing);
    expect(find.text('PLAY IN A BAND?'), findsNothing);
    expect(find.text('CREATE'), findsOne);
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    expect(find.text('BECOME AN ORGANIZER'), findsOne);
    await tester.tap(find.text('START A BAND'));
    await tester.pumpAndSettle();
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

    expect(find.text('CREATE'), findsOne);
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    expect(find.text('BECOME AN ORGANIZER'), findsOne);
    await tester.tap(find.text('START A BAND'));
    await tester.pumpAndSettle();

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

    expect(find.text('ACCOUNTS'), findsOne);
    expect(repository.hasMembershipListener, isTrue);
    await tester.tap(find.text('ACCOUNTS'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.home);

    repository.addMemberships([
      BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
    ]);
    await tester.pumpAndSettle();

    expect(harness.app.membershipsLoaded, isTrue);
    expect(harness.app.myBands, ['b1']);
    expect(find.text('ACCOUNTS'), findsOne);
    await tester.tap(find.text('ACCOUNTS'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR ACCOUNTS'), findsOne);
    await tester.tap(find.text('Foghorn Diet'));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.gigMgr);
    expect(harness.app.bandId, 'b1');

    await harness.app.signOut();
    await tester.pump();
    expect(harness.app.myBands, isEmpty);
    expect(harness.app.membershipsLoaded, isFalse);
    expect(find.text('CREATE'), findsOne);
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
      repository: _membershipRepository(auth: auth, count: 1),
      home: const Scaffold(
        body: MyGigsScreen(),
        bottomNavigationBar: FanTabBar(),
      ),
    );

    expect(find.text('ACCOUNTS'), findsOne);
    await tester.tap(find.text('ACCOUNTS'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR ACCOUNTS'), findsOne);
    expect(find.text('Personal account'), findsOne);
    await tester.tap(find.text('Foghorn Diet'));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.gigMgr);
    expect(harness.app.bandId, 'b1');
  });

  testWidgets('multi-band navigation opens the switcher', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: _membershipRepository(auth: auth, count: 2),
      home: const Scaffold(
        body: MyGigsScreen(),
        bottomNavigationBar: FanTabBar(),
      ),
    );

    expect(find.text('ACCOUNTS'), findsOne);
    await tester.tap(find.text('ACCOUNTS'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR ACCOUNTS'), findsOne);
    expect(find.text('Pigeon Court'), findsWidgets);
  });
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

StubRepository _membershipRepository({
  required AuthService auth,
  required int count,
}) => StubRepository(auth: auth)
  ..returnsStream<List<OrganizationMembership>>(
    'myOrganizations',
    () => Stream.value(const []),
  )
  ..returnsStream(
    'myBands',
    () => Stream.value([
      if (count >= 1)
        BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
      if (count >= 2)
        BandMembership(band: DemoData.bands['b2']!, role: 'member'),
    ]),
  );
