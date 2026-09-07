import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('feature flags keep their defaults until loading completes', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledFeatureFlagsRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );

    expect(harness.app.authed, isFalse);
    expect(harness.app.features.bandGigWrites, isTrue);
    expect(harness.app.features.privateBookings, isFalse);
    expect(harness.app.features.tickets, isFalse);
    expect(harness.app.features.payments, isFalse);
    expect(harness.app.privateBookingsEnabled, isFalse);

    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    // One load on cold start while signed out, one more on sign-in.
    expect(repository.featureFlagsCalls, 2);
    expect(harness.app.features.bandGigWrites, isTrue);
    expect(harness.app.features.privateBookings, isFalse);
    expect(harness.app.features.tickets, isFalse);
    expect(harness.app.features.payments, isFalse);
    expect(harness.app.privateBookingsEnabled, isFalse);

    repository.pendingFlags.complete(
      const FeatureFlags(
        privateBookings: true,
        tickets: true,
        payments: true,
        bandGigWrites: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.app.privateBookingsEnabled, isTrue);
    expect(harness.app.features.tickets, isTrue);
    expect(harness.app.features.payments, isTrue);
    expect(harness.app.features.bandGigWrites, isFalse);
    harness.app.dispose();
  });

  testWidgets('sign-in loads the demo feature flags', (tester) async {
    final harness = await pumpApp(tester, home: const SizedBox.shrink());

    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    expect(harness.app.privateBookingsEnabled, isTrue);
    expect(harness.app.features.tickets, isTrue);
    harness.app.dispose();
  });

  testWidgets('sign-out refreshes the feature flags', (tester) async {
    final auth = FakeAuthService();
    final repository = _ControlledFeatureFlagsRepository(auth: auth);
    repository.pendingFlags.complete(
      const FeatureFlags(
        privateBookings: true,
        tickets: true,
        payments: true,
        bandGigWrites: true,
      ),
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    expect(harness.app.privateBookingsEnabled, isTrue);

    repository.pendingFlags = Completer<FeatureFlags>();
    await harness.app.signOut();
    await tester.pumpAndSettle();
    // Cold start, sign-in, sign-out.
    expect(repository.featureFlagsCalls, 3);

    repository.pendingFlags.complete(
      const FeatureFlags(
        privateBookings: false,
        tickets: false,
        payments: false,
        bandGigWrites: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.app.authed, isFalse);
    expect(harness.app.privateBookingsEnabled, isFalse);
    expect(harness.app.features.tickets, isFalse);
    harness.app.dispose();
  });

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

class _ControlledFeatureFlagsRepository extends DemoRepository {
  _ControlledFeatureFlagsRepository({required super.auth});

  Completer<FeatureFlags> pendingFlags = Completer<FeatureFlags>();
  int featureFlagsCalls = 0;

  @override
  Future<FeatureFlags> featureFlags() {
    featureFlagsCalls++;
    return pendingFlags.future;
  }
}
