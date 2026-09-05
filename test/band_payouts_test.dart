import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_dash.dart';
import 'package:earplug/screens/band_payouts.dart';
import 'package:earplug/screens/org_dash.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

void main() {
  testWidgets('band setup launches Stripe and immediately shows onboarding', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );
    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);

    expect(harness.app.bandPayoutStatus?.state, StripeAccountState.none);
    expect(find.byKey(const Key('band-payouts-status')), findsOneWidget);
    expect(find.byKey(const Key('band-payouts-history')), findsOneWidget);
    expect(find.text('No payouts yet.'), findsOneWidget);
    expectNoFieldInCard(tester);

    await tester.tap(find.byKey(const Key('band-payouts-setup')));
    await tester.pumpAndSettle();

    expect(launched, ['https://demo.stripe/onboard/b1']);
    expect(harness.app.bandPayoutStatus?.state, StripeAccountState.onboarding);
    expect(find.text('Finish your Stripe setup'), findsOneWidget);
    expect(find.text('CONTINUE SETUP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('band-payouts-setup')));
    await tester.pumpAndSettle();
    expect(launched, hasLength(2));
  });

  testWidgets('Stripe return enables payouts and the Express dashboard', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    await repository.startBandOnboarding('b1');
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );
    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);

    await tester.tap(find.byKey(const Key('band-payouts-refresh')));
    await tester.pumpAndSettle();
    expect(harness.app.bandPayoutStatus?.state, StripeAccountState.onboarding);

    await harness.app.handleStripeReturn(band: true, id: 'b1');
    await tester.pumpAndSettle();
    expect(harness.app.bandPayoutStatus?.state, StripeAccountState.enabled);
    expect(find.text('PAYOUTS ENABLED'), findsOneWidget);

    await tester.tap(find.byKey(const Key('band-payouts-refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('band-payouts-dashboard')));
    await tester.pumpAndSettle();
    expect(launched, ['https://demo.stripe/dashboard/b1']);
  });

  testWidgets(
    'payout history shows scheduled dates, kinds, amounts and holds',
    (tester) async {
      final auth = FakeAuthService();
      await pumpApp(
        tester,
        auth: auth,
        repository: _PayoutRepository(auth: auth),
        home: const Scaffold(body: BandPayoutsScreen()),
        beforePump: (app) => app.switchToBand('b1'),
      );

      final paidRow = find.byKey(const ValueKey('band-payout-p1'));
      expect(paidRow, findsOneWidget);
      expect(
        find.descendant(of: paidRow, matching: find.text('Sat Aug 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: paidRow,
          matching: find.text(r'Completion payout · $120.00'),
        ),
        findsOneWidget,
      );
      final paidPill = tester.widget<StatusPill>(
        find.descendant(of: paidRow, matching: find.byType(StatusPill)),
      );
      expect(paidPill.label, 'paid');
      expect(paidPill.tone, EpStatusPillTone.success);

      final heldRow = find.byKey(const ValueKey('band-payout-p2'));
      expect(
        find.descendant(
          of: heldRow,
          matching: find.text(r'Forfeited payout · $40.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('Waiting for bank details'), findsOneWidget);
      expect(
        find.descendant(
          of: paidRow,
          matching: find.text('Waiting for bank details'),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<StatusPill>(
              find.descendant(of: heldRow, matching: find.byType(StatusPill)),
            )
            .tone,
        EpStatusPillTone.warning,
      );
      expectNoFieldInCard(tester);
    },
  );

  testWidgets('band onboarding errors appear inline and clear on retry', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );
    harness.app.hostedUrlLauncher = (_) async {
      throw StateError('Could not open Stripe');
    };
    await tester.tap(find.byKey(const Key('band-payouts-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-payouts-error')), findsOneWidget);
    expect(find.textContaining('Could not open Stripe'), findsOneWidget);

    harness.app.hostedUrlLauncher = (_) async {};
    await tester.tap(find.byKey(const Key('band-payouts-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-payouts-error')), findsNothing);
    expect(find.text('CONTINUE SETUP'), findsOneWidget);
  });

  testWidgets('band dashboard errors from the repository appear inline', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _StripeStatusRepository(
        auth: auth,
        state: StripeAccountState.enabled,
      ),
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );

    // The displayed status is enabled, but the demo account is still disabled.
    await tester.tap(find.byKey(const Key('band-payouts-dashboard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-payouts-error')), findsOneWidget);
    expect(find.textContaining('Finish Stripe setup first'), findsOneWidget);
  });

  for (final (state, caption) in [
    (StripeAccountState.none, 'Set up payouts'),
    (StripeAccountState.unknown, 'Set up payouts'),
    (StripeAccountState.onboarding, 'Finish setup'),
    (StripeAccountState.restricted, 'Finish setup'),
    (StripeAccountState.enabled, 'Enabled'),
  ]) {
    testWidgets('band payouts tile shows ${state.name} and opens payouts', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: _StripeStatusRepository(auth: auth, state: state),
        home: const Scaffold(body: BandDashScreen()),
        beforePump: (app) => app.switchToBand('b1'),
      );

      final tile = find.byKey(const Key('band-dash-payouts'));
      await tester.scrollUntilVisible(
        tile,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text(caption)),
        findsOneWidget,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.bandPayouts);
    });
  }

  testWidgets('band members do not see the payouts tile', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _NonOwnerRepository(auth: auth),
      home: const Scaffold(body: BandDashScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );

    expect(find.text('MANAGING · MEMBER'), findsOneWidget);
    expect(find.byKey(const Key('band-dash-payouts')), findsNothing);
  });

  testWidgets('organization owner can set up Stripe and open its dashboard', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: OrgSettingsScreen()),
      beforePump: (app) => app.switchToOrganization('org1'),
    );
    await enterOrganizer(tester, harness, 'org1');
    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);

    await tester.scrollUntilVisible(
      find.byKey(const Key('org-settings-stripe-refresh')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('org-settings-stripe')), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expectNoFieldInCard(tester);

    await tester.tap(find.byKey(const Key('org-settings-stripe-setup')));
    await tester.pumpAndSettle();
    expect(launched, ['https://demo.stripe/onboard/org1']);
    expect(find.text('Setup in progress'), findsOneWidget);
    expect(find.text('CONTINUE SETUP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('org-settings-stripe-refresh')));
    await tester.pumpAndSettle();
    expect(
      harness.app.organizationStripeStatus?.state,
      StripeAccountState.onboarding,
    );

    await harness.app.handleStripeReturn(band: false, id: 'org1');
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('org-settings-stripe-dashboard')));
    await tester.pumpAndSettle();
    expect(launched.last, 'https://demo.stripe/dashboard/org1');
  });

  testWidgets('organization managers do not see the owner Stripe section', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _NonOwnerRepository(auth: auth),
      home: const Scaffold(body: OrgSettingsScreen()),
      beforePump: (app) => app.switchToOrganization('org1'),
    );
    await enterOrganizer(tester, harness, 'org1');
    expect(harness.app.organizerRoleFor('org1'), OrganizationRole.manager);
    await tester.scrollUntilVisible(
      find.byKey(const Key('org-settings-deactivate')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('org-settings-stripe')), findsNothing);
    expect(find.byKey(const Key('org-settings-stripe-setup')), findsNothing);
  });

  testWidgets('organization Stripe errors are separate from save feedback', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: OrgSettingsScreen()),
      beforePump: (app) => app.switchToOrganization('org1'),
    );
    await enterOrganizer(tester, harness, 'org1');
    harness.app.hostedUrlLauncher = (_) async {
      throw StateError('Could not open Stripe');
    };
    await tester.scrollUntilVisible(
      find.byKey(const Key('org-settings-stripe-refresh')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('org-settings-stripe-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-settings-stripe-error')), findsOneWidget);
    expect(find.textContaining('Could not open Stripe'), findsOneWidget);
    expect(find.byKey(const Key('org-settings-save-error')), findsNothing);

    harness.app.hostedUrlLauncher = (_) async {};
    await tester.tap(find.byKey(const Key('org-settings-stripe-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-settings-stripe-error')), findsNothing);
    expect(find.text('Setup in progress'), findsOneWidget);
  });

  for (final band in [true, false]) {
    testWidgets('${band ? 'band' : 'organization'} lists Stripe requirements', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: _StripeStatusRepository(
          auth: auth,
          state: StripeAccountState.restricted,
        ),
        home: Scaffold(
          body: band ? const BandPayoutsScreen() : const OrgSettingsScreen(),
        ),
        beforePump: (app) =>
            band ? app.switchToBand('b1') : app.switchToOrganization('org1'),
      );
      if (!band) await enterOrganizer(tester, harness, 'org1');
      await tester.scrollUntilVisible(
        find.text('CONTINUE SETUP'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('individual.verification.document'), findsOneWidget);
      expect(find.text('external_account'), findsOneWidget);
      expect(
        find.text(band ? 'Stripe needs more information' : 'Needs information'),
        findsOneWidget,
      );
    });
  }

  for (final complete in [false, true]) {
    testWidgets('organization Stripe readiness links when complete=$complete', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: _ReadinessRepository(auth: auth, complete: complete),
        home: const Scaffold(body: OrgDashScreen()),
        beforePump: (app) => app.switchToOrganization('org1'),
      );
      await enterOrganizer(tester, harness, 'org1');

      expect(find.text('Stripe setup arrives with bookings'), findsNothing);
      for (final key in [
        'org-dash-readiness-stripe',
        'org-dash-readiness-payouts',
      ]) {
        final row = find.byKey(Key(key));
        if (complete) {
          expect(row, findsNothing);
        } else {
          expect(row, findsOneWidget);
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(harness.app.current.screen, Screen.orgSettings);
          harness.app.resetTo(Screen.orgDash);
          await tester.pumpAndSettle();
        }
      }
      expect(find.text('Stripe details'), findsOneWidget);
      expect(find.text('Payouts enabled'), findsOneWidget);
    });
  }
}

