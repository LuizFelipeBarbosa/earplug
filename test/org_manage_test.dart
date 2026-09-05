import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/org_dash.dart';
import 'package:earplug/screens/org_join.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/screens/org_team.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
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
    expect(
      stats,
      contains(
        isA<EpStatCard>()
            .having((card) => card.label, 'label', 'OPPORTUNITIES')
            .having((card) => card.value, 'value', '2')
            .having((card) => card.caption, 'caption', 'open right now'),
      ),
    );

    await tester.tap(find.byKey(const Key('org-dash-stat-opportunities')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.orgOpportunities);
  });

  testWidgets('organizer dashboard opens a new opportunity draft', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: OrgDashScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(find.text('Post a slot for artists'), findsOneWidget);
    final command = find.byKey(const Key('org-dash-command-opportunity'));
    await tester.ensureVisible(command);
    await tester.tap(command);
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'new');
  });

  for (final role in [OrganizationRole.finance, OrganizationRole.door]) {
    testWidgets('${role.name} cannot post opportunities from the dashboard', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: OrgDashScreen()),
      );
      await enterOrganizer(tester, harness, 'org1');
      harness.app.myOrganizations = [
        OrganizationMembership(
          organization: DemoData.organizations['org1']!,
          role: role,
        ),
      ];
      await enterOrganizer(tester, harness, 'org1');

      expect(find.text('Managers post opportunities'), findsOneWidget);
      final command = find.byKey(const Key('org-dash-command-opportunity'));
      await tester.ensureVisible(command);
      await tester.tap(command);
      await tester.pumpAndSettle();

      expect(harness.app.current.screen, Screen.orgDash);
    });
  }

  testWidgets('venue edit page saves the public profile', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const RootShell(),
    );
    await enterOrganizer(tester, harness, 'org1');

    await tester.tap(find.byKey(const Key('org-dash-command-venues')));
    await tester.pumpAndSettle();

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
    expect(find.text('The Foghorn Club'), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('org-venue-public-name')))
          .controller
          ?.text,
      demoVenue.name,
    );
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
    expect(
      find.ancestor(of: find.byType(TextField), matching: find.byType(EpCard)),
      findsNothing,
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
    final clubChip = find.byKey(const Key('org-venue-type-club'));
    await tester.tap(clubChip);
    await tester.enterText(
      find.byKey(const Key('org-venue-public-capacity')),
      '220',
    );
    final save = find.byKey(const Key('org-venue-save'));
    await tester.tap(save);
    await tester.pumpAndSettle();

    final savedVenue = await repository.resolveVenue('v1');
    expect(savedVenue?.name, 'Foghorn Hall');
    expect(savedVenue?.description, updatedDescription);
    expect(savedVenue?.venueType, VenueType.club);
    expect(savedVenue?.capacityPublic, 220);
    expect(find.byKey(const Key('org-venue-save-success')), findsOneWidget);
  });

  testWidgets('venue location autocomplete saves and disclosure can change', (
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
      home: const RootShell(),
    );
    await enterOrganizer(tester, harness, 'org1');

    await tester.tap(find.byKey(const Key('org-dash-command-venues')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('org-venue-v1')));
    await tester.pumpAndSettle();
    final pageScrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    final addressFinder = find.byKey(const Key('org-venue-private-address'));
    await tester.scrollUntilVisible(
      addressFinder,
      250,
      scrollable: pageScrollable,
    );
    final address = tester.widget<TextField>(addressFinder);
    expect(address.controller?.text, DemoData.venuePrivateDetails['v1']!.addr);
    expect(find.text('Tap the map to adjust the pin'), findsOneWidget);

    await tester.enterText(addressFinder, '22 V');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final suggestion = find.byKey(const Key('org-venue-private-suggestion-0'));
    await tester.ensureVisible(suggestion);
    await tester.pump();
    await tester.tap(suggestion);
    await tester.pump();

    await tester.tap(find.byKey(const Key('org-venue-save')));
    await tester.pumpAndSettle();

    final privateDetails = await repository.venuePrivateDetails('v1');
    expect(privateDetails?.addr, '22 Valencia St');
    expect(privateDetails?.capacity, 180);

    final disclosure = find.byKey(const Key('org-venue-disclosure'));
    expect(tester.widget<SwitchRow>(disclosure).value, isFalse);
    await tester.scrollUntilVisible(
      disclosure,
      300,
      scrollable: pageScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show exact address publicly'));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchRow>(disclosure).value, isTrue);
    final venue = await repository.resolveVenue('v1');
    expect(venue?.disclosure, AddressDisclosure.public);
    expect(venue?.exactAddress, '22 Valencia St');
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

  testWidgets('organization public and private settings save together', (
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
    final pageScrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    final legalName = find.byKey(const Key('org-settings-legal-name'));
    await tester.scrollUntilVisible(legalName, 250, scrollable: pageScrollable);
    await tester.enterText(legalName, 'Foghorn Collective LLC');
    expect(
      find.ancestor(of: find.byType(TextField), matching: find.byType(EpCard)),
      findsNothing,
    );

    final save = find.byKey(const Key('org-settings-save'));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect((await repository.organization('org1'))?.name, 'Foghorn Collective');
    expect(
      (await repository.organizationDashboard(
        'org1',
      )).privateDetails?.legalName,
      'Foghorn Collective LLC',
    );
    expect(find.byKey(const Key('org-settings-save-success')), findsOneWidget);
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
