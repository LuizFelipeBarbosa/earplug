import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/admin_application.dart';
import 'package:earplug/screens/admin_queue.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

Future<({AppHarness harness, DemoRepository repository})> _pumpAdmin(
  WidgetTester tester,
  Widget home,
) async {
  final auth = FakeAuthService();
  final repository = DemoRepository(auth: auth)..platformAdmin = true;
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
