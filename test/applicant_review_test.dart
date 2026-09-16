import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/applicant_review.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('the review renders the band page under status and actions', (
    tester,
  ) async {
    await _pumpReview(tester, 'app1');
    final band = DemoData.bands['b1']!;

    expect(find.text(band.name.toUpperCase()), findsWidgets);
    expect(
      find.byKey(const ValueKey('band-profile-mini-header')),
      findsNothing,
    );
    final status = tester.widget<StatusPill>(
      find.byKey(const Key('applicant-review-status')),
    );
    expect(status.label, 'Submitted');
    expect(find.byKey(const Key('applicant-review-back')), findsOneWidget);

    final actions = tester.widget<EpBottomCta>(
      find.byKey(const Key('applicant-review-actions')),
    );
    expect(actions.hint, '${band.name} · Support · \$150.00');
    expect(
      tester
          .widget<EpMonoText>(find.byKey(const Key('applicant-review-message')))
          .text,
      'We can bring 40 people.',
    );
    expect(find.byKey(const Key('applicant-review-decline')), findsOneWidget);
    expect(find.byKey(const Key('applicant-review-shortlist')), findsOneWidget);
    expect(find.byKey(const Key('applicant-review-book')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('ABOUT'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ABOUT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortlist updates the status and swaps the pill in', (
    tester,
  ) async {
    final harness = await _pumpReview(tester, 'app1');

    await tester.tap(find.byKey(const Key('applicant-review-shortlist')));
    await tester.pumpAndSettle();

    expect(
      await _statusOf(harness.app, 'app1'),
      ArtistApplicationStatus.shortlisted,
    );
    expect(
      tester
          .widget<StatusPill>(find.byKey(const Key('applicant-review-status')))
          .label,
      'Shortlisted',
    );
    expect(find.byKey(const Key('applicant-review-shortlist')), findsNothing);
    expect(
      find.byKey(const Key('applicant-review-shortlisted')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('applicant-review-book')), findsOneWidget);
    expect(harness.app.current.screen, Screen.applicantReview);
  });

  testWidgets('decline confirms, reviews and pops back to the detail', (
    tester,
  ) async {
    final harness = await _pumpReview(tester, 'app1');

    await tester.tap(find.byKey(const Key('applicant-review-decline')));
    await tester.pumpAndSettle();
    expect(find.text('Decline this applicant?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
    await tester.pumpAndSettle();
    expect(
      await _statusOf(harness.app, 'app1'),
      ArtistApplicationStatus.submitted,
    );
    expect(harness.app.current.screen, Screen.applicantReview);

    await tester.tap(find.byKey(const Key('applicant-review-decline')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
    await tester.pumpAndSettle();

    expect(
      await _statusOf(harness.app, 'app1'),
      ArtistApplicationStatus.declined,
    );
    expect(harness.app.current.screen, Screen.orgOpportunity);
    expect(harness.app.current.param, 'opp1');
  });

  testWidgets('book opens the offer sheet and a sent offer pops back', (
    tester,
  ) async {
    final harness = await _pumpReview(tester, 'app2');
    (harness.app.repository as DemoRepository).demoPaymentsEnabled = true;
    expect(
      tester
          .widget<StatusPill>(find.byKey(const Key('applicant-review-status')))
          .label,
      'Shortlisted',
    );
    expect(find.byKey(const Key('applicant-review-shortlist')), findsNothing);

    await tester.tap(find.byKey(const Key('applicant-review-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send-offer-submit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-offer-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('send-offer-submit')), findsNothing);
    expect(harness.app.toast, 'Offer sent');
    expect(
      harness.app.organizationBookings.where(
        (booking) => booking.applicationId == 'app2',
      ),
      hasLength(1),
    );
    expect(harness.app.current.screen, Screen.orgOpportunity);
  });

  testWidgets('an offered application shows its booking instead of book', (
    tester,
  ) async {
    final harness = await _pumpReview(
      tester,
      'app2',
      beforePump: (app) async {
        await app.repository.sendOffer(
          applicationId: 'app2',
          grossMinor: 0,
          cancellationTemplate: CancellationTemplate.standard,
        );
      },
    );

    expect(
      tester
          .widget<StatusPill>(find.byKey(const Key('applicant-review-status')))
          .label,
      'Offered',
    );
    expect(find.byKey(const Key('applicant-review-book')), findsNothing);
    expect(find.byKey(const Key('applicant-review-decline')), findsNothing);
    final viewBooking = find.byKey(const Key('applicant-review-booking'));
    expect(viewBooking, findsOneWidget);
    await tester.tap(viewBooking);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
  });

  testWidgets('finance members see the status without a decision row', (
    tester,
  ) async {
    final harness = await _pumpReview(tester, 'app1');
    harness.app.myOrganizations = [
      OrganizationMembership(
        organization: DemoData.organizations['org1']!,
        role: OrganizationRole.finance,
      ),
    ];
    await enterOrganizer(tester, harness, 'org1');

    expect(find.byKey(const Key('applicant-review-decline')), findsNothing);
    expect(find.byKey(const Key('applicant-review-shortlist')), findsNothing);
    expect(find.byKey(const Key('applicant-review-book')), findsNothing);
    expect(find.byKey(const Key('applicant-review-actions')), findsOneWidget);
  });

  testWidgets('back pops to the opportunity detail', (tester) async {
    final harness = await _pumpReview(tester, 'app1');

    await tester.tap(find.byKey(const Key('applicant-review-back')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.orgOpportunity);
    expect(harness.app.current.param, 'opp1');
  });

  testWidgets('the review lays out on a 390x844 phone without overflow', (
    tester,
  ) async {
    await _pumpReview(tester, 'app1', size: const Size(390, 844));
    expect(find.byKey(const Key('applicant-review-book')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Pumps the review as the organizer of org1 with the detail underneath it on
/// the stack, so pops land on [Screen.orgOpportunity].
Future<AppHarness> _pumpReview(
  WidgetTester tester,
  String applicationId, {
  Future<void> Function(AppState app)? beforePump,
  Size size = const Size(402, 900),
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final harness = await pumpApp(
    tester,
    auth: auth,
    size: size,
    repository: DemoRepository(auth: auth),
    home: Scaffold(body: ApplicantReviewScreen(applicationId: applicationId)),
    beforePump: (app) async {
      await beforePump?.call(app);
      app.switchToOrganization('org1');
      app.openOrgOpportunity('opp1');
      app.openApplicantReview(applicationId);
    },
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<ArtistApplicationStatus> _statusOf(
  AppState app,
  String applicationId,
) async {
  final rows = await app.repository.applicantsFor('opp1');
  return rows
      .singleWhere((row) => row.application.id == applicationId)
      .application
      .status;
}
