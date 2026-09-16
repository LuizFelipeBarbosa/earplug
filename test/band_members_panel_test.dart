import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_members_panel.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

const _panel = Scaffold(
  body: SingleChildScrollView(child: BandMembersPanel(bandId: 'b1')),
);

void main() {
  testWidgets('member panel creates, rotates, and revokes secure links', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: _panel);

    expect(find.text('BAND MEMBERS · 1'), findsOne);
    expect(
      find.text(
        'One secure link, valid seven days, usable by several members.',
      ),
      findsOne,
    );
    expect(find.text('BAND ADMIN'), findsOne);
    final member = tester.widget<EpChip>(
      find.byKey(const ValueKey('accepted-member-Band admin')),
    );
    expect(member.onTap, isNull);

    await tester.tap(find.text('CREATE INVITATION LINK'));
    await tester.pumpAndSettle();
    final first = harness.app.inviteFor(harness.app.bandId)!;
    expect(find.text(first.url), findsOne);
    expect(find.byKey(const ValueKey('band-invite-url')), findsOne);
    expect(find.text('COPY INVITATION LINK'), findsOne);

    await tester.tap(find.text('ROTATE LINK'));
    await tester.pumpAndSettle();
    final rotated = harness.app.inviteFor(harness.app.bandId)!;
    expect(rotated.token, isNot(first.token));
    expect(find.text(rotated.url), findsOne);

    await tester.tap(find.text('REVOKE LINK'));
    await tester.pumpAndSettle();
    expect(find.text('The previous invitation was revoked.'), findsOne);
    expect(find.text('CREATE NEW INVITATION LINK'), findsOne);
    expect(find.byKey(const ValueKey('band-invite-url')), findsNothing);
    expect(find.byKey(const ValueKey('invite-management-error')), findsNothing);
  });

  testWidgets('member panel trusts server invitation expiry state', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _InviteStateRepository(
      auth: auth,
      invite: BandInvite(
        bandId: 'b1',
        token: 'server-active',
        expiresAt: DateTime.utc(2000),
        revoked: false,
        expired: false,
      ),
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: _panel,
    );

    expect(find.text(repository.invite.url), findsOne);
    expect(find.byKey(const ValueKey('band-invite-url')), findsOne);
    expect(find.text('COPY INVITATION LINK'), findsOne);

    repository.invite = BandInvite(
      bandId: 'b1',
      token: 'server-expired',
      expiresAt: DateTime.utc(2100),
      revoked: false,
      expired: true,
    );
    await harness.app.refreshBandInvite('b1');
    await tester.pumpAndSettle();

    expect(find.text('The previous invitation expired.'), findsOne);
    expect(find.text('CREATE NEW INVITATION LINK'), findsOne);
    expect(find.byKey(const ValueKey('band-invite-url')), findsNothing);
  });

  testWidgets('member panel shows pending work and lets failed actions retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth)..failOnce('createBandInvite');
    final pending = repository.gate('createBandInvite');
    await pumpApp(tester, auth: auth, repository: repository, home: _panel);

    await tester.tap(find.text('CREATE INVITATION LINK'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOne);
    expect(
      tester.widget<EpButton>(find.byType(EpButton)).kind,
      EpButtonKind.disabled,
    );

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('invite-management-error')))
          .data,
      'The invitation could not be updated. Please retry.',
    );

    await tester.tap(find.text('CREATE INVITATION LINK'));
    await tester.pumpAndSettle();
    expect(repository.callsTo('createBandInvite'), 2);
    expect(find.byKey(const ValueKey('band-invite-url')), findsOne);
    expect(find.byKey(const ValueKey('invite-management-error')), findsNothing);
  });
}

class _InviteStateRepository extends DemoRepository {
  _InviteStateRepository({required super.auth, required this.invite});

  BandInvite invite;

  @override
  Future<BandInvite?> bandInvite(String bandId) async => invite;
}
