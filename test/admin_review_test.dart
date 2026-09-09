import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/date_names.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/admin_application.dart';
import 'package:earplug/screens/admin_queue.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

Future<({AppHarness harness, DemoRepository repository})> _pumpAdmin(
  WidgetTester tester,
  Widget home, {
  Future<void> Function(DemoRepository repository)? beforePump,
}) async {
  final auth = FakeAuthService();
  final repository = DemoRepository(auth: auth)..platformAdmin = true;
  await beforePump?.call(repository);
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: repository,
    home: home,
  );
  await harness.auth.signInDemo();
  await tester.pumpAndSettle();
  return (harness: harness, repository: repository);
}

Future<String> _submitHostApplication(DemoRepository repository) async {
  final saved = await repository.saveOrganizationApplicationDraft(
    kind: ApplicationKind.host,
    orgName: 'Jordan',
    orgType: OrganizationType.privateHost,
    contactName: 'Jordan',
    businessEmail: 'jordan@example.com',
    hostDisplayName: 'Jordan (host)',
    hostPhone: '415-555-0100',
    hostArea: 'Mission',
    hostAgreementAccepted: true,
  );
  await repository.submitOrganizationApplication(
    applicationId: saved.applicationId,
    expectedRevision: saved.revision,
  );
  return saved.applicationId;
}

Future<String> _submitPromoterApplication(
  DemoRepository repository, {
  bool organizerAgreementAccepted = false,
}) async {
  final saved = await repository.saveOrganizationApplicationDraft(
    kind: ApplicationKind.organization,
    orgName: 'Night Heron Collective',
    orgType: OrganizationType.promoter,
    contactName: 'Rae Booker',
    businessEmail: 'rae@nightheron.example',
  );
  await repository.submitOrganizationApplication(
    applicationId: saved.applicationId,
    expectedRevision: saved.revision,
    organizerAgreementAccepted: organizerAgreementAccepted,
  );
  return saved.applicationId;
}

