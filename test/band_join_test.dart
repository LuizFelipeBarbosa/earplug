import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_join.dart';
import 'package:earplug/screens/gig_invite.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  test('demo acceptance creates one member membership and follower', () async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final before = await repository.band('b2');
    final invite = await repository.createBandInvite('b2');
    await auth.signInDemo();

    final first = await repository.acceptBandInvite(invite.token);
    final second = await repository.acceptBandInvite(invite.token);
    final memberships = await repository.myBands().first;

    expect(first.membershipCreated, isTrue);
    expect(second.membershipCreated, isFalse);
    expect(
      memberships,
      contains(
        isA<BandMembership>()
            .having((membership) => membership.band.id, 'band id', 'b2')
            .having((membership) => membership.role, 'role', 'member'),
      ),
    );
    expect((await repository.band('b2'))!.followers, before!.followers + 1);
  });

  testWidgets('resolved invitation waits for explicit confirmation', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final invite = await repository.createBandInvite('b1');
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.openJoinInvite(invite.token),
      home: const Scaffold(body: BandJoinScreen()),
    );

    expect(find.text('Join Foghorn Diet?'), findsOne);
    expect(find.text('JOIN BAND'), findsOne);
    expect(harness.app.joinInviteAccepted, isFalse);

    await tester.tap(find.text('JOIN BAND'));
    await tester.pumpAndSettle();
    expect(harness.app.joinInviteAccepted, isTrue);
    expect(find.text('You joined Foghorn Diet.'), findsOne);
    expect(find.text('OPEN BAND DASHBOARD'), findsOne);
  });

  testWidgets('accepted membership updates band navigation before its stream', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _DeferredJoinMembershipRepository(auth: auth);
    addTearDown(repository.close);
    final invite = await repository.createBandInvite('b2');
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.openJoinInvite(invite.token),
      home: const Scaffold(
        body: BandJoinScreen(),
        bottomNavigationBar: FanTabBar(),
      ),
    );

    expect(find.text('CREATE BAND'), findsOne);
    await tester.tap(find.text('JOIN BAND'));
    await tester.pumpAndSettle();

    expect(harness.app.myBands, ['b2']);
    expect(find.text('SWITCH BAND'), findsOne);
    await tester.tap(find.text('SWITCH BAND'));
    await tester.pumpAndSettle();
    expect(find.text('PIGEON COURT'), findsOne);
  });

  testWidgets('signed-out recipient keeps the invite through authentication', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final invite = await repository.createBandInvite('b1');
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.openJoinInvite(invite.token),
      home: const Scaffold(body: BandJoinScreen()),
    );

    expect(find.text('SIGN IN TO JOIN'), findsOne);
    expect(find.textContaining('will not join automatically'), findsOne);
    await tester.tap(find.text('SIGN IN TO JOIN'));
    await tester.pump();

    expect(harness.app.current.screen, Screen.auth);
    expect(harness.app.pending?.kind, PendingKind.join);
    expect(harness.app.pending?.id, invite.token);
    expect(harness.app.joinInviteAccepted, isFalse);
  });

  testWidgets('invalid, expired, or revoked invitations show no join action', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.openJoinInvite('not-a-real-token'),
      home: const Scaffold(body: BandJoinScreen()),
    );

    expect(find.text('Invitation unavailable'), findsOne);
    expect(
      find.text('This invitation is invalid, expired, or revoked.'),
      findsOne,
    );
    expect(find.text('JOIN BAND'), findsNothing);
    expect(find.text('SIGN IN TO JOIN'), findsNothing);
  });

  testWidgets('acceptance errors stay on the confirmation screen for retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _FailingAcceptRepository(auth: auth);
    final invite = await repository.createBandInvite('b1');
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.openJoinInvite(invite.token),
      home: const Scaffold(body: BandJoinScreen()),
    );

    await tester.tap(find.text('JOIN BAND'));
    await tester.pumpAndSettle();
    expect(find.text('This invitation could not be accepted.'), findsOne);
    expect(find.text('TRY AGAIN'), findsOne);
  });

  testWidgets(
    'performer invitation confirms, gates auth, and claims for a band',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _InviteRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: GigInviteScreen()),
        beforePump: (app) => app.openPerformerInvite('invite-token'),
      );
      final app = harness.app;

      expect(find.text('Join The Shared Bill?'), findsOne);
      expect(find.text('SIGN IN TO CLAIM'), findsOne);
      await tester.tap(find.text('SIGN IN TO CLAIM'));
      await tester.pump();
      expect(app.current.screen, Screen.auth);
      expect(app.pending?.kind, PendingKind.gigInvite);

      await auth.signInDemo();
      await app.commitAuth();
      app.leaveAuth();
      await tester.pumpAndSettle();
      expect(find.text('Foghorn Diet'), findsOne);
      expect(find.text('CLAIM LINEUP SPOT'), findsOne);

      await tester.tap(find.text('CLAIM LINEUP SPOT'));
      await tester.pumpAndSettle();
      expect(repository.claimedToken, 'invite-token');
      expect(repository.claimedBandId, 'b1');
      expect(find.text('You joined The Shared Bill.'), findsOne);
    },
  );
}

class _FailingAcceptRepository extends DemoRepository {
  _FailingAcceptRepository({required super.auth});

  @override
  Future<BandInviteAcceptance> acceptBandInvite(String token) async {
    throw StateError('offline');
  }
}

class _DeferredJoinMembershipRepository extends DemoRepository {
  _DeferredJoinMembershipRepository({required super.auth});

  final StreamController<List<BandMembership>> _updates =
      StreamController<List<BandMembership>>.broadcast();
  var _subscriptions = 0;

  @override
  Stream<List<BandMembership>> myBands() async* {
    _subscriptions++;
    if (_subscriptions == 1) yield const [];
    yield* _updates.stream;
  }

  Future<void> close() => _updates.close();
}

class _InviteRepository extends DemoRepository {
  _InviteRepository({required super.auth});

  String? claimedToken;
  String? claimedBandId;

  @override
  Future<PerformerInviteResolution?> resolvePerformerInvite(
    String token,
  ) async {
    return const PerformerInviteResolution(
      performerName: 'Placeholder Artist',
      gigTitle: 'The Shared Bill',
    );
  }

  @override
  Future<String> claimPerformerInvite({
    required String token,
    required String bandId,
  }) async {
    claimedToken = token;
    claimedBandId = bandId;
    return 'project-id';
  }
}
