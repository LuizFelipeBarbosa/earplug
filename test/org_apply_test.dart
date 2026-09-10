import 'dart:typed_data';

import 'package:earplug/app_links.dart';
import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/org_application_status.dart';
import 'package:earplug/screens/org_apply.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/services/user_actions.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';
import 'support/ui_test_helpers.dart';

void main() {
  testWidgets('organizer type picker is visible when promoters are enabled', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        await app.commitAuth();
        app.go(Screen.orgApply);
      },
      home: _ApplicationHost(mediaPicker: FakeMediaPicker()),
    );

    for (final type in [
      OrganizationType.venueOperator,
      OrganizationType.promoter,
      OrganizationType.studentOrg,
    ]) {
      final chip = find.byKey(Key('org-apply-type-${type.wireValue}'));
      expect(chip, findsOneWidget);
      expect(
        tester.widget<EpChip>(chip).active,
        type == OrganizationType.venueOperator,
      );
    }
    expect(findUiText('ORGANIZATION TYPE'), findsOneWidget);
    expect(
      find.text('Promoters and student organizations are coming next.'),
      findsNothing,
    );
    await _scrollDownToKey(tester, const ValueKey('org-apply-kind-bar'));
    expect(find.byKey(const ValueKey('org-apply-kind-club')), findsOneWidget);
    await _scrollDownToKey(tester, const ValueKey('org-apply-venue-name'));
    await _scrollDownToKey(tester, const ValueKey('org-apply-capacity'));
  });

  testWidgets('selecting promoter hides venue fields and clears saved venue', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    await repository.saveOrganizationApplicationDraft(
      orgName: 'Night Heron Collective',
      orgType: OrganizationType.venueOperator,
      contactName: '',
      businessEmail: '',
      venue: const ApplicationVenueDraft(
        name: 'Night Heron Club',
        addr: '22 Valencia Street',
        point: LatLng(37.76, -122.42),
        area: 'Mission',
        capacity: 180,
        venueType: VenueType.club,
      ),
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        await app.commitAuth();
        app.go(Screen.orgApply);
      },
      home: _ApplicationHost(mediaPicker: FakeMediaPicker()),
    );

    await tester.tap(find.byKey(const Key('org-apply-type-promoter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('org-apply-kind-bar')), findsNothing);
    expect(find.byKey(const ValueKey('org-apply-kind-club')), findsNothing);
    expect(find.byKey(const ValueKey('org-apply-venue-name')), findsNothing);
    expect(find.byKey(const ValueKey('org-apply-venue-address')), findsNothing);
    expect(find.byKey(const ValueKey('org-apply-capacity')), findsNothing);
    expect(
      find.text(
        "You'll post events at verified venues and ask each venue for approval.",
      ),
      findsOneWidget,
    );
    final saved = (await repository.myOrganizationApplication())!;
    expect(saved.orgType, OrganizationType.promoter);
    expect(saved.venue, isNull);
    expect(
      tester.widget<StickyActionBar>(find.byType(StickyActionBar)).onPrimary,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('org-apply-type-promoter')));
    await tester.pumpAndSettle();
    expect(
      (await repository.myOrganizationApplication())!.revision,
      saved.revision,
    );
  });

  testWidgets('promoter application submits without a venue', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final picker = FakeMediaPicker();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        await app.commitAuth();
        app.go(Screen.orgApply);
      },
      home: _ApplicationHost(mediaPicker: picker),
    );

    await tester.tap(find.byKey(const Key('org-apply-type-promoter')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<StickyActionBar>(find.byType(StickyActionBar)).onPrimary,
      isNotNull,
    );
    await _enterText(
      tester,
      const ValueKey('org-apply-name'),
      'Night Heron Collective',
    );
    await _continueToContact(tester);
    expect(find.byKey(const Key('org-apply-type-promoter')), findsNothing);
    await _enterText(
      tester,
      const ValueKey('org-apply-contact-name'),
      'Rae Booker',
    );
    await _enterText(
      tester,
      const ValueKey('org-apply-email'),
      'rae@nightheron.example',
    );
    picker.nextPhoto = _licensePhoto;
    await _scrollDownToKey(tester, const ValueKey('org-apply-doc-add'));
    expect(
      find.text(
        'Upload something that proves your organization exists (registration, a flyer with your name, or a social page screenshot).',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('org-apply-doc-add')));
    await tester.pumpAndSettle();
    await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
    await tester.tap(find.byKey(const ValueKey('org-apply-agree')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<StickyActionBar>(find.byType(StickyActionBar)).onPrimary,
      isNotNull,
    );
    await _continueToReview(tester);
    await tester.tap(find.byKey(const ValueKey('org-apply-submit')));
    await tester.pumpAndSettle();

    final submitted = (await repository.myOrganizationApplication())!;
    expect(submitted.status, OrganizationApplicationStatus.submitted);
    expect(submitted.orgType, OrganizationType.promoter);
    expect(submitted.venue, isNull);
    expect(submitted.documents, hasLength(1));
    expect(harness.app.current.screen, Screen.orgApplicationStatus);
    expect(find.byKey(const ValueKey('org-apply-feedback')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('org-status-type'))).data,
      'Promoter or collective',
    );
  });

  testWidgets('student organization draft restores its type without a venue', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    await repository.saveOrganizationApplicationDraft(
      orgName: 'Campus Music Society',
      orgType: OrganizationType.studentOrg,
      contactName: '',
      businessEmail: '',
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        await app.commitAuth();
        app.go(Screen.orgApply);
      },
      home: _ApplicationHost(mediaPicker: FakeMediaPicker()),
    );

    expect(
      tester
          .widget<EpChip>(find.byKey(const Key('org-apply-type-studentOrg')))
          .active,
      isTrue,
    );
    expect(find.byKey(const ValueKey('org-apply-kind-bar')), findsNothing);
    expect(find.byKey(const ValueKey('org-apply-venue-name')), findsNothing);
    await _continueToContact(tester);
    final saved = (await repository.myOrganizationApplication())!;
    expect(saved.orgType, OrganizationType.studentOrg);
    expect(saved.venue, isNull);
  });

  testWidgets(
    'rejected applicants start a new draft and retain the rejection',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth)..platformAdmin = true;
      final saved = await repository.saveOrganizationApplicationDraft(
        orgName: 'Night Heron Club',
        orgType: OrganizationType.venueOperator,
        contactName: 'Rae Booker',
        businessEmail: 'rae@nightheron.example',
      );
      await repository.submitOrganizationApplication(
        applicationId: saved.applicationId,
        expectedRevision: saved.revision,
      );
      await repository.decideOrganizationApplication(
        applicationId: saved.applicationId,
        decision: ApplicationDecision.rejected,
        note: 'Provide a valid business license when you reapply.',
      );
      final rejected = await repository.myOrganizationApplication();
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        beforePump: (app) => app.go(Screen.orgApplicationStatus),
        home: _ApplicationHost(mediaPicker: FakeMediaPicker()),
      );

      expect(find.textContaining('Provide a valid business license'), findsOne);
      await tester.tap(find.byKey(const Key('org-status-reapply')));
      await tester.pumpAndSettle();

      expect(harness.app.current.screen, Screen.orgApply);
      final newDraft = (await repository.myOrganizationApplication())!;
      expect(newDraft.id, isNot(saved.applicationId));
      expect(newDraft.status, OrganizationApplicationStatus.draft);
      expect(newDraft.orgName, isEmpty);
      expect(newDraft.documents, isEmpty);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('org-apply-name')))
            .controller
            ?.text,
        isEmpty,
      );

      await tester.enterText(
        find.byKey(const ValueKey('org-apply-name')),
        'Night Heron Revised',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect((await repository.myOrganizationApplication())!.id, newDraft.id);
      expect(
        (await repository.myOrganizationApplication())!.orgName,
        'Night Heron Revised',
      );
      final previous = await repository.organizationApplication(
        saved.applicationId,
      );
      expect(previous?.status, OrganizationApplicationStatus.rejected);
      expect(previous?.reviewNote, rejected?.reviewNote);
      expect(previous?.revision, rejected?.revision);
      expect(previous?.orgName, 'Night Heron Club');
    },
  );

  testWidgets('organizer application links its agreement and saves acceptance', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final picker = FakeMediaPicker();
    final opened = <Uri>[];
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: _ApplicationHost(
        mediaPicker: picker,
        launch: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
      beforePump: (app) => app.go(Screen.orgApply),
    );

    await tester.enterText(
      find.byKey(const ValueKey('org-apply-name')),
      'Night Heron Club',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    final autosaved = await repository.myOrganizationApplication();
    expect(autosaved?.status, OrganizationApplicationStatus.draft);
    expect(autosaved?.orgName, 'Night Heron Club');
    expect(find.text('Draft saved'), findsOne);

    await tester.tap(find.byKey(const ValueKey('org-apply-kind-bar')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('org-apply-venue-name')))
          .controller
          ?.text,
      'Night Heron Club',
    );

    await tester.enterText(
      find.byKey(const ValueKey('org-apply-venue-address')),
      '22 V',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _scrollDownToKey(
      tester,
      const ValueKey('org-apply-venue-suggestion-0'),
    );
    await tester.tap(
      find.byKey(const ValueKey('org-apply-venue-suggestion-0')),
    );
    await tester.pumpAndSettle();

    await _continueToContact(tester);

    await _enterText(
      tester,
      const ValueKey('org-apply-contact-name'),
      'Rae Booker',
    );
    await _enterText(
      tester,
      const ValueKey('org-apply-email'),
      'rae@nightheron.example',
    );

    picker.nextPhoto = _licensePhoto;
    await _scrollDownToKey(tester, const ValueKey('org-apply-doc-add'));
    await tester.tap(find.byKey(const ValueKey('org-apply-doc-add')));
    await tester.pumpAndSettle();

    await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
    final agreement = find.byKey(const ValueKey('org-apply-agree'));
    expect(
      find.text(
        'I confirm this information is accurate and accept the Organizer Agreement.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.tapOnText(
      find.textRange.ofSubstring(
        'Organizer Agreement',
        descendentOf: agreement,
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(legalOrganizerAgreementUrl)]);
    expect(tester.widget<CheckboxListTile>(agreement).value, isFalse);
    expect(
      (await repository.myOrganizationApplication())
          ?.organizerAgreementAcceptedAt,
      isNull,
    );
    await tester.tap(
      find.descendant(of: agreement, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();

    await _continueToReview(tester);
    final actionBar = tester.widget<StickyActionBar>(
      find.byKey(const ValueKey('org-apply-submit')),
    );
    expect(actionBar.onPrimary, isNotNull);

    await _continueToReview(tester);
    await tester.tap(find.byKey(const ValueKey('org-apply-submit')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.orgApplicationStatus);
    expect(
      (await repository.myOrganizationApplication())?.status,
      OrganizationApplicationStatus.submitted,
    );
    final acceptedAt = (await repository.myOrganizationApplication())
        ?.organizerAgreementAcceptedAt;
    expect(acceptedAt, isNotNull);
    expect(
      harness.app.myOrganizationApplication?.organizerAgreementAcceptedAt,
      acceptedAt,
    );
    expect(find.text('Submitted'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('org-status-type'))).data,
      'Bar or club',
    );
  });

  testWidgets('draft application reopens in the editor from the switcher', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const RootShell(),
      beforePump: (app) {
        app.go(Screen.orgApply);
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('org-apply-name')),
      'Night Heron Club',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    harness.app.toFanView();
    await tester.pumpAndSettle();

    await tester.tap(findUiText('SWITCH'));
    await tester.pumpAndSettle();
    expect(findUiText('CONTINUE ORGANIZER APPLICATION'), findsOneWidget);

    await tester.tap(find.byKey(const Key('switcher-become-organizer')));
    await tester.pumpAndSettle();

    final nameField = find.byKey(const ValueKey('org-apply-name'));
    expect(nameField, findsOneWidget);
    expect(
      tester.widget<TextField>(nameField).controller?.text,
      'Night Heron Club',
    );
    expect(find.byKey(const Key('org-status-timeline')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('each step validates required decisions before review', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final picker = FakeMediaPicker();
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: OrgApplyScreen(mediaPicker: picker),
    );
    expect(find.byKey(const ValueKey('org-apply-missing')), findsNothing);
    await tester.tap(findUiText('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter organization name.'), findsOneWidget);
    expect(find.byKey(const ValueKey('org-apply-continue')), findsOneWidget);
    await _completeApplication(tester, picker: picker);
    await tester.tap(findUiText('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Organizer Agreement to continue'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('org-apply-submit')), findsNothing);
    await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
    await tester.tap(find.byKey(const ValueKey('org-apply-agree')));
    await tester.pumpAndSettle();
    await _continueToReview(tester);
    expect(
      (await repository.myOrganizationApplication())!.status,
      OrganizationApplicationStatus.draft,
    );
    expect(
      find.byKey(const ValueKey('org-apply-submit')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(findUiText('Back'));
    await tester.pumpAndSettle();
    final document =
        (await repository.myOrganizationApplication())!.documents.single;
    final removeKey = ValueKey('org-apply-doc-remove-${document.storageId}');
    await _scrollUpToKey(tester, removeKey);
    await tester.tap(find.byKey(removeKey));
    await tester.pumpAndSettle();
    await tester.tap(findUiText('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('One verification photo to continue'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('org-apply-submit')), findsNothing);
  });

  testWidgets('draft validation failure keeps typed organization edits', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..failOnce(
        'saveOrganizationApplicationDraft',
        StateError('Contact name is required'),
      );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OrgApplyScreen(),
    );

    await tester.enterText(
      find.byKey(const ValueKey('org-apply-name')),
      'Night Heron Club',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await _scrollDownToKey(tester, const ValueKey('org-apply-feedback'));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('org-apply-feedback')))
          .data,
      'Contact name is required',
    );
    await _scrollUpToKey(tester, const ValueKey('org-apply-name'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('org-apply-name')))
          .controller
          ?.text,
      'Night Heron Club',
    );
  });

  testWidgets('needs info draft prefills fields and venue kind', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final saved = await repository.saveOrganizationApplicationDraft(
      orgName: 'Night Heron Club',
      orgType: OrganizationType.venueOperator,
      website: 'https://nightheron.example',
      contactName: 'Rae Booker',
      businessEmail: 'rae@nightheron.example',
      phone: '415-555-0101',
      venue: const ApplicationVenueDraft(
        name: 'Night Heron Club',
        addr: '22 Valencia Street',
        point: LatLng(37.76, -122.42),
        area: 'Mission',
        capacity: 180,
        venueType: VenueType.club,
      ),
    );
    final documentRevision = await repository.attachApplicationDocument(
      applicationId: saved.applicationId,
      storageId: 'license-document',
    );
    await repository.submitOrganizationApplication(
      applicationId: saved.applicationId,
      expectedRevision: documentRevision,
    );
    repository.platformAdmin = true;
    await repository.decideOrganizationApplication(
      applicationId: saved.applicationId,
      decision: ApplicationDecision.needsInfo,
      note: 'Add a photo of your liquor license.',
    );

    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OrgApplyScreen(),
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('org-apply-name')))
          .controller
          ?.text,
      'Night Heron Club',
    );
    expect(
      tester
          .widget<EpChip>(find.byKey(const ValueKey('org-apply-kind-club')))
          .active,
      isTrue,
    );
    await _continueToContact(tester);

    await _scrollDownToKey(tester, const ValueKey('org-apply-website'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('org-apply-website')))
          .controller
          ?.text,
      'https://nightheron.example',
    );
  });
  testWidgets('venue requirements gate Continue and both steps retain edits', (
    tester,
  ) async {
    final picker = FakeMediaPicker();
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      home: OrgApplyScreen(mediaPicker: picker),
      auth: auth,
    );
    expect(
      tester.widget<StickyActionBar>(find.byType(StickyActionBar)).onPrimary,
      isNotNull,
    );
    expect(find.byKey(const ValueKey('org-apply-contact-name')), findsNothing);
    await _completeVenue(tester);
    await _enterText(
      tester,
      const ValueKey('org-apply-venue-name'),
      'The Back Room',
    );
    await _enterText(tester, const ValueKey('org-apply-capacity'), '180');
    await _scrollUpToKey(tester, const ValueKey('org-apply-name'));
    await tester.enterText(find.byKey(const ValueKey('org-apply-name')), '');
    await tester.pump();
    expect(
      tester.widget<StickyActionBar>(find.byType(StickyActionBar)).onPrimary,
      isNotNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('org-apply-name')),
      'Night Heron',
    );
    await _continueToContact(tester);
    await _enterText(
      tester,
      const ValueKey('org-apply-contact-name'),
      'Rae Booker',
    );
    await _enterText(
      tester,
      const ValueKey('org-apply-email'),
      'rae@example.com',
    );
    await _enterText(tester, const ValueKey('org-apply-phone'), '415-555-0101');
    await _enterText(
      tester,
      const ValueKey('org-apply-website'),
      'https://example.com',
    );
    picker.nextPhoto = _licensePhoto;
    await _scrollDownToKey(tester, const ValueKey('org-apply-doc-add'));
    await tester.tap(find.byKey(const ValueKey('org-apply-doc-add')));
    await tester.pumpAndSettle();
    await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
    await tester.tap(find.byKey(const ValueKey('org-apply-agree')));
    await tester.pumpAndSettle();
    await _scrollUpToKey(tester, const ValueKey('org-apply-back'));
    await tester.tap(find.byKey(const ValueKey('org-apply-back')));
    await tester.pumpAndSettle();
    expect(findUiText('Organization and venue'), findsOneWidget);
    expect(_fieldText(tester, 'org-apply-name'), 'Night Heron');
    await _scrollDownToKey(tester, const ValueKey('org-apply-venue-name'));
    expect(_fieldText(tester, 'org-apply-venue-name'), 'The Back Room');
    await _scrollDownToKey(tester, const ValueKey('org-apply-capacity'));
    expect(_fieldText(tester, 'org-apply-capacity'), '180');
    await _continueToContact(tester);
    expect(_fieldText(tester, 'org-apply-contact-name'), 'Rae Booker');
    expect(_fieldText(tester, 'org-apply-email'), 'rae@example.com');
    await _scrollDownToKey(tester, const ValueKey('org-apply-website'));
    expect(_fieldText(tester, 'org-apply-phone'), '415-555-0101');
    expect(_fieldText(tester, 'org-apply-website'), 'https://example.com');
    await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('org-apply-agree')),
          )
          .value,
      isTrue,
    );
    expect(
      (await harness.app.repository.myOrganizationApplication())!.documents,
      hasLength(1),
    );
    expect(
      tester.widget<StickyActionBar>(find.byType(StickyActionBar)).onPrimary,
      isNotNull,
    );
  });

  testWidgets('Continue waits for saving, stays on failure, and can retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OrgApplyScreen(),
    );
    await _completeVenue(tester);
    final saveGate = repository.gate('saveOrganizationApplicationDraft');
    repository.failOnce(
      'saveOrganizationApplicationDraft',
      StateError('Contact name is required'),
    );
    await tester.tap(findUiText('CONTINUE'));
    await tester.pump();
    expect(findUiText('SAVING…'), findsNWidgets(2));
    expect(
      tester.widget<StickyActionBar>(find.byType(StickyActionBar)).onPrimary,
      isNull,
    );
    expect(findUiText('Contact and verification'), findsNothing);
    saveGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Contact name is required'), findsOneWidget);
    await _scrollUpToKey(tester, const ValueKey('org-apply-save-state'));
    expect(find.text('Save failed'), findsOneWidget);
    expect(_fieldText(tester, 'org-apply-name'), 'Night Heron Club');
    await _continueToContact(tester);
    expect(find.text('Draft saved'), findsOneWidget);
  });

  testWidgets(
    'a contact save error on Venue offers a way back to the hidden field',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = StubRepository(auth: auth);
      await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const OrgApplyScreen(),
      );
      await _completeVenue(tester);
      await _continueToContact(tester);
      await _enterText(tester, const ValueKey('org-apply-website'), 'https://');
      await _scrollUpToKey(tester, const ValueKey('org-apply-back'));
      await tester.tap(find.byKey(const ValueKey('org-apply-back')));
      await tester.pumpAndSettle();
      repository.failOnce(
        'saveOrganizationApplicationDraft',
        StateError('Website must be a valid HTTPS URL'),
      );
      await tester.tap(findUiText('CONTINUE'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('org-apply-continue')), findsOneWidget);
      await _scrollDownToKey(tester, const ValueKey('org-apply-feedback'));
      expect(find.text('Website must be a valid HTTPS URL'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('org-apply-edit-contact')));
      await tester.pumpAndSettle();
      expect(findUiText('Contact and verification'), findsOneWidget);
      await _scrollDownToKey(tester, const ValueKey('org-apply-website'));
      expect(_fieldText(tester, 'org-apply-website'), 'https://');
      await _enterText(
        tester,
        const ValueKey('org-apply-website'),
        'https://example.com',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('Website must be a valid HTTPS URL'), findsNothing);
    },
  );

  for (final contactStep in [false, true]) {
    testWidgets(
      'save for later reopens ${contactStep ? 'contact' : 'venue'} drafts on Venue',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final harness = await pumpApp(
          tester,
          auth: auth,
          home: _ApplicationHost(mediaPicker: FakeMediaPicker()),
          beforePump: (app) => app.go(Screen.orgApply),
        );
        await _completeVenue(tester);
        if (contactStep) {
          await _continueToContact(tester);
          await _enterText(
            tester,
            const ValueKey('org-apply-contact-name'),
            'Saved contact',
          );
          await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
          await tester.tap(find.byKey(const ValueKey('org-apply-agree')));
        }
        await _scrollUpToKey(tester, const ValueKey('org-apply-save'));
        await tester.tap(find.byKey(const ValueKey('org-apply-save')));
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.home);
        final draft = await harness.app.repository.myOrganizationApplication();
        expect(draft!.venue!.name, 'Night Heron Club');
        expect(draft.status, OrganizationApplicationStatus.draft);
        if (contactStep) expect(draft.contactName, 'Saved contact');
        harness.app.go(Screen.orgApply);
        await tester.pumpAndSettle();
        expect(findUiText('Organization and venue'), findsOneWidget);
        expect(_fieldText(tester, 'org-apply-name'), 'Night Heron Club');
        await _continueToContact(tester);
        if (contactStep) {
          expect(_fieldText(tester, 'org-apply-contact-name'), 'Saved contact');
        }
        await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('org-apply-agree')),
              )
              .value,
          isFalse,
        );
      },
    );
  }

  testWidgets(
    'verification photos stop at five and a removed slot can be reused',
    (tester) async {
      final picker = FakeMediaPicker();
      final auth = FakeAuthService();
      await auth.signInDemo();
      final harness = await pumpApp(
        tester,
        home: OrgApplyScreen(mediaPicker: picker),
        auth: auth,
      );
      await _completeVenue(tester);
      await _continueToContact(tester);
      for (var i = 0; i < 5; i++) {
        picker.nextPhoto = _licensePhoto;
        await _scrollDownToKey(tester, const ValueKey('org-apply-doc-add'));
        await tester.tap(find.byKey(const ValueKey('org-apply-doc-add')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('org-apply-doc-add')), findsNothing);
      final draft = (await harness.app.repository.myOrganizationApplication())!;
      expect(draft.documents, hasLength(5));
      final removeKey = ValueKey(
        'org-apply-doc-remove-${draft.documents.first.storageId}',
      );
      await _scrollUpToKey(tester, removeKey);
      await tester.tap(find.byKey(removeKey));
      await tester.pumpAndSettle();
      await _scrollDownToKey(tester, const ValueKey('org-apply-doc-add'));
      expect(find.byKey(const ValueKey('org-apply-doc-add')), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 402.0]) {
      testWidgets(
        'both steps fit $width wide in $brightness with large text and keyboard',
        (tester) async {
          await pumpApp(
            tester,
            home: Builder(
              builder: (context) => Theme(
                data: buildEpTheme(brightness),
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: const Scaffold(body: OrgApplyScreen()),
                ),
              ),
            ),
          );
          tester.view.physicalSize = Size(width, 740);
          await tester.pumpAndSettle();
          await _completeVenue(tester);
          await _scrollDownToKey(tester, const ValueKey('org-apply-capacity'));
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          await _enterText(tester, const ValueKey('org-apply-capacity'), '180');
          expect(
            tester
                .getBottomLeft(find.byKey(const ValueKey('org-apply-capacity')))
                .dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byType(StickyActionBar)).dy,
            ),
          );
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          await _continueToContact(tester);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          await _enterText(
            tester,
            const ValueKey('org-apply-website'),
            'https://example.com',
          );
          expect(
            tester
                .getBottomLeft(find.byKey(const ValueKey('org-apply-website')))
                .dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byType(StickyActionBar)).dy,
            ),
          );
          await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
          expect(
            tester
                .getBottomLeft(find.byKey(const ValueKey('org-apply-agree')))
                .dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byType(StickyActionBar)).dy,
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

