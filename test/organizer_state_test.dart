import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/readiness_memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

const _org1 = 'org1';
const _org2 = 'org2';
const _orgScope = 'org:org1';
const _financeStep = 'org-setup-finance';

final _opp1 = DemoData.opportunities['opp1']!;
final _opp2 = DemoData.opportunities['opp2']!;

OrganizationDashboard _dashboard({
  bool profileComplete = true,
  int memberCount = 1,
}) => OrganizationDashboard(
  organization: DemoData.organizations[_org1]!,
  role: OrganizationRole.owner,
  viaPlatformAdmin: false,
  verification: OrganizationVerification(
    verified: true,
    stripeDetailsSubmitted: true,
    stripeChargesEnabled: true,
    stripePayoutsEnabled: true,
    profileComplete: profileComplete,
    teamInvited: false,
  ),
  venues: const [],
  memberCount: memberCount,
  privateDetails: null,
);

StripeAccountStatus _stripe(StripeAccountState state) => StripeAccountStatus(
  state: state,
  hasAccount: state != StripeAccountState.none,
  chargesEnabled: state == StripeAccountState.enabled,
  payoutsEnabled: state == StripeAccountState.enabled,
  detailsSubmitted: state == StripeAccountState.enabled,
  requirementsDue: const [],
);

