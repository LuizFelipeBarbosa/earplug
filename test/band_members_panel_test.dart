import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_members_panel.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

const _panel = Scaffold(
  body: SingleChildScrollView(child: BandMembersPanel(bandId: 'b1')),
);

const _self = 'band-member-${DemoData.demoUserId}';
const _search = Key('band-members-search');
const _generate = Key('band-members-generate-link');

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _typeSearch(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(_search), query);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

Future<void> _openActions(WidgetTester tester, String userId) async {
  await tester.tap(_key('band-member-actions-$userId'));
  await tester.pumpAndSettle();
  expect(find.byType(EpActionSheet), findsOne);
}

void main() {
  testWidgets('member rows show avatar, legible name and role pill', (
    tester,
  ) async {
    await pumpApp(tester, home: _panel);

    expect(find.text('BAND MEMBERS'), findsOne);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: _key('band-members-count'),
              matching: find.byType(Text),
            ),
          )
          .data,
      '1',
    );
    final row = _key(_self);
    expect(row, findsOne);
    expect(
      find.descendant(of: row, matching: find.byType(EpFanAvatar)),
      findsOne,
    );
    final name = tester.widget<Text>(
      find.descendant(of: row, matching: find.text('BAND ADMIN')),
    );
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(
      tester
          .widget<EpBadge>(
            find.descendant(of: row, matching: find.byType(EpBadge)),
          )
          .label,
      'ADMIN',
    );
    expect(find.descendant(of: row, matching: find.text('· YOU')), findsOne);
    expect(_key('band-member-actions-${DemoData.demoUserId}'), findsOne);
    // No link yet, so no invitation block.
    expect(_key('band-invite-url'), findsNothing);
  });

  testWidgets('add by name searches people and adds, then clears the field', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth);
    await pumpApp(tester, auth: auth, repository: repository, home: _panel);

    await _typeSearch(tester, 'zzzz');
    expect(find.text('NO ONE FOUND'), findsOne);

    await _typeSearch(tester, 'Maya');
    final result = _key('band-members-result-u-maya');
    expect(result, findsOne);
    expect(
      find.descendant(of: result, matching: find.byType(EpFanAvatar)),
      findsOne,
    );
    expect(find.text('Already a member'), findsNothing);

    await tester.tap(_key('band-members-add-u-maya'));
    await tester.pumpAndSettle();
    expect(repository.callsTo('addBandMember'), 1);
    expect(tester.widget<TextField>(find.byKey(_search)).controller!.text, '');
    expect(result, findsNothing);
    final added = _key('band-member-u-maya');
    expect(added, findsOne);
    expect(
      tester
          .widget<EpBadge>(
            find.descendant(of: added, matching: find.byType(EpBadge)),
          )
          .label,
      'MEMBER',
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: _key('band-members-count'),
              matching: find.byType(Text),
            ),
          )
          .data,
      '2',
    );

    // Searching again flags them and disables Add.
    await _typeSearch(tester, 'Maya');
    expect(find.text('Already a member'), findsOne);
    expect(
      tester.widget<EpPill>(_key('band-members-add-u-maya')).onPressed,
      isNull,
    );
  });

  testWidgets('Generate link sits beside the field and manages the link', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: _panel);

    final fieldRect = tester.getRect(find.byKey(_search));
    final pillRect = tester.getRect(find.byKey(_generate));
    expect((fieldRect.center.dy - pillRect.center.dy).abs(), lessThan(12));
    expect(pillRect.left, greaterThan(fieldRect.right));
    expect(find.text('GENERATE LINK'), findsOne);

    await tester.tap(find.byKey(_generate));
    await tester.pumpAndSettle();
    final first = harness.app.inviteFor(harness.app.bandId)!;
    expect(find.text(first.url), findsOne);
    expect(_key('band-invite-url'), findsOne);
    expect(find.text('NEW LINK'), findsOne);
    expect(
      find.text(
        'One secure link, valid seven days, usable by several members.',
      ),
      findsOne,
    );
    expect(_key('band-invite-copy'), findsOne);

    await tester.tap(_key('band-invite-rotate'));
    await tester.pumpAndSettle();
    final rotated = harness.app.inviteFor(harness.app.bandId)!;
    expect(rotated.token, isNot(first.token));
    expect(find.text(rotated.url), findsOne);

    await tester.tap(_key('band-invite-revoke'));
    await tester.pumpAndSettle();
    expect(find.text('The previous invitation was revoked.'), findsOne);
    expect(find.text('NEW LINK'), findsOne);
    expect(_key('band-invite-url'), findsNothing);
    expect(_key('invite-management-error'), findsNothing);
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
    expect(_key('band-invite-url'), findsOne);
    expect(_key('band-invite-copy'), findsOne);

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
    expect(find.text('NEW LINK'), findsOne);
    expect(_key('band-invite-url'), findsNothing);
  });

  testWidgets('member panel shows pending work and lets failed actions retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth)..failOnce('createBandInvite');
    final pending = repository.gate('createBandInvite');
    await pumpApp(tester, auth: auth, repository: repository, home: _panel);

    await tester.tap(find.byKey(_generate));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOne);
    expect(tester.widget<EpPill>(find.byKey(_generate)).onPressed, isNull);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester.widget<Text>(_key('invite-management-error')).data,
      'The invitation could not be updated. Please retry.',
    );

    await tester.tap(find.byKey(_generate));
    await tester.pumpAndSettle();
    expect(repository.callsTo('createBandInvite'), 2);
    expect(_key('band-invite-url'), findsOne);
    expect(_key('invite-management-error'), findsNothing);
  });

  testWidgets('overflow offers role toggle and Remove with admin rules', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth);
    await repository.addBandMember(bandId: 'b1', userId: 'u-maya');
    await pumpApp(tester, auth: auth, repository: repository, home: _panel);

    // Yourself: never a role toggle or Remove, only Leave.
    await _openActions(tester, DemoData.demoUserId);
    expect(find.text('Leave band'), findsOne);
    expect(find.text('Make member'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    await tester.tap(find.text('Leave band'));
    await tester.pumpAndSettle();
    expect(find.text('LEAVE FOGHORN DIET?'), findsOne);
    await tester.tap(find.text('KEEP'));
    await tester.pumpAndSettle();
    expect(repository.callsTo('removeBandMember'), 0);
    expect(_key(_self), findsOne);

    // A plain member can be promoted.
    await _openActions(tester, 'u-maya');
    expect(find.text('Make admin'), findsOne);
    expect(find.text('Remove'), findsOne);
    await tester.tap(find.text('Make admin'));
    await tester.pumpAndSettle();
    expect(repository.callsTo('setBandMemberRole'), 1);
    final maya = _key('band-member-u-maya');
    expect(
      tester
          .widget<EpBadge>(
            find.descendant(of: maya, matching: find.byType(EpBadge)),
          )
          .label,
      'ADMIN',
    );

    // Two admins now, so the other one can be demoted or removed.
    await _openActions(tester, 'u-maya');
    expect(find.text('Make member'), findsOne);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('REMOVE MAYA OKAFOR?'), findsOne);
    await tester.tap(find.text('KEEP'));
    await tester.pumpAndSettle();
    expect(repository.callsTo('removeBandMember'), 0);
    expect(maya, findsOne);

    await _openActions(tester, 'u-maya');
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();
    expect(repository.callsTo('removeBandMember'), 1);
    expect(maya, findsNothing);
    expect(find.byType(EpActionSheet), findsNothing);
  });

  testWidgets('the last admin cannot be demoted from the overflow', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth)
      ..returns('bandMembers', const [
        BandMember(
          userId: 'u-maya',
          name: 'Maya Okafor',
          role: BandMemberRole.admin,
        ),
        BandMember(
          userId: DemoData.demoUserId,
          name: 'Band admin',
          role: BandMemberRole.member,
          isSelf: true,
        ),
      ]);
    await pumpApp(tester, auth: auth, repository: repository, home: _panel);

    await _openActions(tester, 'u-maya');
    expect(find.text('Make member'), findsNothing);
    expect(find.text('Remove'), findsOne);
  });

  testWidgets('Leave band confirms and then removes yourself', (tester) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth);
    await repository.addBandMember(
      bandId: 'b1',
      userId: 'u-maya',
      role: BandMemberRole.admin,
    );
    await pumpApp(tester, auth: auth, repository: repository, home: _panel);

    await _openActions(tester, DemoData.demoUserId);
    await tester.tap(find.text('Leave band'));
    await tester.pumpAndSettle();
    expect(find.text('LEAVE FOGHORN DIET?'), findsOne);
    await tester.tap(find.text('LEAVE'));
    await tester.pumpAndSettle();
    expect(repository.callsTo('removeBandMember'), 1);
    expect(_key(_self), findsNothing);
  });

  testWidgets('non-admins get no add row, link or overflow except Leave', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _MemberRepository(auth: auth);
    await pumpApp(tester, auth: auth, repository: repository, home: _panel);

    expect(find.byKey(_search), findsNothing);
    expect(find.byKey(_generate), findsNothing);
    expect(_key('band-invite-url'), findsNothing);
    expect(_key('band-member-u-maya'), findsOne);
    expect(_key('band-member-actions-u-maya'), findsNothing);
    expect(_key(_self), findsOne);

    await _openActions(tester, DemoData.demoUserId);
    expect(find.text('Leave band'), findsOne);
    expect(find.text('Make admin'), findsNothing);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('member panel fits a 390px phone without overflow', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..returns('bandMembers', const [
        BandMember(
          userId: DemoData.demoUserId,
          name: 'Band admin',
          role: BandMemberRole.admin,
          isSelf: true,
        ),
        BandMember(
          userId: 'u-long',
          name: 'Maximilian Featherstonehaugh-Worthington III',
          role: BandMemberRole.member,
        ),
      ]);
    final harness = await pumpApp(
      tester,
      size: const Size(390, 900),
      auth: auth,
      repository: repository,
      home: _panel,
    );
    await harness.app.createBandInvitation();
    await tester.pumpAndSettle();
    await _typeSearch(tester, 'Maya');

    expect(_key('band-invite-url'), findsOne);
    expect(_key('band-members-result-u-maya'), findsOne);
    expect(_key('band-member-u-long'), findsOne);
    expect(tester.takeException(), isNull);
  });
}

class _InviteStateRepository extends DemoRepository {
  _InviteStateRepository({required super.auth, required this.invite});

  BandInvite invite;

  @override
  Future<BandInvite?> bandInvite(String bandId) async => invite;
}

class _MemberRepository extends StubRepository {
  _MemberRepository({required super.auth}) {
    returnsStream(
      'myBands',
      () => Stream.value([
        BandMembership(band: DemoData.bands['b1']!, role: 'member'),
      ]),
    );
    returns('bandMembers', const [
      BandMember(
        userId: 'u-maya',
        name: 'Maya Okafor',
        role: BandMemberRole.admin,
      ),
      BandMember(
        userId: DemoData.demoUserId,
        name: 'Band admin',
        role: BandMemberRole.member,
        isSelf: true,
      ),
    ]);
  }
}
