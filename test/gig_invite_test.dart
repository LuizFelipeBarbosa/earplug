import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_invite.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
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
