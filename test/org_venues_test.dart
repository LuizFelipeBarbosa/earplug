import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/org_venues.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('owner sees a venue request and can approve it', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgVenuesScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    final row = find.byKey(const Key('venue-request-consent-1'));
    expect(row, findsOneWidget);
    expect(tester.widget(row), isA<EpCard>());
    expect(find.text('VENUE REQUESTS'), findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.text('Night Shift at The Foghorn Club'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(DemoData.organizations['org3']!.name),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('The Foghorn Club')),
      findsOneWidget,
    );
    expect(find.text('PENDING APPROVAL'), findsOneWidget);
    expect(
      find.byKey(const Key('venue-request-approve-consent-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('venue-request-decline-consent-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('venue-request-approve-consent-1')));
    await tester.pumpAndSettle();

    expect(find.text('APPROVED'), findsOneWidget);
    expect(
      find.byKey(const Key('venue-request-revoke-consent-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('venue-request-approve-consent-1')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('venue-request-decline-consent-1')),
      findsNothing,
    );
    expect(
      (await repository.venueConsentForOpportunity('opp-promoter'))?.status,
      VenueConsentStatus.granted,
    );
  });

  for (final note in ['', 'The venue is unavailable.']) {
    testWidgets(
      'declining a venue request ${note.isEmpty ? 'without' : 'with'} a note removes it',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final repository = DemoRepository(auth: auth);
        final harness = await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          beforePump: (app) => app.switchToOrganization('org1'),
          home: const Scaffold(body: OrgVenuesScreen()),
        );
        await enterOrganizer(tester, harness, 'org1');

        await tester.tap(
          find.byKey(const Key('venue-request-decline-consent-1')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(EpFormSheet), findsOneWidget);
        expectNoFieldInCard(tester);
        if (note.isNotEmpty) {
          await tester.enterText(
            find.byKey(const Key('venue-request-note')),
            note,
          );
        }
        await tester.tap(find.byKey(const Key('venue-request-note-submit')));
        await tester.pumpAndSettle();

        expect(find.byType(EpFormSheet), findsNothing);
        expect(find.byKey(const Key('venue-request-consent-1')), findsNothing);
        expect(find.text('VENUE REQUESTS'), findsNothing);
        expect(find.byKey(const ValueKey('org-venue-v1')), findsOneWidget);
        final consent = await repository.venueConsentForOpportunity(
          'opp-promoter',
        );
        expect(consent?.status, VenueConsentStatus.declined);
        expect(consent?.note, note.isEmpty ? isNull : note);
      },
    );
  }

  testWidgets('revoking approval warns the owner and saves the note', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    await repository.decideVenueConsent(consentId: 'consent-1', granted: true);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgVenuesScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    await tester.tap(find.byKey(const Key('venue-request-revoke-consent-1')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Revoking cancels the event if it is already open. After a confirmed booking, contact EarPlug support.',
      ),
      findsOneWidget,
    );
    expectNoFieldInCard(tester);
    await tester.enterText(
      find.byKey(const Key('venue-request-note')),
      '  The venue needs repairs.  ',
    );
    await tester.tap(find.byKey(const Key('venue-request-note-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(EpFormSheet), findsNothing);
    expect(find.byKey(const Key('venue-request-consent-1')), findsNothing);
    final consent = await repository.venueConsentForOpportunity('opp-promoter');
    expect(consent?.status, VenueConsentStatus.revoked);
    expect(consent?.note, 'The venue needs repairs.');
  });

  for (final role in [OrganizationRole.finance, OrganizationRole.door]) {
    for (final granted in [false, true]) {
      testWidgets(
        '${role.name} sees ${granted ? 'approved' : 'pending'} requests without actions',
        (tester) async {
          final auth = FakeAuthService();
          await auth.signInDemo();
          final repository = DemoRepository(auth: auth);
          if (granted) {
            await repository.decideVenueConsent(
              consentId: 'consent-1',
              granted: true,
            );
          }
          final harness = await pumpApp(
            tester,
            auth: auth,
            repository: repository,
            beforePump: (app) => app.switchToOrganization('org1'),
            home: const Scaffold(body: OrgVenuesScreen()),
          );
          harness.app.myOrganizations = [
            OrganizationMembership(
              organization: DemoData.organizations['org1']!,
              role: role,
            ),
          ];
          await enterOrganizer(tester, harness, 'org1');

          expect(
            find.byKey(const Key('venue-request-consent-1')),
            findsOneWidget,
          );
          expect(
            find.text(granted ? 'APPROVED' : 'PENDING APPROVAL'),
            findsOneWidget,
          );
          for (final action in ['approve', 'decline', 'revoke']) {
            expect(
              find.byKey(Key('venue-request-$action-consent-1')),
              findsNothing,
            );
          }
        },
      );
    }
  }

  testWidgets('request load failure uses the venues retry path', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..failOnce(
        'venueConsentsForOrganization',
        StateError('Could not load venue requests'),
      );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgVenuesScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(find.text('Could not load venues.'), findsOneWidget);
    expect(find.byKey(const Key('venue-request-consent-1')), findsNothing);
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load venues.'), findsNothing);
    expect(find.byKey(const Key('venue-request-consent-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('org-venue-v1')), findsOneWidget);
  });
}
