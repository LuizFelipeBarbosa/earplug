import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  for (final (state, label, tone) in [
    (StripeAccountState.none, 'SET UP', EpStatusPillTone.attention),
    (StripeAccountState.onboarding, 'SET UP', EpStatusPillTone.attention),
    (StripeAccountState.enabled, 'CONNECTED', EpStatusPillTone.success),
  ]) {
    testWidgets('Stripe section badge reads $label when ${state.name}', (
      tester,
    ) async {
      final harness = await _pumpSettings(tester, stripeState: state);

      final badge = find.byKey(const Key('org-settings-stripe-badge'));
      await tester.scrollUntilVisible(
        badge,
        250,
        scrollable: _pageScrollable(harness),
      );
      final pill = tester.widget<StatusPill>(badge);
      expect(pill.label, label);
      expect(pill.tone, tone);
    });
  }

  testWidgets('save bar stays pinned above the tab bar while scrolling', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      stripeState: StripeAccountState.none,
    );

    final save = find.byKey(const Key('org-settings-save'));
    expect(save, findsOneWidget);
    final before = tester.getRect(save);
    // 900 logical px tall phone surface, 66 px tab bar below the bar.
    expect(before.bottom, closeTo(900 - 66, 1));
    expect(before.left, 0);
    expect(before.width, 402);

    await tester.drag(_pageScrollable(harness), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(tester.getRect(save), before);
  });
}

Future<AppHarness> _pumpSettings(
  WidgetTester tester, {
  required StripeAccountState stripeState,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: _StripeStateRepository(auth: auth, state: stripeState),
    beforePump: (app) => app.switchToOrganization('org1'),
    home: const Scaffold(body: OrgSettingsScreen()),
  );
  await enterOrganizer(tester, harness, 'org1');
  return harness;
}

Finder _pageScrollable(AppHarness harness) => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

/// Demo data with the organization's Stripe account held in one fixed state.
class _StripeStateRepository extends DemoRepository {
  _StripeStateRepository({required super.auth, required this.state});

  final StripeAccountState state;

  @override
  Future<StripeAccountStatus> organizationStripeStatus(
    String organizationId,
  ) async => StripeAccountStatus(
    state: state,
    hasAccount: state != StripeAccountState.none,
    chargesEnabled: state == StripeAccountState.enabled,
    payoutsEnabled: state == StripeAccountState.enabled,
    detailsSubmitted: state == StripeAccountState.enabled,
    requirementsDue: const [],
  );
}
