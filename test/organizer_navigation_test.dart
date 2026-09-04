import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('a new account can apply without creating a band', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _NewOrganizerRepository(auth: auth),
      home: const RootShell(),
    );

    expect(harness.app.myBands, isEmpty);
    expect(harness.app.myOrganizations, isEmpty);
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switcher-become-organizer')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.orgApply);
    expect(find.byKey(const ValueKey('org-apply-name')), findsOneWidget);
    expect(harness.app.myBands, isEmpty);
  });

  testWidgets('signed-out organizer entry resumes application after sign-in', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _NewOrganizerRepository(auth: auth),
      home: const RootShell(),
    );

    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switcher-become-organizer')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.auth);
    expect(harness.app.pending?.kind, PendingKind.orgApply);

    await auth.signInDemo();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgApply);
    expect(find.byKey(const ValueKey('org-apply-name')), findsOneWidget);
  });

  testWidgets(
    'invitation sign-in preserves the token and requires acceptance',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _InviteRepository(auth: auth);
      final invite = await repository.createOrganizationInvite(
        organizationId: 'org1',
        role: OrganizationRole.manager,
      );
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        beforePump: (app) => app.openOrganizationJoin(invite.token),
        home: const RootShell(),
      );

      await tester.tap(find.text('SIGN IN TO JOIN'));
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.auth);
      expect(harness.app.pending?.kind, PendingKind.orgJoin);
      expect(harness.app.pending?.id, invite.token);
      expect(repository.acceptedTokens, isEmpty);

      await auth.signInDemo();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(harness.app.current.screen, Screen.orgJoin);
      expect(harness.app.current.param, invite.token);
      expect(repository.acceptedTokens, isEmpty);
      await tester.tap(find.text('ACCEPT'));
      await tester.pumpAndSettle();
      expect(repository.acceptedTokens, [invite.token]);
      expect(harness.app.current.screen, Screen.orgDash);
    },
  );

  testWidgets('organizer memberships drive the switcher and organizer shell', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const RootShell(),
    );

    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    expect(
      harness.app.myOrganizations.any(
        (membership) => membership.organization.id == 'org1',
      ),
      isTrue,
    );

    await tester.tap(find.text('SWITCH'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('switcher-org-org1')), findsOne);
    expect(find.byKey(const Key('switcher-become-organizer')), findsOne);

    await tester.tap(find.text('Personal account'));
    await tester.pumpAndSettle();
    await enterOrganizer(tester, harness, 'org1');

    expect(find.byKey(const Key('organizer-tab-dash')), findsOne);
    expect(find.byKey(const Key('org-dash-verification')), findsOne);
    expect(harness.app.identity, isA<OrganizerIdentity>());

    harness.app.toFanView();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('organizer-tab-dash')), findsNothing);
    expect(find.text('GIGS'), findsOne);
    expect(find.text('EXPLORE'), findsOne);
    expect(find.text('PROFILE'), findsOne);
    expect(harness.app.identity, isA<PersonalIdentity>());
  });

  testWidgets('platform admins can enter the admin shell from the switcher', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const RootShell(),
    );

    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    expect(harness.app.isPlatformAdmin, isTrue);

    await tester.tap(find.text('SWITCH'));
    await tester.pumpAndSettle();
    final adminButton = find.byKey(const Key('switcher-admin'));
    await tester.ensureVisible(adminButton);
    await tester.tap(adminButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-queue-exit')), findsOne);
    expect(harness.app.identity, isA<AdminIdentity>());
  });
}

class _NewOrganizerRepository extends DemoRepository {
  _NewOrganizerRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() => Stream.value(const []);

  @override
  Stream<List<OrganizationMembership>> myOrganizations() =>
      Stream.value(const []);
}

class _InviteRepository extends DemoRepository {
  _InviteRepository({required super.auth});

  final acceptedTokens = <String>[];

  @override
  Future<OrganizationInviteAcceptance> acceptOrganizationInvite(String token) {
    acceptedTokens.add(token);
    return super.acceptOrganizationInvite(token);
  }
}
