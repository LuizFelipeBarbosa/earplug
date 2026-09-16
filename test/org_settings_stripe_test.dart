import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  for (final (state, label, tone) in [
    (StripeAccountState.none, 'SET UP', EpStatusPillTone.attention),
    (
      StripeAccountState.onboarding,
      'SETUP IN PROGRESS — FINISH IN STRIPE',
      EpStatusPillTone.attention,
    ),
    (
      StripeAccountState.restricted,
      'SETUP IN PROGRESS — FINISH IN STRIPE',
      EpStatusPillTone.attention,
    ),
    (StripeAccountState.enabled, 'CONNECTED', EpStatusPillTone.success),
  ]) {
    testWidgets('Stripe row pill reads $label when ${state.name}', (
      tester,
    ) async {
      await _pumpHub(tester, stripeState: state);

      final row = find.byKey(const Key('org-hub-stripe'));
      await _reveal(tester, row);
      final pill = tester.widget<StatusPill>(
        find.descendant(of: row, matching: find.byType(StatusPill)),
      );
      expect(pill.label.toUpperCase(), label);
      expect(pill.tone, tone);
    });
  }

  testWidgets('Stripe row opens finance; tax row reflects Stripe details', (
    tester,
  ) async {
    final harness = await _pumpHub(
      tester,
      stripeState: StripeAccountState.enabled,
    );

    final tax = find.byKey(const Key('org-hub-tax'));
    await _reveal(tester, tax);
    final taxPill = tester.widget<StatusPill>(
      find.descendant(of: tax, matching: find.byType(StatusPill)),
    );
    expect(taxPill.label.toUpperCase(), '✓ COLLECTED VIA STRIPE');
    expect(taxPill.tone, EpStatusPillTone.success);

    await tester.tap(find.byKey(const Key('org-hub-stripe')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgFinance);
  });

  testWidgets('tax row flags missing tax details and surfaces open errors', (
    tester,
  ) async {
    final harness = await _pumpHub(
      tester,
      stripeState: StripeAccountState.restricted,
      requirementsDue: const ['individual.id_number'],
      detailsSubmitted: true,
    );

    final tax = find.byKey(const Key('org-hub-tax'));
    await _reveal(tester, tax);
    final taxPill = tester.widget<StatusPill>(
      find.descendant(of: tax, matching: find.byType(StatusPill)),
    );
    expect(taxPill.label.toUpperCase(), 'ACTION NEEDED');
    expect(taxPill.tone, EpStatusPillTone.attention);

    harness.app.hostedUrlLauncher = (_) async {
      throw StateError('Could not open Stripe');
    };
    await tester.tap(tax);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-settings-stripe-error')), findsOneWidget);
    expect(find.byKey(const Key('org-settings-save-error')), findsNothing);

    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);
    await tester.tap(tax);
    await tester.pumpAndSettle();
    expect(launched, ['https://demo.stripe/dashboard/org1']);
    expect(find.byKey(const Key('org-settings-stripe-error')), findsNothing);
  });

  testWidgets('no save bar renders on the hub', (tester) async {
    await _pumpHub(tester, stripeState: StripeAccountState.none);

    expect(find.byType(StickyActionBar), findsNothing);
    expect(find.byKey(const Key('org-settings-save')), findsNothing);
    await tester.drag(_pageScrollable(), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byType(StickyActionBar), findsNothing);
  });
}

Future<AppHarness> _pumpHub(
  WidgetTester tester, {
  required StripeAccountState stripeState,
  List<String> requirementsDue = const [],
  bool? detailsSubmitted,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final repository = _StripeStateRepository(
    auth: auth,
    state: stripeState,
    requirementsDue: requirementsDue,
    detailsSubmitted:
        detailsSubmitted ?? stripeState == StripeAccountState.enabled,
  );
  // The demo dashboard link only resolves once the account exists.
  if (stripeState != StripeAccountState.none) {
    await repository.refreshOrganizationAccountStatus('org1');
  }
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: repository,
    beforePump: (app) => app.switchToOrganization('org1'),
    home: const Scaffold(body: OrgSettingsScreen()),
  );
  await enterOrganizer(tester, harness, 'org1');
  return harness;
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 250, scrollable: _pageScrollable());
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Finder _pageScrollable() => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

/// Demo data with the organization's Stripe account held in one fixed state.
class _StripeStateRepository extends DemoRepository {
  _StripeStateRepository({
    required super.auth,
    required this.state,
    required this.requirementsDue,
    required this.detailsSubmitted,
  });

  final StripeAccountState state;
  final List<String> requirementsDue;
  final bool detailsSubmitted;

  @override
  Future<StripeAccountStatus> organizationStripeStatus(
    String organizationId,
  ) async => StripeAccountStatus(
    state: state,
    hasAccount: state != StripeAccountState.none,
    chargesEnabled: state == StripeAccountState.enabled,
    payoutsEnabled: state == StripeAccountState.enabled,
    detailsSubmitted: detailsSubmitted,
    requirementsDue: requirementsDue,
  );
}
