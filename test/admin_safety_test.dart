import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/date_names.dart';
import 'package:earplug/models.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/admin_application.dart';
import 'package:earplug/screens/admin_bookings.dart';
import 'package:earplug/screens/admin_disputes.dart';
import 'package:earplug/screens/admin_queue.dart';
import 'package:earplug/screens/admin_safety.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';
import 'support/ui_test_helpers.dart';

Future<Booking> _acceptPrivateOffer(DemoRepository repository) async {
  final opportunity = (await repository.browseOpportunities(
    mode: OpportunityMode.privateBooking,
  )).items.single.opportunity;
  final applicationId = await repository.applyToOpportunity(
    opportunityId: opportunity.id,
    slotId: opportunity.slots.single.id,
    bandId: 'b1',
    message: 'Ready for the courtyard set.',
  );
  await repository.reviewApplication(
    applicationId: applicationId,
    action: ArtistApplicationReviewAction.shortlisted,
  );
  final offer = await repository.sendOffer(
    applicationId: applicationId,
    grossMinor: opportunity.slots.single.guaranteeMinor,
    cancellationTemplate: CancellationTemplate.standard,
  );
  await repository.respondToOffer(
    bookingId: offer.bookingId,
    accept: true,
    expectedRevision: offer.revision,
  );
  return (await repository.booking(offer.bookingId))!;
}

void main() {
  testWidgets('admin resolves an open report with an optional note', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final booking = await _acceptPrivateOffer(repository);
    final reportId = await repository.reportSafety(
      bookingId: booking.id,
      category: SafetyCategory.safety,
      text: 'The exit was blocked.',
    );
    repository.platformAdmin = true;
    final report = (await repository.openSafetyReports()).items.single;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminSafetyScreen(),
    );

    final row = find.byKey(Key('admin-safety-$reportId'));
    expect(row, findsOneWidget);
    expect(find.text('Safety'), findsOneWidget);
    expect(find.text(booking.opportunityTitle), findsOneWidget);
    expect(find.text(booking.bandName), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text(dateLabel(report.createdAt)), findsOneWidget);
    expect(find.text('The exit was blocked.'), findsOneWidget);

    await tester.tap(find.byKey(Key('admin-safety-open-$reportId')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, booking.id);

    await tester.tap(find.byKey(Key('admin-safety-resolve-$reportId')));
    await tester.pumpAndSettle();
    expect(findUiText('ADMIN NOTE'), findsOneWidget);
    expectNoFieldInCard(tester);
    await tester.enterText(
      find.byKey(const Key('admin-safety-note')),
      '  Confirmed that the exit is now clear.  ',
    );
    await tester.tap(find.byKey(const Key('admin-safety-resolve-confirm')));
    await tester.pumpAndSettle();

    expect(row, findsNothing);
    expect(find.text('No open safety reports.'), findsOneWidget);
    final resolved = (await repository.safetyReportsForBookingAdmin(
      booking.id,
    )).single;
    expect(resolved.status, 'resolved');
    expect(resolved.adminNote, 'Confirmed that the exit is now clear.');
    expect(resolved.resolvedAt, isNotNull);
  });

  testWidgets('admin can resolve a report without a note', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final booking = await _acceptPrivateOffer(repository);
    final reportId = await repository.reportSafety(
      bookingId: booking.id,
      category: SafetyCategory.harassment,
      text: 'A guest repeatedly harassed the performers.',
    );
    repository.platformAdmin = true;
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminSafetyScreen(),
    );

    expect(find.text('Harassment'), findsOneWidget);
    await tester.tap(find.byKey(Key('admin-safety-resolve-$reportId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-safety-resolve-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('No open safety reports.'), findsOneWidget);
    final resolved = (await repository.safetyReportsForBookingAdmin(
      booking.id,
    )).single;
    expect(resolved.status, 'resolved');
    expect(resolved.adminNote, isNull);
  });

  testWidgets('admin loads the next page of reports in newest-first order', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final booking = await _acceptPrivateOffer(repository);
    for (var index = 0; index < 26; index++) {
      await repository.reportSafety(
        bookingId: booking.id,
        category: SafetyCategory.other,
        text: 'Report $index',
      );
    }
    repository.platformAdmin = true;
    final firstPage = await repository.openSafetyReports();
    final nextPage = await repository.openSafetyReports(
      cursor: firstPage.continueCursor,
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminSafetyScreen(),
    );

    final newest = find.byKey(
      Key('admin-safety-${firstPage.items.first.reportId}'),
    );
    final next = find.byKey(Key('admin-safety-${firstPage.items[1].reportId}'));
    expect(tester.getTopLeft(newest).dy, lessThan(tester.getTopLeft(next).dy));
    final more = find.byKey(const Key('admin-safety-more'));
    await tester.scrollUntilVisible(
      more,
      600,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(more, findsNothing);
    final oldest = find.byKey(
      Key('admin-safety-${nextPage.items.single.reportId}'),
    );
    await tester.scrollUntilVisible(
      oldest,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(oldest, findsOneWidget);
  });

  for (final (label, screen, assertExtra)
      in <(String, Widget, void Function(WidgetTester)?)>[
        (
          'bookings',
          const AdminBookingsScreen(),
          (tester) {
            expect(
              find.byKey(const Key('admin-bookings-filter-all')),
              findsNothing,
            );
            expect(find.byKey(const Key('admin-bookings-more')), findsNothing);
          },
        ),
        (
          'disputes',
          const AdminDisputesScreen(),
          (tester) {
            expect(find.byKey(const Key('admin-disputes-more')), findsNothing);
            expectNoFieldInCard(tester);
          },
        ),
        ('the admin queue', const AdminQueueScreen(), null),
        (
          'an admin application',
          const AdminApplicationScreen(applicationId: 'application-review-1'),
          null,
        ),
        (
          'safety reports',
          const AdminSafetyScreen(),
          (tester) {
            expect(
              find.text('Only platform admins can view safety reports.'),
              findsOneWidget,
            );
            expect(find.byKey(const Key('admin-safety-more')), findsNothing);
          },
        ),
      ]) {
    testWidgets('non-admins cannot view $label', (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await pumpApp(tester, auth: auth, repository: repository, home: screen);
      await auth.signInDemo();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-not-authorized')), findsOneWidget);
      assertExtra?.call(tester);
    });
  }
}