class _PayoutRepository extends DemoRepository {
  _PayoutRepository({required super.auth});

  @override
  Future<List<Payout>> payoutsForBand(String bandId) async => [
    Payout(
      id: 'p1',
      kind: PayoutKind.completion,
      amountMinor: 12000,
      currency: 'usd',
      status: PayoutStatus.paid,
      scheduledFor: DateTime(2026, 8, 1),
      paidAt: DateTime(2026, 8, 2),
    ),
    Payout(
      id: 'p2',
      kind: PayoutKind.forfeit,
      amountMinor: 4000,
      currency: 'usd',
      status: PayoutStatus.held,
      scheduledFor: DateTime(2026, 8, 3),
      holdReason: 'Waiting for bank details',
    ),
  ];
}

class _StripeStatusRepository extends DemoRepository {
  _StripeStatusRepository({
    required super.auth,
    required StripeAccountState state,
  }) : status = StripeAccountStatus(
         state: state,
         hasAccount: state != StripeAccountState.none,
         chargesEnabled: state == StripeAccountState.enabled,
         payoutsEnabled: state == StripeAccountState.enabled,
         detailsSubmitted: state == StripeAccountState.enabled,
         requirementsDue: state == StripeAccountState.restricted
             ? const ['individual.verification.document', 'external_account']
             : const [],
       );

