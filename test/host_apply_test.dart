import 'dart:typed_data';

import 'package:earplug/app_links.dart';
import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/host_apply.dart';
import 'package:earplug/screens/org_application_status.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  testWidgets('host agreement link preserves the full checkbox label', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final opened = <Uri>[];
    final harness = await pumpApp(
      tester,
      auth: auth,
      home: HostApplyScreen(
        launch: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );
    addTearDown(() => _disposeApp(harness.app));

    await _reveal(tester, 'host-apply-agree');
    final agreement = find.byKey(const ValueKey('host-apply-agree'));
    expect(
      find.text(
        'I agree to the Host Agreement and booking protection terms',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.tapOnText(
      find.textRange.ofSubstring('Host Agreement', descendentOf: agreement),
    );
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse(legalHostAgreementUrl)]);
    expect(tester.widget<CheckboxListTile>(agreement).value, isFalse);
  });

  testWidgets(
    'flat host form autosaves, validates every requirement and submits',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final picker = FakeMediaPicker()..nextPhoto = _idPhoto;
      final harness = await pumpApp(
        tester,
        home: HostApplyScreen(mediaPicker: picker),
        auth: auth,
        repository: repository,
        beforePump: (app) => app.openHostApply(),
      );
      addTearDown(() => _disposeApp(harness.app));

      expect(find.text('BECOME A HOST'), findsOneWidget);
      expectNoFieldInCard(tester);
      expect(_submitBar(tester).onPrimary, isNull);
      for (final field in _hostFields.entries) {
        await _enterText(tester, field.key, field.value);
        expect(_submitBar(tester).onPrimary, isNull);
      }
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      final draft = (await repository.myOrganizationApplication())!;
      expect(draft.kind, ApplicationKind.host);
      expect(draft.orgType, OrganizationType.privateHost);
      expect(draft.status, OrganizationApplicationStatus.draft);
      expect(draft.orgName, 'Jordan Lee');
      expect(draft.contactName, 'Jordan Lee');
      expect(draft.hostDisplayName, 'Jordan Lee');
      expect(draft.phone, '415-555-0101');
      expect(draft.hostPhone, '415-555-0101');
      expect(draft.hostArea, 'Mission District, San Francisco');
      expect(draft.businessEmail, 'jordan@example.com');
      expect(draft.venue, isNull);

      await _reveal(tester, 'host-apply-agree');
      await tester.tap(find.byKey(const ValueKey('host-apply-agree')));
      await tester.pump();
      expect(_submitBar(tester).onPrimary, isNull);
      await tester.tap(find.byKey(const ValueKey('host-apply-agree')));
      await tester.pump();

      await _reveal(tester, 'host-apply-doc-add', upward: true);
      await tester.tap(find.byKey(const ValueKey('host-apply-doc-add')));
      await tester.pumpAndSettle();
      expect(picker.photoCalls, 1);
      expect(
        (await repository.myOrganizationApplication())!.documents,
        hasLength(1),
      );
      expect(_submitBar(tester).onPrimary, isNull);

      await _reveal(tester, 'host-apply-agree');
      await tester.tap(find.byKey(const ValueKey('host-apply-agree')));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(_submitBar(tester).onPrimary, isNotNull);
      expect(
        (await repository.myOrganizationApplication())!.hostAgreementAcceptedAt,
        isNotNull,
      );
      expectNoFieldInCard(tester);

      // Each field still gates submission when the document and agreement exist.
      for (final field in _hostFields.entries) {
        await _enterText(tester, field.key, '', upward: true);
        expect(_submitBar(tester).onPrimary, isNull);
        await tester.enterText(find.byKey(ValueKey(field.key)), field.value);
        await tester.pump();
        expect(_submitBar(tester).onPrimary, isNotNull);
      }

      final document =
          (await repository.myOrganizationApplication())!.documents.single;
      await _reveal(tester, 'host-apply-doc-remove-${document.storageId}');
      await tester.tap(
        find.byKey(ValueKey('host-apply-doc-remove-${document.storageId}')),
      );
      await tester.pumpAndSettle();
      expect(_submitBar(tester).onPrimary, isNull);
      await _reveal(tester, 'host-apply-doc-add');
      await tester.tap(find.byKey(const ValueKey('host-apply-doc-add')));
      await tester.pumpAndSettle();
      expect(_submitBar(tester).onPrimary, isNotNull);

      await tester.tap(find.text('SUBMIT APPLICATION'));
      await tester.pumpAndSettle();
      expect(
        harness.app.myOrganizationApplication?.status,
        OrganizationApplicationStatus.submitted,
      );
      expect(harness.app.current.screen, Screen.orgApplicationStatus);

      final statusHarness = await pumpApp(
        tester,
        home: const OrgApplicationStatusScreen(),
        auth: auth,
        repository: repository,
        beforePump: (app) => app.resetTo(Screen.orgApplicationStatus),
      );
      addTearDown(() => _disposeApp(statusHarness.app));
      expect(find.text('HOST APPLICATION'), findsOneWidget);
      expect(find.byKey(const Key('host-status-details')), findsOneWidget);
      expect(find.text('Jordan Lee'), findsOneWidget);
      expect(find.text('Mission District, San Francisco'), findsOneWidget);
      expect(find.text('415-555-0101'), findsOneWidget);
      expect(find.text('ORGANIZER APPLICATION'), findsNothing);
    },
  );

  testWidgets('new host application prefills the profile email only once', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _HostTestRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      home: const HostApplyScreen(),
      auth: auth,
      repository: repository,
    );
    addTearDown(() => _disposeApp(harness.app));

    await _reveal(tester, 'host-apply-email');
    expect(_fieldText(tester, 'host-apply-email'), 'fan@example.com');
    await tester.enterText(find.byKey(const ValueKey('host-apply-email')), '');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(_fieldText(tester, 'host-apply-email'), isEmpty);
    expect(
      (await repository.myOrganizationApplication())!.businessEmail,
      isEmpty,
    );
  });

  for (final email in ['', 'saved@example.com']) {
    testWidgets('host draft preserves saved email "$email" and other fields', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _HostTestRepository(auth: auth);
      final draft = await _seedHostDraft(repository, email: email);
      final harness = await pumpApp(
        tester,
        home: const HostApplyScreen(),
        auth: auth,
        repository: repository,
      );
      addTearDown(() => _disposeApp(harness.app));

      expect(_fieldText(tester, 'host-apply-display-name'), 'Jordan Lee');
      expect(_fieldText(tester, 'host-apply-phone'), '415-555-0101');
      await _reveal(tester, 'host-apply-area');
      expect(
        _fieldText(tester, 'host-apply-area'),
        'Mission District, San Francisco',
      );
      await _reveal(tester, 'host-apply-email');
      expect(_fieldText(tester, 'host-apply-email'), email);
      await _reveal(tester, 'host-apply-agree');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('host-apply-agree')),
            )
            .value,
        isTrue,
      );
      expect(
        find.byKey(
          ValueKey('host-apply-doc-remove-${draft.documents.single.storageId}'),
        ),
        findsOneWidget,
      );
      expectNoFieldInCard(tester);
    });
  }

  testWidgets(
    'blur saves promptly and a revision conflict reloads the host draft',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        home: const HostApplyScreen(),
        auth: auth,
        repository: repository,
      );
      addTearDown(() => _disposeApp(harness.app));

      await tester.enterText(
        find.byKey(const ValueKey('host-apply-display-name')),
        'Jordan Lee',
      );
      await tester.tap(find.byKey(const ValueKey('host-apply-phone')));
      await tester.pump();
      final saved = (await repository.myOrganizationApplication())!;
      expect(saved.hostDisplayName, 'Jordan Lee');

      await repository.saveOrganizationApplicationDraft(
        applicationId: saved.id,
        expectedRevision: saved.revision,
        kind: ApplicationKind.host,
        orgType: OrganizationType.privateHost,
        orgName: 'Updated elsewhere',
        contactName: 'Updated elsewhere',
        hostDisplayName: 'Updated elsewhere',
        businessEmail: 'updated@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('host-apply-display-name')),
        'Local edit',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(
        _fieldText(tester, 'host-apply-display-name'),
        'Updated elsewhere',
      );
      await _reveal(tester, 'host-apply-feedback');
      expect(find.text('Application changed elsewhere'), findsOneWidget);

      await _enterText(
        tester,
        'host-apply-display-name',
        'Reconciled',
        upward: true,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(
        (await repository.myOrganizationApplication())!.hostDisplayName,
        'Reconciled',
      );
    },
  );

  testWidgets('host form opens after an approved organizer application', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final draft = await repository.saveOrganizationApplicationDraft(
      kind: ApplicationKind.organization,
      orgName: 'The Foghorn Club',
      orgType: OrganizationType.venueOperator,
      contactName: 'Jordan Lee',
      businessEmail: 'jordan@example.com',
    );
    await repository.submitOrganizationApplication(
      applicationId: draft.applicationId,
      expectedRevision: draft.revision,
    );
    await repository.decideOrganizationApplication(
      applicationId: draft.applicationId,
      decision: ApplicationDecision.approved,
    );
    final harness = await pumpApp(
      tester,
      home: const HostApplyScreen(),
      auth: auth,
      repository: repository,
    );
    addTearDown(() => _disposeApp(harness.app));

    expect(
      find.text('You already have an organizer application in progress.'),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('host-apply-display-name')),
      findsOneWidget,
    );
  });

  for (final kind in [
    null,
    ApplicationKind.organization,
    ApplicationKind.unknown,
  ]) {
    testWidgets('host form blocks an existing $kind organizer application', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      await repository.saveOrganizationApplicationDraft(
        kind: kind,
        orgName: 'The Foghorn Club',
        orgType: OrganizationType.venueOperator,
        contactName: 'Jordan Lee',
        businessEmail: 'jordan@example.com',
      );
      final harness = await pumpApp(
        tester,
        home: const HostApplyScreen(),
        auth: auth,
        repository: repository,
      );
      addTearDown(() => _disposeApp(harness.app));

      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('You already have an organizer application in progress.'),
        findsOneWidget,
      );
      await tester.tap(find.text('OPEN APPLICATION'));
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.orgApplicationStatus);
    });
  }

  testWidgets('switcher host entry opens the host application', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _HostTestRepository(
      auth: auth,
      excludedOrganizationTypes: const {OrganizationType.privateHost},
    );
    final harness = await pumpApp(
      tester,
      home: const Scaffold(bottomNavigationBar: FanTabBar()),
      auth: auth,
      repository: repository,
    );
    addTearDown(() => _disposeApp(harness.app));
    await tester.tap(find.text('SWITCH'));
    await tester.pumpAndSettle();

    final hostEntry = find.byKey(const Key('switcher-become-host'));
    expect(hostEntry, findsOneWidget);
    expect(find.byKey(const Key('switcher-org-org1')), findsOneWidget);
    expect(find.byKey(const Key('switcher-org-org2')), findsNothing);
    expect(find.byKey(const Key('switcher-become-organizer')), findsNothing);
    expect(find.text('BECOME A HOST'), findsOneWidget);
    await tester.ensureVisible(hostEntry);
    await tester.tap(hostEntry);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.hostApply);
  });

  testWidgets(
    'memberships hide both entries without an application in progress',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        home: const Scaffold(bottomNavigationBar: FanTabBar()),
        auth: auth,
        repository: repository,
      );
      addTearDown(() => _disposeApp(harness.app));
      expect(harness.app.myOrganizationApplication, isNull);
      await tester.tap(find.text('SWITCH'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('switcher-org-org1')), findsOneWidget);
      expect(find.byKey(const Key('switcher-org-org2')), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
      expect(find.byKey(const Key('switcher-become-organizer')), findsNothing);
      expect(find.byKey(const Key('switcher-become-host')), findsNothing);
    },
  );

  testWidgets('host draft stays accessible despite a privateHost membership', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _HostTestRepository(auth: auth);
    await _seedHostDraft(repository);
    final harness = await pumpApp(
      tester,
      home: const Scaffold(bottomNavigationBar: FanTabBar()),
      auth: auth,
      repository: repository,
    );
    addTearDown(() => _disposeApp(harness.app));
    expect(harness.app.myOrganizationApplication?.kind, ApplicationKind.host);
    expect(
      harness.app.myOrganizationApplication?.status,
      OrganizationApplicationStatus.draft,
    );
    expect(
      harness.app.myOrganizations.any(
        (membership) =>
            membership.organization.id == 'org2' &&
            membership.organization.orgType == OrganizationType.privateHost,
      ),
      isTrue,
    );
    await tester.tap(find.text('SWITCH'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('switcher-org-org2')), findsOneWidget);
    final hostEntry = find.byKey(const Key('switcher-become-host'));
    expect(hostEntry, findsOneWidget);
    expect(find.text('CONTINUE HOST APPLICATION'), findsOneWidget);
    await tester.ensureVisible(hostEntry);
    await tester.tap(hostEntry);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.hostApply);
  });

  testWidgets('host-only membership keeps the organizer entry available', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _HostTestRepository(
      auth: auth,
      hostRole: OrganizationRole.door,
      excludedOrganizationTypes: const {
        OrganizationType.venueOperator,
        OrganizationType.promoter,
      },
    );
    final harness = await pumpApp(
      tester,
      home: const Scaffold(bottomNavigationBar: FanTabBar()),
      auth: auth,
      repository: repository,
    );
    addTearDown(() => _disposeApp(harness.app));
    await tester.tap(find.text('SWITCH'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('switcher-org-org1')), findsNothing);
    expect(find.byKey(const Key('switcher-org-org2')), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.byKey(const Key('switcher-become-host')), findsNothing);
    final organizerEntry = find.byKey(const Key('switcher-become-organizer'));
    expect(organizerEntry, findsOneWidget);
    expect(find.text('BECOME AN ORGANIZER'), findsOneWidget);
    await tester.ensureVisible(organizerEntry);
    await tester.tap(organizerEntry);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgApply);
  });

  for (final hasHostMembership in [true, false]) {
    testWidgets(
      'approved host application hides entry with membership=$hasHostMembership',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final repository = _HostTestRepository(
          auth: auth,
          excludedOrganizationTypes: {
            if (!hasHostMembership) OrganizationType.privateHost,
          },
        )..platformAdmin = true;
        final draft = await _seedHostDraft(repository);
        await repository.submitOrganizationApplication(
          applicationId: draft.id,
          expectedRevision: draft.revision,
        );
        await repository.decideOrganizationApplication(
          applicationId: draft.id,
          decision: ApplicationDecision.approved,
        );
        final harness = await pumpApp(
          tester,
          home: const Scaffold(bottomNavigationBar: FanTabBar()),
          auth: auth,
          repository: repository,
        );
        addTearDown(() => _disposeApp(harness.app));
        final application = harness.app.myOrganizationApplication!;
        expect(application.kind, ApplicationKind.host);
        expect(application.status, OrganizationApplicationStatus.approved);
        expect(
          harness.app.myOrganizations.any(
            (membership) =>
                membership.organization.orgType == OrganizationType.privateHost,
          ),
          hasHostMembership,
        );
        await tester.tap(find.text('SWITCH'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            Key('switcher-org-${application.resultingOrganizationId}'),
          ),
          hasHostMembership ? findsOneWidget : findsNothing,
        );
        expect(find.byKey(const Key('switcher-become-host')), findsNothing);
        expect(find.text('HOST APPLICATION · APPROVED'), findsNothing);
        expect(
          find.byKey(const Key('switcher-become-organizer')),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'host draft and status keep the organizer switcher entry separate',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _HostTestRepository(
        auth: auth,
        excludedOrganizationTypes: const {
          OrganizationType.venueOperator,
          OrganizationType.privateHost,
          OrganizationType.promoter,
        },
      );
      final draft = await _seedHostDraft(repository);
      final harness = await pumpApp(
        tester,
        home: const Scaffold(bottomNavigationBar: FanTabBar()),
        auth: auth,
        repository: repository,
      );
      addTearDown(() => _disposeApp(harness.app));
      expect(harness.app.myOrganizations, isEmpty);
      await tester.tap(find.text('SWITCH'));
      await tester.pumpAndSettle();
      expect(find.text('CONTINUE HOST APPLICATION'), findsOneWidget);
      expect(find.text('BECOME AN ORGANIZER'), findsOneWidget);
      final organizerEntry = find.byKey(const Key('switcher-become-organizer'));
      await tester.ensureVisible(organizerEntry);
      await tester.tap(organizerEntry);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.orgApply);

      await repository.submitOrganizationApplication(
        applicationId: draft.id,
        expectedRevision: draft.revision,
      );
      await harness.app.refreshOrganizationApplication();
      harness.app.toFanView();
      await tester.pumpAndSettle();
      await tester.tap(find.text('SWITCH'));
      await tester.pumpAndSettle();
      expect(find.text('HOST APPLICATION · SUBMITTED'), findsOneWidget);
      expect(find.text('BECOME AN ORGANIZER'), findsOneWidget);
      final hostEntry = find.byKey(const Key('switcher-become-host'));
      await tester.ensureVisible(hostEntry);
      await tester.tap(hostEntry);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.orgApplicationStatus);
    },
  );

  for (final role in [OrganizationRole.owner, OrganizationRole.door]) {
    testWidgets(
      'host tabs show three items for $role and organizer retains TEAM',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final repository = _HostTestRepository(auth: auth, hostRole: role);
        final harness = await pumpApp(
          tester,
          home: const Scaffold(bottomNavigationBar: OrganizerTabBar()),
          auth: auth,
          repository: repository,
          beforePump: (app) => app.switchToOrganization('org2'),
        );
        addTearDown(() => _disposeApp(harness.app));

        expect(find.byKey(const Key('organizer-tab-dash')), findsOneWidget);
        expect(
          find.byKey(const Key('organizer-tab-opportunities')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('organizer-tab-settings')), findsOneWidget);
        expect(find.byKey(const Key('organizer-tab-team')), findsNothing);
        expect(find.byType(EpNavigationItem), findsNWidgets(3));
        expect(find.text('DASH'), findsOneWidget);
        expect(find.text('REQUESTS'), findsOneWidget);
        expect(find.text('SETTINGS'), findsOneWidget);
        await tester.tap(find.text('REQUESTS'));
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.orgOpportunities);
        expect(
          tester
              .widget<EpNavigationItem>(
                find.byKey(const Key('organizer-tab-opportunities')),
              )
              .selected,
          isTrue,
        );

        await enterOrganizer(tester, harness, 'org1');
        expect(find.byKey(const Key('organizer-tab-team')), findsOneWidget);
        expect(find.text('GIGS'), findsOneWidget);
        expect(find.text('REQUESTS'), findsNothing);
      },
    );
  }

  for (final decision in [
    ApplicationDecision.approved,
    ApplicationDecision.rejected,
    ApplicationDecision.needsInfo,
  ]) {
    testWidgets('host status handles $decision with the correct destination', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth)..platformAdmin = true;
      final draft = await _seedHostDraft(repository);
      await repository.submitOrganizationApplication(
        applicationId: draft.id,
        expectedRevision: draft.revision,
      );
      await repository.decideOrganizationApplication(
        applicationId: draft.id,
        decision: decision,
        note: decision == ApplicationDecision.rejected
            ? 'Please use a clearer ID.'
            : null,
      );
      final harness = await pumpApp(
        tester,
        home: const OrgApplicationStatusScreen(),
        auth: auth,
        repository: repository,
      );
      addTearDown(() => _disposeApp(harness.app));
      expect(find.text('HOST APPLICATION'), findsOneWidget);
      expect(find.byKey(const Key('host-status-details')), findsOneWidget);

      if (decision == ApplicationDecision.approved) {
        expect(find.text('Your host account is ready.'), findsOneWidget);
        expect(find.text('OPEN HOST DASHBOARD'), findsOneWidget);
        await tester.tap(find.byKey(const Key('org-status-switch')));
        await tester.pumpAndSettle();
        expect(
          harness.app.organizationId,
          harness.app.myOrganizationApplication!.resultingOrganizationId,
        );
        expect(harness.app.currentIsHost, isTrue);
        expect(harness.app.current.screen, Screen.orgDash);
      } else if (decision == ApplicationDecision.rejected) {
        await tester.tap(find.byKey(const Key('org-status-reapply')));
        // This directly pumped status widget remains mounted after navigation.
        // Its draft placeholder animates until the real shell changes screens.
        await tester.pump();
        await tester.pump();
        final newDraft = (await repository.myOrganizationApplication())!;
        expect(newDraft.id, isNot(draft.id));
        expect(newDraft.kind, ApplicationKind.host);
        expect(newDraft.orgType, OrganizationType.privateHost);
        expect(newDraft.orgName, isEmpty);
        expect(newDraft.businessEmail, isEmpty);
        expect(newDraft.documents, isEmpty);
        expect(harness.app.current.screen, Screen.hostApply);
        expect(
          (await repository.organizationApplication(draft.id))!.status,
          OrganizationApplicationStatus.rejected,
        );
      } else {
        await tester.tap(find.byKey(const Key('org-status-edit')));
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.hostApply);
      }
    });
  }
}