final _licensePhoto = PickedMedia(
  bytes: Uint8List.fromList([1, 2, 3]),
  filename: 'license.jpg',
  contentType: 'image/jpeg',
  sizeBytes: 3,
);

class _ApplicationHost extends StatelessWidget {
  const _ApplicationHost({required this.mediaPicker, this.launch});

  final MediaPicker mediaPicker;
  final ExternalUrlLauncher? launch;

  @override
  Widget build(BuildContext context) {
    final screen = context.select<AppState, Screen>(
      (app) => app.current.screen,
    );
    return switch (screen) {
      Screen.home => const Material(child: SizedBox()),
      Screen.orgApplicationStatus => const OrgApplicationStatusScreen(),
      _ => OrgApplyScreen(mediaPicker: mediaPicker, launch: launch),
    };
  }
}

Future<void> _completeApplication(
  WidgetTester tester, {
  required FakeMediaPicker picker,
}) async {
  await _completeVenue(tester);
  await _continueToContact(tester);
  await _enterText(
    tester,
    const ValueKey('org-apply-contact-name'),
    'Rae Booker',
  );
  await _enterText(
    tester,
    const ValueKey('org-apply-email'),
    'rae@nightheron.example',
  );
  picker.nextPhoto = _licensePhoto;
  await _scrollDownToKey(tester, const ValueKey('org-apply-doc-add'));
  await tester.tap(find.byKey(const ValueKey('org-apply-doc-add')));
  await tester.pumpAndSettle();
  await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
}

