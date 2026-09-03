import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/org_dash.dart';
import 'package:earplug/screens/org_join.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/screens/org_team.dart';
import 'package:earplug/screens/org_venues.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('organizer dashboard shows verification and demo counts', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgDashScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(find.byKey(const Key('org-dash-verification')), findsOneWidget);
    final stats = tester
        .widgetList<EpStatCard>(find.byType(EpStatCard))
        .toList();
    expect(
      stats,
      contains(
        isA<EpStatCard>()
            .having((card) => card.label, 'label', 'VENUES')
            .having((card) => card.value, 'value', '1'),
      ),
    );
    expect(
      stats,
      contains(
        isA<EpStatCard>()
            .having((card) => card.label, 'label', 'MEMBERS')
            .having((card) => card.value, 'value', '2'),
      ),
    );
  });

  testWidgets('venue public profile saves and refreshes the venue list', (
    tester,
  ) async {
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

    final venueCard = find.byKey(const ValueKey('org-venue-v1'));
    expect(venueCard, findsOneWidget);
    expect(
      find.descendant(
        of: venueCard,
        matching: find.text('Mission, San Francisco'),
      ),
      findsWidgets,
    );

    await tester.tap(venueCard);
    await tester.pumpAndSettle();
    final demoVenue = DemoData.venues['v1']!;
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('org-venue-public-description')),
          )
          .controller
          ?.text,
      demoVenue.description,
    );
    expect(
      tester.widget<EpChip>(find.byKey(const Key('org-venue-type-bar'))).active,
      isTrue,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('org-venue-public-capacity')))
          .controller
          ?.text,
      demoVenue.capacityPublic!.toString(),
    );

    await tester.enterText(
      find.byKey(const Key('org-venue-public-name')),
      'Foghorn Hall',
    );
    const updatedDescription = 'A lively neighborhood room for local music.';
    await tester.enterText(
      find.byKey(const Key('org-venue-public-description')),
      updatedDescription,
    );
    final sheetScrollable = find
        .descendant(
          of: find.byType(EpSheetShell),
          matching: find.byType(Scrollable),
        )
        .first;
    final clubChip = find.byKey(const Key('org-venue-type-club'));
    await tester.scrollUntilVisible(clubChip, 100, scrollable: sheetScrollable);
    await tester.tap(clubChip);
    await tester.enterText(
      find.byKey(const Key('org-venue-public-capacity')),
      '220',
    );
    final save = find.byKey(const Key('org-venue-save-public'));
    await tester.scrollUntilVisible(save, 250, scrollable: sheetScrollable);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final refreshedCard = find.byKey(const ValueKey('org-venue-v1'));
    expect(
      find.descendant(of: refreshedCard, matching: find.text('Foghorn Hall')),
      findsOneWidget,
    );
    final savedVenue = await repository.resolveVenue('v1');
    expect(savedVenue?.name, 'Foghorn Hall');
    expect(savedVenue?.description, updatedDescription);
    expect(savedVenue?.venueType, VenueType.club);
    expect(savedVenue?.capacityPublic, 220);
  });

  testWidgets('venue private location is seeded and disclosure can change', (
    tester,
  ) async {
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

    await tester.tap(find.byKey(const ValueKey('org-venue-v1')));
    await tester.pumpAndSettle();
    final address = tester.widget<TextField>(
      find.byKey(const Key('org-venue-private-address')),
    );
    expect(address.controller?.text, DemoData.venuePrivateDetails['v1']!.addr);

    final disclosure = find.byKey(const Key('org-venue-disclosure'));
    expect(tester.widget<SwitchRow>(disclosure).value, isFalse);
    await tester.scrollUntilVisible(
      disclosure,
      300,
      scrollable: find
          .descendant(
            of: find.byType(EpSheetShell),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show exact address publicly'));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchRow>(disclosure).value, isTrue);
    final venue = await repository.resolveVenue('v1');
    expect(venue?.disclosure, AddressDisclosure.public);
    expect(venue?.exactAddress, DemoData.venuePrivateDetails['v1']!.addr);
  });

  testWidgets('team lists members and creates a role-specific invite', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgTeamScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(
      find.byKey(const ValueKey('org-team-member-demo-user')),
      findsOneWidget,
    );
    expect(find.textContaining('Mara Kim'), findsOneWidget);

    final financeRole = find.byKey(
      const ValueKey('org-team-invite-role-finance'),
    );
    await tester.ensureVisible(financeRole);
    await tester.pump();
    await tester.tap(financeRole);
    await tester.pump();
    expect(tester.widget<EpChip>(financeRole).active, isTrue);

    final create = find.byKey(const Key('org-team-invite-create'));
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(find.textContaining('/apply/'), findsOneWidget);
    expect(
      (await repository.organizationInvite('org1'))?.role,
      OrganizationRole.finance,
    );
  });

  testWidgets('removing the last owner surfaces the repository error', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _LastOwnerGuardRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgTeamScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    await tester.tap(find.byKey(const ValueKey('org-team-member-demo-user')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'REMOVE'));
    await tester.pumpAndSettle();

    expect(harness.app.toast, contains('at least one owner'));
  });

  testWidgets('organization public profile saves through settings', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgSettingsScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    await tester.enterText(
      find.byKey(const Key('org-settings-name')),
      'Foghorn Collective',
    );
    final save = find.byKey(const Key('org-settings-save-profile'));
    await tester.scrollUntilVisible(
      save,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect((await repository.organization('org1'))?.name, 'Foghorn Collective');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('org-settings-name')))
          .controller
          ?.text,
      'Foghorn Collective',
    );
  });

  testWidgets('organization invite can be accepted and opens organizer mode', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final invite = await repository.createOrganizationInvite(
      organizationId: 'org1',
      role: OrganizationRole.manager,
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: Scaffold(body: OrgJoinScreen(token: invite.token)),
    );
    await enterOrganizer(tester, harness, 'org1');

    final accept = find.byKey(const Key('org-join-accept'));
    expect(accept, findsOneWidget);
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(harness.app.organizationId, 'org1');
    expect(harness.app.currentOrganization, isNotNull);
  });
}

class _LastOwnerGuardRepository extends DemoRepository {
  _LastOwnerGuardRepository({required super.auth});

  @override
  Future<void> removeOrganizationMember({
    required String organizationId,
    required String userId,
  }) async {
    final members = await organizationMembers(organizationId);
    final target = members
        .where((member) => member.userId == userId)
        .firstOrNull;
    final owners = members.where(
      (member) => member.role == OrganizationRole.owner,
    );
    if (target?.role == OrganizationRole.owner && owners.length <= 1) {
      throw StateError('Organizations need at least one owner.');
    }
    return super.removeOrganizationMember(
      organizationId: organizationId,
      userId: userId,
    );
  }
}
