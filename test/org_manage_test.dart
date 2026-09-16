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
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('organizer dashboard leads with header, readiness and hero', (
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

    expect(find.byKey(const Key('org-dash-header')), findsOneWidget);
    expect(find.textContaining('ORGANIZER · '), findsOneWidget);
    expect(
      tester.widget<EpPill>(find.byKey(const Key('org-dash-discover'))).variant,
      EpPillVariant.accentOutline,
    );
    for (final removed in [
      'org-dash-verification',
      'org-dash-venue-requests',
      'org-dash-stat-members',
      'org-dash-stat-opportunities',
      'org-dash-stat-rating',
      'org-dash-reviews',
    ]) {
      expect(find.byKey(Key(removed)), findsNothing);
    }
    expect(find.textContaining('OPEN SLOTS'), findsNothing);
    expect(find.textContaining('Profile pending'), findsNothing);
    expect(find.textContaining('PROFILE PENDING'), findsNothing);

    // The demo profile is complete and Stripe is not set up: 1 of 2.
    final readiness = find.byKey(const Key('band-readiness'));
    expect(readiness, findsOneWidget);
    expect(
      find.descendant(of: readiness, matching: find.text('1 OF 2')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('org-setup-finance')), findsOneWidget);
    expect(find.byKey(const Key('org-dash-finance-badge')), findsOneWidget);

    // Nothing in the demo is fully booked, so the hero prompts for a post.
    expect(find.byKey(const Key('org-dash-next-event')), findsNothing);
    expect(find.byKey(const Key('org-dash-next-event-empty')), findsOneWidget);
    final post = find.byKey(const Key('org-dash-post-request'));
    await tester.ensureVisible(post);
    await tester.tap(post);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'new');
  });

  testWidgets('next event hero shows the fully booked request and opens it', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final booked = _fullyBooked(DemoData.opportunities['opp1']!);
    final repository = StubRepository(auth: auth)
      ..returnsStream<List<Opportunity>>(
        'watchOrganizationOpportunities',
        () => Stream.value([booked]),
      )
      ..returns('organizationStripeStatus', _enabledStripe);
    final harness = await pumpApp(
      tester,
      size: const Size(390, 844),
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgDashScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    // Profile and finance are both done, so no module and no badge.
    expect(find.byKey(const Key('band-readiness')), findsNothing);
    expect(find.byKey(const Key('org-dash-finance-badge')), findsNothing);
    expect(find.byKey(const Key('org-dash-next-event-empty')), findsNothing);

    final hero = find.byKey(const Key('org-dash-next-event'));
    final heroRect = tester.getRect(hero);
    expect(heroRect.top, greaterThanOrEqualTo(0));
    expect(heroRect.bottom, lessThan(844));
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      0,
    );
    expect(find.text('NEXT EVENT'), findsOneWidget);
    expect(find.byKey(const Key('org-dash-next-event-when')), findsOneWidget);
    expect(
      find.descendant(
        of: hero,
        matching: find.textContaining(
          '${booked.slots.length}/${booked.slots.length} slots booked',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is StatusPill && widget.label == 'Confirmed',
      ),
      findsOneWidget,
    );

    final view = find.byKey(const Key('org-dash-next-event-view'));
    expect(view.hitTestable(), findsOneWidget);
    await tester.tap(view);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.opportunityApplicants);
    expect(harness.app.current.param, 'opp1');
  });

  testWidgets('promoter dashboard hides venue management and keeps team', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org3'),
      home: const Scaffold(body: OrgDashScreen()),
    );
    await enterOrganizer(tester, harness, 'org3');

    expect(find.textContaining('VENUES'), findsNothing);
    expect(find.byKey(const Key('org-dash-venue-requests')), findsNothing);
    expect(find.byKey(const Key('org-dash-command-venues')), findsNothing);
    expect(find.byKey(const Key('org-dash-locations')), findsNothing);
    expect(find.byKey(const Key('org-dash-command-team')), findsOneWidget);
    expect(find.byKey(const Key('org-dash-footer-note')), findsNothing);
  });

  testWidgets('organizer dashboard opens a new opportunity draft', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: OrgDashScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(find.text('POST A SLOT FOR ARTISTS'), findsOneWidget);
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

      expect(
        find.byKey(const Key('org-dash-command-opportunity')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('org-dash-next-event-empty')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('org-dash-post-request')), findsNothing);
      // Readiness is a manager's concern.
      expect(find.byKey(const Key('band-readiness')), findsNothing);
      expect(harness.app.current.screen, Screen.orgOpportunities);
    });
  }

  testWidgets(
    'finance command opens for owners and is hidden for door members',
    (tester) async {
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

      final command = find.byKey(const Key('org-dash-command-finance'));
      await tester.scrollUntilVisible(command, 250);
      expect(command, findsOneWidget);
      expect(
        find.descendant(of: command, matching: find.text('FINANCE')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: command,
          matching: find.byKey(const Key('org-dash-finance-badge')),
        ),
        findsOneWidget,
      );
      await tester.tap(command);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.orgFinance);

      harness.app.myOrganizations = [
        OrganizationMembership(
          organization: DemoData.organizations['org1']!,
          role: OrganizationRole.door,
        ),
      ];
      await enterOrganizer(tester, harness, 'org1');
      expect(command, findsNothing);
    },
  );

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

    await tester.tap(find.byKey(const Key('organizer-tab-venues')));
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

    await _openVenue(tester, venueCard);
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

    await tester.tap(find.byKey(const Key('organizer-tab-venues')));
    await tester.pumpAndSettle();
    await _openVenue(tester, find.byKey(const ValueKey('org-venue-v1')));
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

  testWidgets(
    'hub team section lists members and creates a role-specific invite',
    (tester) async {
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

      final owner = find.byKey(const ValueKey('org-hub-member-demo-user'));
      await _reveal(tester, owner);
      expect(owner, findsOneWidget);
      expect(find.text('MEMBERS · 2'), findsOneWidget);
      expect(find.textContaining('MARA KIM'), findsOneWidget);
      expect(
        tester
            .widget<StatusPill>(
              find.descendant(of: owner, matching: find.byType(StatusPill)),
            )
            .tone,
        EpStatusPillTone.selected,
      );

      final invite = find.byKey(const Key('org-hub-invite'));
      await _reveal(tester, invite);
      await tester.tap(invite);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('org-hub-invite-sheet')), findsOneWidget);

      final financeRole = find.byKey(
        const ValueKey('org-team-invite-role-finance'),
      );
      await tester.tap(financeRole);
      await tester.pump();
      expect(tester.widget<EpChip>(financeRole).active, isTrue);

      await tester.tap(find.byKey(const Key('org-team-invite-create')));
      await tester.pumpAndSettle();

      expect(find.textContaining('/apply/'), findsOneWidget);
      expect(find.byKey(const Key('org-team-invite-copy')), findsOneWidget);
      expect(find.byKey(const Key('org-team-invite-rotate')), findsOneWidget);
      expect(find.byKey(const Key('org-team-invite-revoke')), findsOneWidget);
      expect(
        (await repository.organizationInvite('org1'))?.role,
        OrganizationRole.finance,
      );

      await tester.tap(find.byKey(const Key('org-team-invite-revoke')));
      await tester.pumpAndSettle();
      expect((await repository.organizationInvite('org1'))?.revoked, isTrue);
      expect(find.byKey(const Key('org-team-invite-create')), findsOneWidget);
    },
  );

  testWidgets('hub team section changes a member role from the overflow', (
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

    final actions = find.byKey(
      const ValueKey('org-hub-member-actions-manager1'),
    );
    await _reveal(tester, actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Door'));
    await tester.pumpAndSettle();

    final members = await repository.organizationMembers('org1');
    expect(
      members.singleWhere((member) => member.userId == 'manager1').role,
      OrganizationRole.door,
    );
    expect(harness.app.toast, 'Role updated.');
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
      home: const Scaffold(body: OrgSettingsScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    final actions = find.byKey(
      const ValueKey('org-hub-member-actions-demo-user'),
    );
    await _reveal(tester, actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'REMOVE'));
    await tester.pumpAndSettle();

    expect(harness.app.toast, contains('at least one owner'));
  });

  testWidgets('standalone team screen still renders the shared panel', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: OrgTeamScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(
      find.byKey(const ValueKey('org-hub-member-demo-user')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('org-hub-invite')), findsOneWidget);
  });

  testWidgets('organization hub shows values in rows with no save bar', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      size: const Size(390, 844),
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgSettingsScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(find.byKey(const Key('org-hub-title')), findsOneWidget);
    expect(find.textContaining('SETTINGS'), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
    expect(find.byType(StickyActionBar), findsNothing);
    expect(find.byKey(const Key('org-settings-save')), findsNothing);
    expect(find.byType(TextField), findsNothing);

    final demo = DemoData.organizations['org1']!;
    expect(
      find.descendant(
        of: find.byKey(const Key('org-hub-name')),
        matching: find.text(demo.name),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('org-hub-about')),
        matching: find.text(demo.description!),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('org-hub-website')),
        matching: find.text(demo.website!),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('org-hub-photos')),
        matching: find.text('0 OF 10'),
      ),
      findsOneWidget,
    );

    final phone = find.byKey(const Key('org-hub-phone'));
    await _reveal(tester, phone);
    expect(
      find.descendant(
        of: find.byKey(const Key('org-hub-legal-name')),
        matching: find.text('The Foghorn Club LLC'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('org-hub-contact-email')),
        matching: find.text('hello@foghorn.example'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: phone, matching: find.text('415-555-0142')),
      findsOneWidget,
    );
    expect(find.text('EDIT'), findsNWidgets(3));
    expect(find.byKey(const Key('org-hub-stripe')), findsOneWidget);
    expect(find.byKey(const Key('org-hub-tax')), findsOneWidget);
    expect(find.byKey(const Key('org-settings-deactivate')), findsOneWidget);
  });

  testWidgets('hub label, value and trailing columns line up across rows', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      size: const Size(390, 844),
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgSettingsScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    final demo = DemoData.organizations['org1']!;
    final rows = [
      ('org-hub-name', 'NAME', demo.name),
      ('org-hub-about', 'ABOUT', demo.description!),
      ('org-hub-website', 'WEBSITE', demo.website!),
      ('org-hub-photos', 'PHOTOS', '0 OF 10'),
      ('org-hub-legal-name', 'LEGAL NAME', 'The Foghorn Club LLC'),
      ('org-hub-contact-email', 'CONTACT EMAIL', 'hello@foghorn.example'),
      ('org-hub-phone', 'PHONE', '415-555-0142'),
    ];
    final labelLefts = <double>[];
    final valueLefts = <double>[];
    final trailingRights = <double>[];
    for (final (key, label, value) in rows) {
      final row = find.byKey(Key(key));
      await _reveal(tester, row);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44), reason: key);
      labelLefts.add(
        tester
            .getRect(find.descendant(of: row, matching: find.text(label)))
            .left,
      );
      valueLefts.add(
        tester
            .getRect(find.descendant(of: row, matching: find.text(value)))
            .left,
      );
      final trailing = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              (widget is Icon && widget.icon == Icons.chevron_right) ||
              (widget is Text && widget.data == 'EDIT'),
        ),
      );
      trailingRights.add(tester.getRect(trailing).right);
    }
    for (final xs in [labelLefts, valueLefts, trailingRights]) {
      for (final x in xs) {
        expect((x - xs.first).abs(), lessThanOrEqualTo(1), reason: '$xs');
      }
    }
  });

  testWidgets('hub shows NOT SET for empty fields and hides private rows', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    await repository.updateOrganizationProfile(
      organizationId: 'org1',
      description: '',
      website: '',
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgSettingsScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');
    harness.app.myOrganizations = [
      OrganizationMembership(
        organization: DemoData.organizations['org1']!,
        role: OrganizationRole.manager,
      ),
    ];
    await enterOrganizer(tester, harness, 'org1');

    expect(find.text('NOT SET'), findsNWidgets(2));
    expect(find.byKey(const Key('org-hub-legal-name')), findsNothing);
    expect(find.byKey(const Key('org-hub-stripe')), findsNothing);
    await tester.drag(_pageScrollable(), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-settings-deactivate')), findsOneWidget);
  });

  testWidgets('name sheet saves the merged public profile', (tester) async {
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

    await tester.tap(find.byKey(const Key('org-hub-name')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('org-hub-sheet-name'));
    expect(sheet, findsOneWidget);
    expect(
      find.ancestor(of: find.byType(TextField), matching: find.byType(EpCard)),
      findsNothing,
    );
    final field = find.byKey(const Key('org-settings-name'));
    expect(
      tester.widget<TextField>(field).controller?.text,
      'The Foghorn Club',
    );

    await tester.enterText(field, '');
    await tester.pump();
    expect(
      tester
          .widget<EpPill>(find.byKey(const Key('org-hub-sheet-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(field, 'Foghorn Collective');
    await tester.pump();
    await tester.tap(find.byKey(const Key('org-hub-sheet-save')));
    await tester.pumpAndSettle();

    expect(sheet, findsNothing);
    final saved = await repository.organization('org1');
    expect(saved?.name, 'Foghorn Collective');
    expect(saved?.description, DemoData.organizations['org1']!.description);
    expect(saved?.website, DemoData.organizations['org1']!.website);
    expect(
      find.descendant(
        of: find.byKey(const Key('org-hub-name')),
        matching: find.text('Foghorn Collective'),
      ),
      findsOneWidget,
    );
    expect(harness.app.toast, 'Changes saved.');
  });

  testWidgets('about and website sheets save just their field', (tester) async {
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

    await tester.tap(find.byKey(const Key('org-hub-about')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-hub-sheet-about')), findsOneWidget);
    final about = find.byKey(const Key('org-settings-description'));
    expect(tester.widget<TextField>(about).maxLength, 1000);
    expect(tester.widget<TextField>(about).maxLines, greaterThan(1));
    await tester.enterText(about, 'A lively neighborhood room.');
    await tester.tap(find.byKey(const Key('org-hub-sheet-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-hub-sheet-about')), findsNothing);

    await tester.tap(find.byKey(const Key('org-hub-website')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-hub-sheet-website')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('org-settings-website')),
      'https://foghorn.example',
    );
    await tester.tap(find.byKey(const Key('org-hub-sheet-save')));
    await tester.pumpAndSettle();

    final saved = await repository.organization('org1');
    expect(saved?.name, 'The Foghorn Club');
    expect(saved?.description, 'A lively neighborhood room.');
    expect(saved?.website, 'https://foghorn.example');
  });

  testWidgets('private detail sheets save the merged details', (tester) async {
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

    final legalName = find.byKey(const Key('org-hub-legal-name'));
    await _reveal(tester, legalName);
    await tester.tap(legalName);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-hub-sheet-legal-name')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('org-settings-contact-name')))
          .controller
          ?.text,
      'Earplug Fan',
    );
    await tester.enterText(
      find.byKey(const Key('org-settings-legal-name')),
      'Foghorn Collective LLC',
    );
    await tester.tap(find.byKey(const Key('org-hub-sheet-save')));
    await tester.pumpAndSettle();

    final phone = find.byKey(const Key('org-hub-phone'));
    await _reveal(tester, phone);
    await tester.tap(phone);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('org-settings-phone')),
      '415-555-0199',
    );
    await tester.tap(find.byKey(const Key('org-hub-sheet-save')));
    await tester.pumpAndSettle();

    final details = (await repository.organizationDashboard(
      'org1',
    )).privateDetails;
    expect(details?.legalName, 'Foghorn Collective LLC');
    expect(details?.contactName, 'Earplug Fan');
    expect(details?.businessEmail, 'hello@foghorn.example');
    expect(details?.phone, '415-555-0199');
    expect(
      find.descendant(
        of: legalName,
        matching: find.text('Foghorn Collective LLC'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed sheet save stays open with the error', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _FailingProfileRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgSettingsScreen()),
    );
    await enterOrganizer(tester, harness, 'org1');

    await tester.tap(find.byKey(const Key('org-hub-name')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('org-settings-name')),
      'Foghorn Collective',
    );
    await tester.tap(find.byKey(const Key('org-hub-sheet-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('org-hub-sheet-name')), findsOneWidget);
    expect(find.byKey(const Key('org-settings-save-error')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('org-settings-name')))
          .controller
          ?.text,
      'Foghorn Collective',
    );
    expect((await repository.organization('org1'))?.name, 'The Foghorn Club');
  });

  testWidgets('danger zone deactivates after typing DEACTIVATE', (
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

    final deactivate = find.byKey(const Key('org-settings-deactivate'));
    await _reveal(tester, deactivate);
    await tester.tap(deactivate);
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'DEACTIVATE');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('org-settings-deactivate-confirmation')),
      'DEACTIVATE',
    );
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(
      (await repository.organization('org1'))?.status,
      OrganizationStatus.suspended,
    );
    expect(harness.app.current.screen, Screen.home);
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

/// The stat cells render their value as display type and their label as a mono
/// eyebrow, so both read back uppercased.
/// Every slot filled by the demo band, so the request counts as confirmed.
Opportunity _fullyBooked(Opportunity opportunity) => opportunity.copyWith(
  slots: [
    for (final slot in opportunity.slots)
      OpportunitySlot(
        id: slot.id,
        order: slot.order,
        role: slot.role,
        setLengthMin: slot.setLengthMin,
        guaranteeMinor: slot.guaranteeMinor,
        required: slot.required,
        status: SlotStatus.booked,
        bandId: 'b1',
      ),
  ],
);

const _enabledStripe = StripeAccountStatus(
  state: StripeAccountState.enabled,
  hasAccount: true,
  chargesEnabled: true,
  payoutsEnabled: true,
  detailsSubmitted: true,
  requirementsDue: [],
);

/// The venue card centre sits on its area map, which swallows taps; open the
/// editor from the venue name instead.
Future<void> _openVenue(WidgetTester tester, Finder venueCard) async {
  await tester.tap(
    find.descendant(of: venueCard, matching: find.byType(Text)).first,
  );
  await tester.pumpAndSettle();
}

/// Scrolls the row into view and settles so its centre is tappable.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 250, scrollable: _pageScrollable());
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Finder _pageScrollable() => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

class _FailingProfileRepository extends DemoRepository {
  _FailingProfileRepository({required super.auth});

  @override
  Future<void> updateOrganizationProfile({
    required String organizationId,
    String? name,
    String? description,
    String? website,
  }) async {
    throw StateError('offline');
  }
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