const _hostFields = {
  'host-apply-display-name': 'Jordan Lee',
  'host-apply-phone': '415-555-0101',
  'host-apply-area': 'Mission District, San Francisco',
  'host-apply-email': 'jordan@example.com',
};

final _idPhoto = PickedMedia(
  bytes: Uint8List.fromList([1, 2, 3]),
  filename: 'id.jpg',
  contentType: 'image/jpeg',
  sizeBytes: 3,
);

Future<OrganizationApplication> _seedHostDraft(
  DemoRepository repository, {
  String email = 'jordan@example.com',
}) async {
  final saved = await repository.saveOrganizationApplicationDraft(
    kind: ApplicationKind.host,
    orgType: OrganizationType.privateHost,
    orgName: 'Jordan Lee',
    contactName: 'Jordan Lee',
    businessEmail: email,
    phone: '415-555-0101',
    hostDisplayName: 'Jordan Lee',
    hostPhone: '415-555-0101',
    hostArea: 'Mission District, San Francisco',
    hostAgreementAccepted: true,
  );
  await repository.attachApplicationDocument(
    applicationId: saved.applicationId,
    storageId: 'host-id-document',
  );
  return (await repository.myOrganizationApplication())!;
}

StickyActionBar _submitBar(WidgetTester tester) => tester
    .widget<StickyActionBar>(find.byKey(const ValueKey('host-apply-submit')));

