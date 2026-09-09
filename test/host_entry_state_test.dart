import 'package:earplug/app_state.dart';
import 'package:earplug/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('host detection follows organization memberships and selection', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const SizedBox.shrink());

    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    expect(harness.app.isHostOrganization('org2'), isTrue);
    expect(harness.app.isHostOrganization('org1'), isFalse);
    expect(harness.app.isHostOrganization('missing'), isFalse);
    harness.app.switchToOrganization('org2');
    await tester.pumpAndSettle();
    expect(harness.app.currentIsHost, isTrue);

    harness.app.switchToOrganization('org1');
    await tester.pumpAndSettle();
    expect(harness.app.currentIsHost, isFalse);
    harness.app.dispose();
  });

  testWidgets('signed-out host entry resumes application after sign-in', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const RootShell());

    harness.app.openHostApply();
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.auth);
    expect(harness.app.pending?.kind, PendingKind.hostApply);

    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.hostApply);
    expect(harness.app.pending, isNull);
    expect(harness.app.identity, isA<PersonalIdentity>());
    expect(find.byKey(const ValueKey('hostApply-null')), findsOneWidget);
  });

  testWidgets('signed-in host entry opens the application directly', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const RootShell());
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    harness.app.openHostApply();
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.hostApply);
    expect(harness.app.pending, isNull);
    expect(find.byKey(const ValueKey('hostApply-null')), findsOneWidget);
  });
}