void main() {
  testWidgets('admin queue lists submitted organizer applications', (
    tester,
  ) async {
    await _pumpAdmin(tester, const AdminQueueScreen());

    expect(
      find.byKey(const Key('admin-queue-row-application-review-1')),
      findsOneWidget,
    );
    expect(find.text('The Knockout'), findsOneWidget);
    expectNoFieldInCard(tester);
  });

  testWidgets('admin queue shows a promoter type pill for submitted drafts', (
    tester,
  ) async {
    late String applicationId;
    await _pumpAdmin(
      tester,
      const AdminQueueScreen(),
      beforePump: (repository) async {
        applicationId = await _submitPromoterApplication(repository);
      },
    );

    final typePill = find.byKey(Key('admin-row-$applicationId-type'));
    await tester.scrollUntilVisible(
      typePill,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('admin-queue-row-$applicationId')),
        matching: typePill,
      ),
      findsOneWidget,
    );
    expect(tester.widget<StatusPill>(typePill).label, 'PROMOTER');
    expect(tester.widget<StatusPill>(typePill).tone, EpStatusPillTone.neutral);
    expect(find.text('PROMOTER').hitTestable(), findsOneWidget);
  });

  testWidgets('admin promoter detail shows its type and omits venue section', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final applicationId = await _submitPromoterApplication(repository);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: AdminApplicationScreen(applicationId: applicationId),
    );

    final typePill = tester.widget<StatusPill>(
      find.byKey(const Key('admin-application-type')),
    );
    expect(typePill.label, 'PROMOTER');
    expect(typePill.tone, EpStatusPillTone.neutral);
    await tester.scrollUntilVisible(
      find.text('DOCUMENTS'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('VENUE'), findsNothing);
    expect(find.text('No venue provided.'), findsNothing);
  });

  for (final accepted in [false, true]) {
    testWidgets(
      'admin sees organizer agreement ${accepted ? 'acceptance' : 'not accepted'} without a venue',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final repository = DemoRepository(auth: auth)..platformAdmin = true;
        final applicationId = await _submitPromoterApplication(
          repository,
          organizerAgreementAccepted: accepted,
        );
        final application = (await repository.organizationApplication(
          applicationId,
        ))!;
        expect(application.kind, ApplicationKind.organization);
        expect(application.venue, isNull);
        await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          home: AdminApplicationScreen(applicationId: applicationId),
        );

        final agreement = find.byKey(
          const Key('admin-application-organizer-agreement'),
        );
        await tester.scrollUntilVisible(
          agreement,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(agreement, findsOneWidget);
        expect(
          find.descendant(
            of: agreement,
            matching: find.text(
              accepted ? 'ORGANIZER AGREEMENT ACCEPTED' : 'ORGANIZER AGREEMENT',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: agreement,
            matching: find.text(
              accepted
                  ? dateLabel(application.organizerAgreementAcceptedAt!)
                  : 'Not accepted',
            ),
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('admin application reveals exact venue details', (tester) async {
    await _pumpAdmin(
      tester,
      AdminApplicationScreen(
        applicationId: DemoData.submittedOrganizationApplication.id,
      ),
    );

    expect(find.text('VENUE'), findsOneWidget);
    expect(find.text('3223 Mission St, San Francisco'), findsOneWidget);
  });

  testWidgets('admin can start reviewing a submitted application', (
    tester,
  ) async {
    final result = await _pumpAdmin(
      tester,
      AdminApplicationScreen(
        applicationId: DemoData.submittedOrganizationApplication.id,
      ),
    );
    final repository = result.repository;

    await tester.tap(find.byKey(const Key('admin-review-start')));
    await tester.pumpAndSettle();

    final application = await repository.organizationApplication(
      'application-review-1',
    );
    expect(application?.status, OrganizationApplicationStatus.underReview);
  });

  testWidgets('admin can request information with a review note', (
    tester,
  ) async {
    final result = await _pumpAdmin(
      tester,
      AdminApplicationScreen(
        applicationId: DemoData.submittedOrganizationApplication.id,
      ),
    );
    final repository = result.repository;

    await tester.tap(find.byKey(const Key('admin-review-request-info')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-review-note')),
      'Please send proof of venue operation.',
    );
    expectNoFieldInCard(tester);
    await tester.tap(find.byKey(const Key('admin-review-confirm')));
    await tester.pumpAndSettle();

    final application = await repository.organizationApplication(
      'application-review-1',
    );
    expect(application?.status, OrganizationApplicationStatus.needsInfo);
    expect(application?.reviewNote, 'Please send proof of venue operation.');

    await tester.scrollUntilVisible(
      find.text('Note: Please send proof of venue operation.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Note: Please send proof of venue operation.'),
      findsOneWidget,
    );
  });

  testWidgets('approval creates an organization and removes the queue row', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: AdminApplicationScreen(
        applicationId: DemoData.submittedOrganizationApplication.id,
      ),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-review-approve')));
    await tester.pumpAndSettle();
    expect(
      find.text('This creates the organization and its venue.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('admin-review-confirm')));
    await tester.pumpAndSettle();

    final application = await repository.organizationApplication(
      'application-review-1',
    );
    final resultingOrganizationId = application?.resultingOrganizationId;
    expect(application?.status, OrganizationApplicationStatus.approved);
    expect(resultingOrganizationId, isNotNull);
    expect(await repository.organization(resultingOrganizationId!), isNotNull);

    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminQueueScreen(),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('admin-queue-row-application-review-1')),
      findsNothing,
    );
    expect(find.text('No submitted applications.'), findsOneWidget);
  });

  testWidgets('non-admins cannot view the admin queue', (tester) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminQueueScreen(),
    );

    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-not-authorized')), findsOneWidget);
  });

  testWidgets('admin queue distinguishes and filters host applications', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final applicationId = await _submitHostApplication(repository);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminQueueScreen(),
    );

    final hostRow = find.byKey(Key('admin-queue-row-$applicationId'));
    final organizerRow = find.byKey(
      const Key('admin-queue-row-application-review-1'),
    );
    expect(hostRow, findsOneWidget);
    expect(organizerRow, findsOneWidget);
    expect(find.byKey(Key('admin-row-$applicationId-host')), findsOneWidget);
    expect(find.byKey(Key('admin-row-$applicationId-type')), findsNothing);
    expect(
      find.descendant(of: hostRow, matching: find.text('Jordan (host)')),
      findsOneWidget,
    );
    final hostCount = tester
        .widgetList<EpStatCard>(find.byType(EpStatCard))
        .singleWhere((card) => card.label == 'HOSTS');
    expect(hostCount.value, '1');

    await tester.tap(find.byKey(const Key('admin-queue-kind-host')));
    await tester.pumpAndSettle();
    expect(hostRow, findsOneWidget);
    expect(organizerRow, findsNothing);

    await tester.tap(find.byKey(const Key('admin-queue-kind-organization')));
    await tester.pumpAndSettle();
    expect(hostRow, findsNothing);
    expect(organizerRow, findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-queue-kind-all')));
    await tester.pumpAndSettle();
    expect(hostRow, findsOneWidget);
    expect(organizerRow, findsOneWidget);
    expectNoFieldInCard(tester);
  });

  testWidgets('admin reviews host details and approves a host account', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final applicationId = await _submitHostApplication(repository);
    final submitted = (await repository.organizationApplication(
      applicationId,
    ))!;
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: AdminApplicationScreen(applicationId: applicationId),
    );

    await tester.scrollUntilVisible(
      find.text('HOST DETAILS'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('VENUE'), findsNothing);
    expect(find.text('Jordan (host)'), findsOneWidget);
    expect(find.text('415-555-0100'), findsOneWidget);
    expect(find.text('Mission'), findsOneWidget);
    expect(find.text('AGREEMENT ACCEPTED'), findsOneWidget);
    expect(
      find.byKey(const Key('admin-application-organizer-agreement')),
      findsNothing,
    );
    expect(
      find.text(dateLabel(submitted.hostAgreementAcceptedAt!)),
      findsOneWidget,
    );
    expect(find.text('CONTACT EMAIL'), findsOneWidget);
    expect(find.text('jordan@example.com'), findsWidgets);
    expectNoFieldInCard(tester);

    await tester.tap(find.byKey(const Key('admin-review-approve')));
    await tester.pumpAndSettle();
    expect(find.text('This creates the host account.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-review-confirm')));
    await tester.pumpAndSettle();

    final approved = (await repository.organizationApplication(applicationId))!;
    expect(approved.status, OrganizationApplicationStatus.approved);
    expect(approved.resultingOrganizationId, isNotNull);
    final organization = (await repository.organization(
      approved.resultingOrganizationId!,
    ))!;
    expect(organization.orgType, OrganizationType.privateHost);
    expect(approved.resultingVenueId, isNull);
    final createdText = find.text(
      'Host account created — ${organization.name} (${organization.slug})',
    );
    await tester.scrollUntilVisible(
      createdText,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(createdText, findsOneWidget);
    expect(find.text('VENUE'), findsNothing);
  });

  testWidgets('admin queue opens safety reports', (tester) async {
    final result = await _pumpAdmin(tester, const AdminQueueScreen());
    final entry = find.byKey(const Key('admin-safety-entry'));
    expect(tester.widget<EpButton>(entry).kind, EpButtonKind.outline);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(result.harness.app.current.screen, Screen.adminSafety);
  });

  testWidgets('admin queue opens disputes', (tester) async {
    final result = await _pumpAdmin(tester, const AdminQueueScreen());
    final entry = find.byKey(const Key('admin-disputes-entry'));
    expect(tester.widget<EpButton>(entry).kind, EpButtonKind.outline);

    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(result.harness.app.current.screen, Screen.adminDisputes);
  });

  testWidgets('admin queue opens bookings', (tester) async {
    final result = await _pumpAdmin(tester, const AdminQueueScreen());
    final entry = find.byKey(const Key('admin-bookings-entry'));
    expect(tester.widget<EpButton>(entry).kind, EpButtonKind.outline);

    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(result.harness.app.current.screen, Screen.adminBookings);
  });

  testWidgets('non-admins cannot view an admin application', (tester) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminApplicationScreen(applicationId: 'application-review-1'),
    );

    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-not-authorized')), findsOneWidget);
  });
}