String? _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller?.text;

Future<void> _enterText(
  WidgetTester tester,
  String key,
  String value, {
  bool upward = false,
}) async {
  await _reveal(tester, key, upward: upward);
  await tester.enterText(find.byKey(ValueKey(key)), value);
  await tester.pump();
}

Future<void> _reveal(
  WidgetTester tester,
  String key, {
  bool upward = false,
}) async {
  final target = find.byKey(ValueKey(key));
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(
      find.byType(Scrollable).first,
      Offset(0, upward ? 500 : -500),
    );
    await tester.pump();
  }
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}

void _disposeApp(AppState app) {
  try {
    app.dispose();
  } on FlutterError catch (error) {
    if (!error.message.contains('used after being disposed')) rethrow;
  }
}

class _HostTestRepository extends DemoRepository {
  _HostTestRepository({
    required super.auth,
    this.hostRole = OrganizationRole.owner,
    this.excludedOrganizationTypes = const {},
  });

  final OrganizationRole hostRole;
  final Set<OrganizationType> excludedOrganizationTypes;

  @override
  Future<UserProfile?> me() async => UserProfile(
    name: 'Jordan Lee',
    email: 'fan@example.com',
    genres: const [],
    attendedCount: 0,
    createdAt: DateTime(2026),
  );

  @override
  Stream<List<OrganizationMembership>> myOrganizations() =>
      super.myOrganizations().map(
        (memberships) => [
          for (final membership in memberships)
            if (!excludedOrganizationTypes.contains(
              membership.organization.orgType,
            ))
              if (membership.organization.id == 'org2')
                OrganizationMembership(
                  organization: membership.organization,
                  role: hostRole,
                )
              else
                membership,
        ],
      );
}