Future<void> _completeVenue(WidgetTester tester) async {
  await _scrollDownToKey(tester, const ValueKey('org-apply-name'));
  await tester.enterText(
    find.byKey(const ValueKey('org-apply-name')),
    'Night Heron Club',
  );
  await _scrollDownToKey(tester, const ValueKey('org-apply-kind-bar'));
  await tester.tap(find.byKey(const ValueKey('org-apply-kind-bar')));
  await tester.pumpAndSettle();
  await _scrollDownToKey(tester, const ValueKey('org-apply-venue-address'));
  await tester.enterText(
    find.byKey(const ValueKey('org-apply-venue-address')),
    '22 V',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await _scrollDownToKey(
    tester,
    const ValueKey('org-apply-venue-suggestion-0'),
  );
  await tester.tap(find.byKey(const ValueKey('org-apply-venue-suggestion-0')));
  await tester.pumpAndSettle();
}

Future<void> _continueToContact(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(findUiText('CONTINUE'));
  await tester.pumpAndSettle();
  expect(findUiText('Contact and verification'), findsOneWidget);
}

String? _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller?.text;

Future<void> _enterText(
  WidgetTester tester,
  ValueKey<String> key,
  String text,
) async {
  await _scrollDownToKey(tester, key);
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

Future<void> _scrollDownToKey(WidgetTester tester, ValueKey<String> key) =>
    _scrollToKey(tester, key, const Offset(0, -500));

Future<void> _scrollUpToKey(WidgetTester tester, ValueKey<String> key) =>
    _scrollToKey(tester, key, const Offset(0, 500));

Future<void> _scrollToKey(
  WidgetTester tester,
  ValueKey<String> key,
  Offset dragOffset,
) async {
  final target = find.byKey(key);
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(Scrollable).first, dragOffset);
    await tester.pump();
  }
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: 1);
  await tester.pumpAndSettle();
}

Future<void> _continueToReview(WidgetTester tester) async {
  if (find.byKey(const ValueKey('org-apply-submit')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(findUiText('Continue'));
  await tester.pumpAndSettle();
  expect(findUiText('Review'), findsOneWidget);
}
