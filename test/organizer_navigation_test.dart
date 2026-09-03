import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
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
    expect(find.byKey(const Key('placeholder-orgDash')), findsOne);
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

    expect(find.byKey(const Key('placeholder-adminQueue')), findsOne);
    expect(harness.app.identity, isA<AdminIdentity>());
  });
}
