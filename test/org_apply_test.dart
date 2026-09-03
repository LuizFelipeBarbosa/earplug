import 'dart:typed_data';

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/org_application_status.dart';
import 'package:earplug/screens/org_apply.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_map.dart';
import 'package:earplug/widgets/status_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  testWidgets('full organizer application submits and can be withdrawn', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final picker = FakeMediaPicker();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: OrgApplyScreen(mediaPicker: picker),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    await _fillOrganization(tester);
    await _fillLocation(tester);
    await _fillContact(tester);

    picker.nextPhoto = PickedMedia(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'license.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 3,
    );
    await _addDocument(tester);

    final reviewStep = find.byKey(const Key('org-apply-step-review'));
    await tester.ensureVisible(reviewStep);
    await tester.tap(reviewStep);
    await tester.pumpAndSettle();

    EpButton submit = tester.widget(find.byKey(const Key('org-apply-submit')));
    expect(submit.kind, EpButtonKind.disabled);
    expect(submit.onTap, isNull);

    await tester.tap(find.byKey(const Key('org-apply-agree')));
    await tester.pump();
    submit = tester.widget(find.byKey(const Key('org-apply-submit')));
    expect(submit.kind, EpButtonKind.filled);
    expect(submit.onTap, isNotNull);

    await tester.tap(find.byKey(const Key('org-apply-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      (await repository.myOrganizationApplication())?.status,
      OrganizationApplicationStatus.submitted,
    );

    final statusHarness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OrgApplicationStatusScreen(),
    );
    final timeline = tester.widget<StatusTimeline>(
      find.byKey(const Key('org-status-timeline')),
    );
    expect(timeline.steps.first.label, 'Submitted');
    expect(timeline.steps.first.state, TimelineStepState.done);

    await tester.tap(find.text('WITHDRAW APPLICATION'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('org-status-withdraw-confirm')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('org-status-withdraw-confirm')));
    await tester.pumpAndSettle();

    expect(
      (await repository.myOrganizationApplication())?.status,
      OrganizationApplicationStatus.withdrawn,
    );
    expect(statusHarness.app.current.screen, Screen.home);
  });

  testWidgets('needs info shows its note and prefills the editable wizard', (
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
        neighborhood: 'Mission',
        city: 'San Francisco',
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

    final statusHarness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OrgApplicationStatusScreen(),
    );
    expect(
      find.textContaining('Add a photo of your liquor license.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('org-status-edit')), findsOneWidget);

    await tester.tap(find.byKey(const Key('org-status-edit')));
    await tester.pumpAndSettle();
    expect(statusHarness.app.current.screen, Screen.orgApply);

    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OrgApplyScreen(),
    );
    final organizationStep = find.byKey(
      const Key('org-apply-step-organization'),
    );
    await tester.tap(organizationStep);
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(
      find.byKey(const Key('org-apply-name')),
    );
    expect(nameField.controller?.text, 'Night Heron Club');
    final websiteField = tester.widget<TextField>(
      find.byKey(const Key('org-apply-website')),
    );
    expect(websiteField.controller?.text, 'https://nightheron.example');
  });
}

Future<void> _fillOrganization(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('org-apply-step-organization')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('org-apply-name')),
    'Night Heron Club',
  );
  await tester.tap(find.widgetWithText(FilterChip, 'CLUB'));
  await tester.enterText(
    find.byKey(const Key('org-apply-website')),
    'https://nightheron.example',
  );
  await tester.tap(find.byKey(const Key('org-apply-organization-done')));
  await tester.pumpAndSettle();
}

Future<void> _fillLocation(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('org-apply-step-location')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('org-apply-venue-name')),
    'Night Heron Club',
  );
  await tester.enterText(
    find.byKey(const Key('org-apply-venue-address')),
    '22 Valencia Street',
  );
  await tester.enterText(
    find.byKey(const Key('org-apply-venue-area')),
    'Mission',
  );
  final map = tester.widget<EpMap>(
    find.descendant(
      of: find.byKey(const Key('org-apply-venue-map')),
      matching: find.byType(EpMap),
    ),
  );
  map.options.onTap!(
    const TapPosition(Offset.zero, Offset.zero),
    const LatLng(37.76, -122.42),
  );
  await tester.pump();

  final neighborhood = find.byKey(const Key('org-apply-neighborhood'));
  await tester.ensureVisible(neighborhood);
  await tester.enterText(neighborhood, 'Mission');
  final city = find.byKey(const Key('org-apply-city'));
  await tester.ensureVisible(city);
  await tester.enterText(city, 'San Francisco');
  final capacity = find.byKey(const Key('org-apply-capacity'));
  await tester.ensureVisible(capacity);
  await tester.enterText(capacity, '180');
  final clubType = find.widgetWithText(FilterChip, 'CLUB');
  await tester.ensureVisible(clubType);
  await tester.tap(clubType);
  await tester.ensureVisible(find.byKey(const Key('org-apply-location-done')));
  await tester.tap(find.byKey(const Key('org-apply-location-done')));
  await tester.pumpAndSettle();
}

Future<void> _fillContact(WidgetTester tester) async {
  final contactStep = find.byKey(const Key('org-apply-step-contact'));
  await tester.ensureVisible(contactStep);
  await tester.tap(contactStep);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('org-apply-contact-name')),
    'Rae Booker',
  );
  await tester.enterText(
    find.byKey(const Key('org-apply-email')),
    'rae@nightheron.example',
  );
  await tester.enterText(
    find.byKey(const Key('org-apply-phone')),
    '415-555-0101',
  );
  await tester.tap(find.byKey(const Key('org-apply-contact-done')));
  await tester.pumpAndSettle();
}

Future<void> _addDocument(WidgetTester tester) async {
  final documentsStep = find.byKey(const Key('org-apply-step-documents'));
  await tester.ensureVisible(documentsStep);
  await tester.tap(documentsStep);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('org-apply-doc-add')));
  await tester.pumpAndSettle();
  expect(find.text('image/jpeg'), findsOneWidget);
  await tester.tap(find.text('DONE'));
  await tester.pumpAndSettle();
}