  final StripeAccountStatus status;

  @override
  Future<StripeAccountStatus> bandPayoutStatus(String bandId) async => status;

  @override
  Future<StripeAccountStatus> organizationStripeStatus(
    String organizationId,
  ) async => status;
}

class _NonOwnerRepository extends DemoRepository {
  _NonOwnerRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() => Stream.value([
    BandMembership(band: DemoData.bands['b1']!, role: 'member'),
  ]);

  @override
  Stream<List<OrganizationMembership>> myOrganizations() => Stream.value([
    OrganizationMembership(
      organization: DemoData.organizations['org1']!,
      role: OrganizationRole.manager,
    ),
  ]);
}

class _ReadinessRepository extends DemoRepository {
  _ReadinessRepository({required super.auth, required this.complete});

  final bool complete;

  @override
  Future<OrganizationDashboard> organizationDashboard(
    String organizationId,
  ) async {
    final dashboard = await super.organizationDashboard(organizationId);
    return OrganizationDashboard(
      organization: dashboard.organization,
      role: dashboard.role,
      viaPlatformAdmin: dashboard.viaPlatformAdmin,
      verification: OrganizationVerification(
        verified: dashboard.verification.verified,
        stripeDetailsSubmitted: complete,
        stripeChargesEnabled: complete,
        stripePayoutsEnabled: complete,
        profileComplete: dashboard.verification.profileComplete,
        teamInvited: dashboard.verification.teamInvited,
      ),
      venues: dashboard.venues,
      memberCount: dashboard.memberCount,
      privateDetails: dashboard.privateDetails,
    );
  }
}
