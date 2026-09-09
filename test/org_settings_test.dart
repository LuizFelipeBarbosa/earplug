import 'package:earplug/models.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  for (final (description, requirementsDue, needsTaxInformation) in [
    ('ID number', ['external_account', 'individual.id_number'], true),
    ('SSN', ['individual.ssn_last_4'], true),
    ('tax ID', ['company.tax_id'], true),
    ('verification document', ['individual.verification.document'], true),
    ('no requirements', <String>[], false),
    ('non-tax requirement', ['external_account'], false),
  ]) {
    testWidgets('organization tax row handles $description', (tester) async {
      final auth = FakeAuthService();
      final detailsSubmitted = requirementsDue.isEmpty;
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: _stripeStatusRepository(
          auth: auth,
          state: detailsSubmitted
              ? StripeAccountState.enabled
              : StripeAccountState.restricted,
          detailsSubmitted: detailsSubmitted,
          requirementsDue: requirementsDue,
        ),
        home: const Scaffold(body: OrgSettingsScreen()),
        beforePump: (app) => app.switchToOrganization('org1'),
      );
      await enterOrganizer(tester, harness, 'org1');

      final row = find.byKey(const Key('stripe-tax-row'));
      await tester.scrollUntilVisible(
        row,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('org-settings-stripe')),
          matching: row,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('TAX DETAILS')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            'Stripe collects your tax information (W-9 / 1099) during onboarding. '
            'Update it in your Stripe dashboard.',
          ),
        ),
        findsOneWidget,
      );
      final pill = find.descendant(of: row, matching: find.byType(StatusPill));
      if (needsTaxInformation) {
        expect(tester.widget<StatusPill>(pill).label, 'ACTION NEEDED');
        expect(tester.widget<StatusPill>(pill).tone, EpStatusPillTone.warning);
      } else {
        expect(pill, findsNothing);
      }
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.check)),
        needsTaxInformation ? findsNothing : findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            'Stripe needs your tax information before payouts continue.',
          ),
        ),
        needsTaxInformation ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('org-settings-tax-dashboard')),
        detailsSubmitted ? findsOneWidget : findsNothing,
      );
      expectNoFieldInCard(tester);
    });
  }

  testWidgets(
    'restricted organization with submitted details can manage tax details and retry errors',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _stripeStatusRepository(
        auth: auth,
        state: StripeAccountState.restricted,
        detailsSubmitted: true,
        requirementsDue: const ['individual.id_number'],
      );
      // Enable the demo dashboard link while the displayed status stays restricted.
      await repository.refreshOrganizationAccountStatus('org1');
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: OrgSettingsScreen()),
        beforePump: (app) => app.switchToOrganization('org1'),
      );
      await enterOrganizer(tester, harness, 'org1');

      final button = find.byKey(const Key('org-settings-tax-dashboard'));
      await tester.scrollUntilVisible(
        button,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: button, matching: find.text('MANAGE IN STRIPE')),
        findsOneWidget,
      );
      harness.app.hostedUrlLauncher = (_) async {
        throw StateError('Could not open Stripe');
      };
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('org-settings-stripe-error')), findsOneWidget);
      expect(find.textContaining('Could not open Stripe'), findsOneWidget);
      expect(find.byKey(const Key('org-settings-save-error')), findsNothing);

      final launched = <String>[];
      harness.app.hostedUrlLauncher = (url) async => launched.add(url);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(launched, ['https://demo.stripe/dashboard/org1']);
      expect(find.byKey(const Key('org-settings-stripe-error')), findsNothing);
      expect(find.byKey(const Key('org-settings-save-error')), findsNothing);
    },
  );
}

StubRepository _stripeStatusRepository({
  required FakeAuthService auth,
  required StripeAccountState state,
  required bool detailsSubmitted,
  required List<String> requirementsDue,
}) {
  return StubRepository(auth: auth)
    ..returns(
      'organizationStripeStatus',
      StripeAccountStatus(
        state: state,
        hasAccount: state != StripeAccountState.none,
        chargesEnabled: state == StripeAccountState.enabled,
        payoutsEnabled: state == StripeAccountState.enabled,
        detailsSubmitted: detailsSubmitted,
        requirementsDue: requirementsDue,
      ),
    );
}