/// A signed-in app over [stub], with [controllers] handing out one broadcast
/// opportunity stream per `watchOrganizationOpportunities` call, in order.
Future<AppHarness> _pump(
  WidgetTester tester,
  StubRepository stub, {
  List<StreamController<List<Opportunity>>> controllers = const [],
  MemoryReadinessMemoryStore? store,
  DateTime Function()? now,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  if (controllers.isNotEmpty) {
    final pending = List.of(controllers);
    stub.returnsStream<List<Opportunity>>(
      'watchOrganizationOpportunities',
      () => pending.removeAt(0).stream,
    );
  }
  return pumpApp(
    tester,
    auth: auth,
    repository: stub,
    readinessMemoryStore: store,
    now: now,
    home: const Scaffold(body: SizedBox()),
  );
}

void main() {
  testWidgets('the opportunity subscription updates the list on each event', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final controller = StreamController<List<Opportunity>>.broadcast();
    final harness = await _pump(
      tester,
      StubRepository(auth: auth),
      controllers: [controller],
    );
    final app = harness.app;
    var notifications = 0;
    app.addListener(() => notifications++);

    final firstLoad = app.refreshOpportunities(_org1);
    expect(app.opportunitiesStatus(_org1), DataStatus.connecting);
    controller.add([_opp1]);
    await firstLoad;
    expect(app.opportunitiesFor(_org1).map((o) => o.id), ['opp1']);
    expect(app.opportunitiesStatus(_org1), DataStatus.ready);
    expect(notifications, 1);

    controller.add([_opp2, _opp1]);
    await tester.pump();
    expect(app.opportunitiesFor(_org1).map((o) => o.id), ['opp2', 'opp1']);
    expect(notifications, 2);

    app.dispose();
    expect(controller.hasListener, isFalse);
    await controller.close();
  });

  testWidgets('refreshing an organization replaces its subscription', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final org1First = StreamController<List<Opportunity>>.broadcast();
    final org2 = StreamController<List<Opportunity>>.broadcast();
    final org1Second = StreamController<List<Opportunity>>.broadcast();
    final stub = StubRepository(auth: auth);
    final harness = await _pump(
      tester,
      stub,
      controllers: [org1First, org2, org1Second],
    );
    final app = harness.app;

    final org1Load = app.refreshOpportunities(_org1);
    org1First.add([_opp1]);
    await org1Load;
    final org2Load = app.refreshOpportunities(_org2);
    org2.add([_opp2]);
    await org2Load;
    expect(stub.callsTo('watchOrganizationOpportunities'), 2);
    expect(app.opportunitiesFor(_org1).map((o) => o.id), ['opp1']);
    expect(app.opportunitiesFor(_org2).map((o) => o.id), ['opp2']);
    expect(org1First.hasListener, isTrue);

    // Re-subscribing org1 cancels its earlier stream; org2 is untouched.
    final resubscribe = app.refreshOpportunities(_org1);
    await tester.pump();
    expect(org1First.hasListener, isFalse);
    expect(org2.hasListener, isTrue);
    org1First.add([_opp2, _opp1]);
    org1Second.add([]);
    await resubscribe;
    expect(app.opportunitiesFor(_org1), isEmpty);
    expect(app.opportunitiesFor(_org2).map((o) => o.id), ['opp2']);

    app.dispose();
    await Future.wait([org1First.close(), org2.close(), org1Second.close()]);
  });

  testWidgets('sign-out cancels the subscription and clears the list', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final controller = StreamController<List<Opportunity>>.broadcast();
    final harness = await _pump(
      tester,
      StubRepository(auth: auth),
      controllers: [controller],
    );
    final app = harness.app;
    final load = app.refreshOpportunities(_org1);
    controller.add([_opp1]);
    await load;
    expect(app.opportunitiesFor(_org1), isNotEmpty);

    await app.signOut();
    await tester.pump();

    expect(app.opportunitiesFor(_org1), isEmpty);
    expect(app.opportunitiesStatus(_org1), DataStatus.connecting);
    expect(controller.hasListener, isFalse);
    app.dispose();
    await controller.close();
  });

  testWidgets('a stream error keeps the last list and marks the status', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final controller = StreamController<List<Opportunity>>.broadcast();
    final harness = await _pump(
      tester,
      StubRepository(auth: auth),
      controllers: [controller],
    );
    final app = harness.app;
    final load = app.refreshOpportunities(_org1);
    controller.add([_opp1]);
    await load;

    controller.addError(StateError('offline'));
    await tester.pump();

    expect(app.opportunitiesFor(_org1).map((o) => o.id), ['opp1']);
    expect(app.opportunitiesStatus(_org1), DataStatus.error);

    // The stream is still live: a later event recovers.
    controller.add([_opp2]);
    await tester.pump();
    expect(app.opportunitiesFor(_org1).map((o) => o.id), ['opp2']);
    expect(app.opportunitiesStatus(_org1), DataStatus.ready);
    app.dispose();
    await controller.close();
  });

  testWidgets('the demo stream re-emits after an opportunity mutation', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await _pump(tester, StubRepository(auth: auth));
    final app = harness.app;
    await app.refreshOpportunities(_org1);
    final before = app.opportunitiesFor(_org1).length;

    await app.repository.duplicateOpportunity('opp1');
    await tester.pump();

    expect(app.opportunitiesFor(_org1).length, before + 1);
    app.dispose();
  });

  testWidgets('the dashboard loads lazily on first read and refreshes', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final stub = StubRepository(auth: auth)
      ..returns('organizationDashboard', _dashboard(memberCount: 1));
    final harness = await _pump(tester, stub);
    final app = harness.app;

    expect(app.organizationDashboardFor(_org1), isNull);
    expect(app.organizationDashboardLoadingFor(_org1), isTrue);
    await tester.pump();
    expect(app.organizationDashboardFor(_org1)?.memberCount, 1);
    expect(app.organizationDashboardFor(_org1)?.memberCount, 1);
    expect(stub.callsTo('organizationDashboard'), 1);

    stub.returns('organizationDashboard', _dashboard(memberCount: 3));
    await app.refreshOrganizationDashboard(_org1);
    expect(app.organizationDashboardFor(_org1)?.memberCount, 3);
    expect(stub.callsTo('organizationDashboard'), 2);

    await app.signOut();
    expect(app.organizationDashboardFor(''), isNull);
    expect(stub.callsTo('organizationDashboard'), 2);
    app.dispose();
  });

  testWidgets('a failed dashboard load is not retried until a refresh', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final stub = StubRepository(auth: auth)
      ..returns('organizationDashboard', _dashboard())
      ..failOnce('organizationDashboard');
    final harness = await _pump(tester, stub);
    final app = harness.app;

    expect(app.organizationDashboardFor(_org1), isNull);
    expect(app.organizationDashboardLoadingFor(_org1), isTrue);
    await tester.pump();
    expect(app.organizationDashboardLoadingFor(_org1), isFalse);
    expect(app.organizationDashboardFailedFor(_org1), isTrue);

    // Reads through every path leave the failure alone.
    expect(app.organizationDashboardFor(_org1), isNull);
    expect(app.hostReadinessSnapshotFor(_org1), isNull);
    expect(app.readinessSnapshotFor(_orgScope), isNull);
    await tester.pumpAndSettle();
    expect(app.organizationDashboardFor(_org1), isNull);
    expect(stub.callsTo('organizationDashboard'), 1);

    await app.refreshOrganizationDashboard(_org1);
    expect(app.organizationDashboardFailedFor(_org1), isFalse);
    expect(app.organizationDashboardFor(_org1), isNotNull);
    expect(stub.callsTo('organizationDashboard'), 2);
    app.dispose();
  });

  testWidgets('a signed-out org dash settles without refetching', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final stub = StubRepository(auth: auth)
      ..returns('organizationDashboard', _dashboard());
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: stub,
      beforePump: (app) => app
        ..switchToOrganization(_org1)
        ..resetTo(Screen.orgDash),
      home: const RootShell(),
    );
    final app = harness.app;
    expect(app.authed, isFalse);
    expect(app.current.screen, Screen.orgDash);

    // The discarded result is remembered as a failure, so each rebuild reads
    // the null dashboard without kicking the load off again.
    await tester.pumpAndSettle();
    expect(app.organizationDashboardFor(_org1), isNull);
    expect(app.organizationDashboardFailedFor(_org1), isTrue);
    expect(stub.callsTo('organizationDashboard'), 1);
  });

  testWidgets('host readiness derives from the dashboard and Stripe status', (
    tester,
  ) async {
    final start = DateTime(2026, 9, 16, 12);
    var now = start;
    final store = MemoryReadinessMemoryStore();
    final auth = FakeAuthService();
    final stub = StubRepository(auth: auth)
      ..returns('organizationDashboard', _dashboard(profileComplete: true))
      ..returns(
        'organizationStripeStatus',
        _stripe(StripeAccountState.enabled),
      );
    final harness = await _pump(tester, stub, store: store, now: () => now);
    final app = harness.app;
    app.switchToOrganization(_org1);
    await tester.pumpAndSettle();

    // Null until both sources are in; nothing is remembered before that.
    await app.refreshOrganizationDashboard(_org1);
    await tester.pump();
    expect(app.hostReadinessSnapshotFor(_org1), isNull);
    expect(await store.read(_orgScope), isNull);

    await app.refreshOrganizationStripeStatus();
    await tester.pump();
    final complete = app.readinessSnapshotFor(_orgScope)!;
    expect(complete.total, 2);
    expect(complete.done, 2);
    expect(complete.complete, isTrue);
    expect((await store.read(_orgScope))!.doneIds, complete.doneIds);
    expect(app.readinessRegressionFor(_orgScope), isNull);

    // Stripe drops back to onboarding: the finance step is undone and the
    // reconcile after the refresh records the regression.
    now = start.add(const Duration(days: 1));
    stub.returns(
      'organizationStripeStatus',
      _stripe(StripeAccountState.onboarding),
    );
    await app.refreshOrganizationStripeStatus();
    await tester.pump();
    final regressed = app.readinessSnapshotFor(_orgScope)!;
    expect(regressed.done, 1);
    expect(regressed.todo.single.id, _financeStep);
    final regression = app.readinessRegressionFor(_orgScope)!;
    expect(regression.stepIds, [_financeStep]);
    expect(regression.since, now);
    expect(app.readinessSheetShouldAutoOpen(_orgScope), isTrue);

    // An incomplete profile from the dashboard undoes the other step.
    stub.returns('organizationDashboard', _dashboard(profileComplete: false));
    await app.refreshOrganizationDashboard(_org1);
    await tester.pump();
    expect(app.readinessSnapshotFor(_orgScope)!.done, 0);
    expect(app.readinessRegressionFor(_orgScope)!.stepIds, [
      'org-setup-profile',
      _financeStep,
    ]);
    app.dispose();
  });

  testWidgets('a stale Stripe status from another organization is ignored', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final stub = StubRepository(auth: auth)
      ..returns('organizationDashboard', _dashboard())
      ..returns(
        'organizationStripeStatus',
        _stripe(StripeAccountState.enabled),
      );
    final harness = await _pump(tester, stub);
    final app = harness.app;
    app.switchToOrganization(_org1);
    await tester.pumpAndSettle();
    await app.refreshOrganizationDashboard(_org1);
    await app.refreshOrganizationStripeStatus();
    await tester.pump();
    expect(app.hostReadinessSnapshotFor(_org1)!.complete, isTrue);

    app.switchToOrganization(_org2);
    await tester.pumpAndSettle();
    expect(app.organizationStripeStatus, isNotNull);
    expect(app.organizationStripeStatusFor(_org2), isNull);
    await app.refreshOrganizationDashboard(_org2);
    await tester.pump();
    expect(app.hostReadinessSnapshotFor(_org2), isNull);
    app.dispose();
  });
}
