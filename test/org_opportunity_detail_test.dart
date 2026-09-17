import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/org_opportunity_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('the detail leads with title, meta line and slot fill', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester);
    final opportunity = DemoData.opportunities['opp1']!;

    expect(find.text(opportunity.title.toUpperCase()), findsOneWidget);

    final meta = find.byKey(const Key('org-opportunity-meta'));
    final metaText = tester.widget<Text>(meta);
    final startsAt = opportunity.startsAt.toLocal();
    final time = TimeOfDay.fromDateTime(startsAt).format(tester.element(meta));
    expect(
      metaText.textSpan!.toPlainText(),
      '${dateLabel(startsAt).toUpperCase()} · $time · THE FOGHORN CLUB · ACTIVE',
    );
    final statusSpan = (metaText.textSpan! as TextSpan).children!.single;
    expect((statusSpan as TextSpan).text, 'ACTIVE');
    expect(
      statusSpan.style!.color,
      Theme.of(tester.element(meta)).extension<EpPalette>()!.accent,
    );

    expect(
      tester
          .widget<EpEyebrow>(
            find.byKey(const Key('org-opportunity-slots-label')),
          )
          .text,
      'Slots — 0 of 2 filled',
    );
    final bar = tester.widget<EpReadinessBar>(
      find.byKey(const Key('org-opportunity-fill-bar')),
    );
    expect(bar.done, 0);
    expect(bar.total, 2);
    expect(find.text('APPLICANTS · 2'), findsOneWidget);
    expect(find.text('CONFIRMED · 0'), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets('applicants carry their state-specific actions', (tester) async {
    final harness = await _pumpDetail(tester);

    // app1 is submitted: shortlist, book and review.
    expect(find.byKey(const Key('applicant-app1')), findsOneWidget);
    expect(find.byKey(const Key('applicant-app1-shortlist')), findsOneWidget);
    expect(find.byKey(const Key('applicant-app1-book')), findsOneWidget);
    expect(find.byKey(const Key('applicant-app1-review')), findsOneWidget);
    expect(find.byKey(const Key('applicant-app1-profile')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('applicant-app1')),
        matching: find.text(r'GARAGE · SURF PUNK · $150.00'),
      ),
      findsOneWidget,
    );

    // app2 is shortlisted: pill plus book and review.
    expect(find.byKey(const Key('applicant-app2-shortlist')), findsNothing);
    expect(_applicantPill(tester, 'app2').label, 'Shortlisted');
    expect(find.byKey(const Key('applicant-app2-book')), findsOneWidget);
    expect(find.byKey(const Key('applicant-app2-review')), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets('the name row and chevron open the band profile', (tester) async {
    final harness = await _pumpDetail(tester);

    await tester.tap(find.byKey(const Key('applicant-app1-profile')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.band);
    expect(harness.app.current.param, 'b1');
    harness.app.dispose();
  });

  testWidgets('review opens the applicant review route', (tester) async {
    final harness = await _pumpDetail(tester);

    await tester.tap(find.byKey(const Key('applicant-app1-review')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.applicantReview);
    expect(harness.app.current.param, 'app1');
    harness.app.dispose();
  });

  testWidgets('shortlist reviews the application and updates the row', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester);

    await tester.tap(find.byKey(const Key('applicant-app1-shortlist')));
    await tester.pumpAndSettle();

    final rows = await harness.app.repository.applicantsFor('opp1');
    expect(
      rows
          .singleWhere((row) => row.application.id == 'app1')
          .application
          .status,
      ArtistApplicationStatus.shortlisted,
    );
    expect(_applicantPill(tester, 'app1').label, 'Shortlisted');
    expect(find.byKey(const Key('applicant-app1-shortlist')), findsNothing);
    expect(find.byKey(const Key('applicant-app1-book')), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets('book opens the offer sheet and a sent offer shows its booking', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester);
    (harness.app.repository as DemoRepository).demoPaymentsEnabled = true;

    await tester.tap(find.byKey(const Key('applicant-app2-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send-offer-submit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-offer-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('send-offer-submit')), findsNothing);
    expect(harness.app.toast, 'Offer sent');
    expect(_applicantPill(tester, 'app2').label, 'Offer sent');
    expect(find.byKey(const Key('applicant-app2-book')), findsNothing);
    final booking = harness.app.organizationBookings.singleWhere(
      (booking) => booking.applicationId == 'app2',
    );
    final viewBooking = find.byKey(const Key('applicant-app2-booking'));
    expect(viewBooking, findsOneWidget);
    await tester.ensureVisible(viewBooking);
    await tester.tap(viewBooking);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, booking.id);
    harness.app.dispose();
  });

  testWidgets('booking a fresh applicant shortlists them on the way in', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester);

    await tester.tap(find.byKey(const Key('applicant-app1-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send-offer-submit')), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('send-offer-submit')), findsNothing);
    expect(_applicantPill(tester, 'app1').label, 'Shortlisted');
    expect(harness.app.toast, isNot('Offer sent'));
    harness.app.dispose();
  });

  testWidgets('a declined applicant is dimmed and carries no actions', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester, screen: const SizedBox.shrink());
    await harness.app.repository.reviewApplication(
      applicationId: 'app1',
      action: ArtistApplicationReviewAction.declined,
    );
    await _pumpDetailAgain(tester, harness);

    final row = find.byKey(const Key('applicant-app1'));
    expect(row, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: row, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, .4);
    expect(
      find.descendant(of: row, matching: find.text('DECLINED')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('applicant-app1-shortlist')), findsNothing);
    expect(find.byKey(const Key('applicant-app1-book')), findsNothing);
    expect(find.byKey(const Key('applicant-app1-review')), findsNothing);
    expect(find.text('APPLICANTS · 2'), findsOneWidget);

    // The shortlisted applicant keeps its actions at full strength.
    final other = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const Key('applicant-app2')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(other.opacity, 1);
    harness.app.dispose();
  });

  testWidgets('an accepted offer fills a slot and lists the confirmed act', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester, screen: const SizedBox.shrink());
    final repository = harness.app.repository;
    final result = await repository.sendOffer(
      applicationId: 'app2',
      grossMinor: 0,
      cancellationTemplate: CancellationTemplate.standard,
    );
    await repository.respondToOffer(
      bookingId: result.bookingId,
      accept: true,
      expectedRevision: result.revision,
    );
    harness.app.organizationBookings = [];
    await _pumpDetailAgain(tester, harness);

    expect(
      tester
          .widget<EpEyebrow>(
            find.byKey(const Key('org-opportunity-slots-label')),
          )
          .text,
      'Slots — 1 of 2 filled',
    );
    final bar = tester.widget<EpReadinessBar>(
      find.byKey(const Key('org-opportunity-fill-bar')),
    );
    expect(bar.done, 1);
    expect(bar.total, 2);
    // The booked applicant leaves the applicant list for the confirmed one.
    expect(find.text('APPLICANTS · 1'), findsOneWidget);
    expect(find.byKey(const Key('applicant-app2')), findsNothing);
    expect(find.text('CONFIRMED · 1'), findsOneWidget);
    final confirmed = find.byKey(
      const Key('org-opportunity-confirmed-opp1-headliner'),
    );
    await tester.ensureVisible(confirmed);
    expect(confirmed, findsOneWidget);
    expect(
      find.descendant(
        of: confirmed,
        matching: find.text(DemoData.bands['b2']!.name.toUpperCase()),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: confirmed,
        matching: find.text(r'Headliner · $300.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: confirmed, matching: find.text('BOOKED')),
      findsOneWidget,
    );
    harness.app.dispose();
  });

  testWidgets('edit opportunity opens the editor for this opportunity', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester);

    final edit = find.byKey(const Key('org-opportunity-edit'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'opp1');
    harness.app.dispose();
  });

  testWidgets('finance members read the applicants without actions', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester);
    harness.app.myOrganizations = [
      OrganizationMembership(
        organization: DemoData.organizations['org1']!,
        role: OrganizationRole.finance,
      ),
    ];
    await enterOrganizer(tester, harness, 'org1');

    expect(find.byKey(const Key('applicant-app1')), findsOneWidget);
    expect(find.byKey(const Key('applicant-app2')), findsOneWidget);
    expect(find.byKey(const Key('applicant-app1-shortlist')), findsNothing);
    expect(find.byKey(const Key('applicant-app1-book')), findsNothing);
    expect(find.byKey(const Key('applicant-app1-review')), findsNothing);
    expect(find.byKey(const Key('applicant-app2-book')), findsNothing);
    expect(find.byKey(const Key('applicant-app2-review')), findsNothing);
    expect(_applicantPill(tester, 'app2').label, 'Shortlisted');
    harness.app.dispose();
  });

  testWidgets('back returns to the previous screen', (tester) async {
    final harness = await _pumpDetail(tester);

    await tester.tap(find.byKey(const Key('org-opportunity-back')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.orgOpportunities);
    harness.app.dispose();
  });

  testWidgets('the detail lays out on a 390x844 phone without overflow', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester, size: const Size(390, 844));
    (harness.app.repository as DemoRepository).demoPaymentsEnabled = true;

    await tester.tap(find.byKey(const Key('applicant-app2-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-offer-submit')));
    await tester.pumpAndSettle();
    final edit = find.byKey(const Key('org-opportunity-edit'));
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    harness.app.dispose();
  });
}

Future<AppHarness> _pumpDetail(
  WidgetTester tester, {
  Widget screen = const OrgOpportunityDetailScreen(opportunityId: 'opp1'),
  DemoRepository Function(FakeAuthService auth)? repositoryBuilder,
  Size size = const Size(402, 900),
}) async {
  final harness = await pumpOrganizerScreen(
    tester,
    screen,
    repositoryBuilder: repositoryBuilder,
    size: size,
  );
  harness.app.openOrgOpportunity('opp1');
  await tester.pumpAndSettle();
  return harness;
}

/// Mounts the detail over an app whose repository was changed after the
/// first pump, so the screen loads the changed data fresh.
Future<void> _pumpDetailAgain(WidgetTester tester, AppHarness harness) =>
    rehostApp(
      tester,
      harness.app,
      const OrgOpportunityDetailScreen(opportunityId: 'opp1'),
    );

EpBadge _applicantPill(WidgetTester tester, String applicationId) =>
    tester.widget<EpBadge>(
      find.descendant(
        of: find.byKey(ValueKey('applicant-$applicationId')),
        matching: find.byType(EpBadge),
      ),
    );
