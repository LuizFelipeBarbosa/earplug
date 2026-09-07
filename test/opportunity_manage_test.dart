import 'package:earplug/app_state.dart';
import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/door_mode.dart';
import 'package:earplug/screens/opportunity_applicants.dart';
import 'package:earplug/screens/org_opportunities.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/design_rules.dart';
import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  testWidgets('opportunities group drafts and open listings with counts', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );
    final openSection = find.byKey(const ValueKey('org-opps-section-OPEN'));
    final draftsSection = find.byKey(const ValueKey('org-opps-section-DRAFTS'));
    final openCard = find.byKey(const ValueKey('org-opp-opp1'));
    final draftCard = find.byKey(const ValueKey('org-opp-opp2'));

    expect(find.text('OPPORTUNITIES'), findsOneWidget);
    expect(find.text('Post a slot. Find your next artist.'), findsOneWidget);
    expect(find.text('NEW OPPORTUNITY'), findsOneWidget);
    expect(
      tester
          .widget<SectionBar>(
            find.descendant(of: openSection, matching: find.byType(SectionBar)),
          )
          .count,
      2,
    );
    expect(
      tester
          .widget<SectionBar>(
            find.descendant(
              of: draftsSection,
              matching: find.byType(SectionBar),
            ),
          )
          .label,
      'DRAFTS',
    );
    expect(
      find.descendant(of: openSection, matching: openCard),
      findsOneWidget,
    );
    expect(
      find.descendant(of: draftsSection, matching: draftCard),
      findsOneWidget,
    );
    expect(
      find.descendant(of: openCard, matching: find.text('2 applied')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openCard,
        matching: find.text(DemoData.opportunities['opp1']!.title),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openCard,
        matching: find.text(r'Headliner $300.00 · Support $150.00'),
      ),
      findsOneWidget,
    );
    harness.app.dispose();
  });

  testWidgets('host requests use host copy and a private event caption', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: OrgOpportunitiesScreen()),
      beforePump: (app) => app.switchToOrganization('org2'),
    );

    expect(find.text('REQUESTS'), findsOneWidget);
    expect(find.text('Post a request. Find your artist.'), findsOneWidget);
    expect(find.text('NEW REQUEST'), findsOneWidget);
    expect(find.text('OPPORTUNITIES'), findsNothing);
    expect(find.text('Post a slot. Find your next artist.'), findsNothing);
    expect(find.text('NEW OPPORTUNITY'), findsNothing);
    final privateCard = find.byKey(const ValueKey('org-opp-opp-private'));
    await tester.ensureVisible(privateCard);
    expect(
      find.descendant(
        of: privateCard,
        matching: find.text('Private event · Mission District'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Venue TBD'), findsNothing);
    expectNoFieldInCard(tester);

    final newRequest = find.byKey(const Key('org-opps-new'));
    await tester.ensureVisible(newRequest);
    await tester.tap(newRequest);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'new');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'published paid opportunities load sales and offer a door action',
    (tester) async {
      final harness = await _pumpOrganizerScreen(
        tester,
        const SizedBox.shrink(),
        repositoryBuilder: (auth) =>
            _PublishedOpportunityRepository(auth: auth),
      );
      final repository =
          harness.app.repository as _PublishedOpportunityRepository;
      final reservation = await repository.reserveTickets(
        gigId: 'g8',
        quantity: 2,
      );
      final checkout = await repository.startTicketCheckout(
        reservation.orderId,
      );
      await repository.simulateTicketCheckoutCompleted(checkout.sessionId);
      final expected = await repository.ticketSalesForGig('g8');
      final readsBeforeScreen = repository.salesReads;
      expect(expected.sold, greaterThan(0));
      expect(expected.netMinor, greaterThan(0));
      expect(harness.app.salesFor('g8'), isNull);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: harness.app,
          child: MaterialApp(
            theme: buildEpTheme(),
            home: const Scaffold(body: OrgOpportunitiesScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final caption = find.byKey(const Key('org-opp-sales-opp1'));
      await tester.ensureVisible(caption);
      expect(
        tester.widget<Text>(caption).data,
        '${expected.sold}/${expected.capacity} sold · ${expected.net.label} net',
      );
      expect(repository.salesReads, readsBeforeScreen + 1);
      expectNoFieldInCard(tester);

      await harness.app.refreshOpportunities('org1');
      await tester.pumpAndSettle();
      expect(repository.salesReads, readsBeforeScreen + 1);
      await _chooseOpportunityAction(tester, 'opp1', 'DOOR');
      expect(find.byType(DoorModeScreen), findsOneWidget);
      expect(
        tester.widget<DoorModeScreen>(find.byType(DoorModeScreen)).launch.gigId,
        'g8',
      );
      expect(find.text(DemoData.opportunities['opp1']!.title), findsOneWidget);
      expect(tester.takeException(), isNull);
      harness.app.dispose();
    },
  );

  for (final published in [false, true]) {
    testWidgets(
      published
          ? 'published RSVP opportunities offer DOOR without loading sales'
          : 'paid opportunities without a published gig have no sales or DOOR',
      (tester) async {
        final harness = await _pumpOrganizerScreen(
          tester,
          const OrgOpportunitiesScreen(),
          repositoryBuilder: (auth) => _PublishedOpportunityRepository(
            auth: auth,
            published: published,
            ticketing: published
                ? OpportunityTicketing.rsvp
                : OpportunityTicketing.paid,
          ),
        );
        final repository =
            harness.app.repository as _PublishedOpportunityRepository;
        expect(repository.salesReads, 0);
        expect(find.byKey(const Key('org-opp-sales-opp1')), findsNothing);
        final card = find.byKey(const ValueKey('org-opp-opp1'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(find.text('DOOR'), published ? findsOneWidget : findsNothing);
        harness.app.dispose();
      },
    );
  }

  testWidgets('new opportunity opens the editor with the new parameter', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await tester.tap(find.byKey(const Key('org-opps-new')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'new');
    harness.app.dispose();
  });

  testWidgets('close applications moves the opportunity to CLOSED', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await _chooseOpportunityAction(tester, 'opp1', 'CLOSE APPLICATIONS');

    final card = find.byKey(const ValueKey('org-opp-opp1'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final closedSection = find.byKey(const ValueKey('org-opps-section-CLOSED'));
    expect(find.descendant(of: closedSection, matching: card), findsOneWidget);
    expect(
      tester
          .widget<SectionBar>(
            find.descendant(
              of: closedSection,
              matching: find.byType(SectionBar),
            ),
          )
          .label,
      'CLOSED',
    );
    final opportunities = await harness.app.repository.manageOpportunities(
      'org1',
    );
    expect(
      opportunities
          .singleWhere((opportunity) => opportunity.id == 'opp1')
          .status,
      OpportunityStatus.applicationsClosed,
    );
    expect(harness.app.toast, 'Applications closed.');
    harness.app.dispose();
  });

  testWidgets('delete draft removes the opportunity without another dialog', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await _chooseOpportunityAction(tester, 'opp2', 'DELETE DRAFT');

    expect(find.byKey(const ValueKey('org-opp-opp2')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(harness.app.toast, 'Draft deleted.');
    harness.app.dispose();
  });

  testWidgets('duplicate adds a draft with no active applications', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await _chooseOpportunityAction(tester, 'opp1', 'DUPLICATE');

    final duplicate = harness.app
        .opportunitiesFor('org1')
        .singleWhere(
          (opportunity) => !DemoData.opportunities.containsKey(opportunity.id),
        );
    expect(duplicate.status, OpportunityStatus.draft);
    expect(duplicate.applicationCount, 0);
    expect(find.byKey(ValueKey('org-opp-${duplicate.id}')), findsOneWidget);
    expect(harness.app.toast, 'Opportunity duplicated.');
    harness.app.dispose();
  });

  testWidgets('cancel opportunity requires confirmation', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await _chooseOpportunityAction(tester, 'opp1', 'CANCEL…');
    expect(find.text('Cancel opportunity?'), findsOneWidget);
    expect(
      (await harness.app.repository.opportunity('opp1'))!.status,
      OpportunityStatus.open,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
    await tester.pumpAndSettle();

    final opportunity = await harness.app.repository.opportunity('opp1');
    expect(opportunity!.status, OpportunityStatus.cancelled);
    expect(opportunity.applicationCount, 0);
    expect(harness.app.toast, 'Opportunity cancelled.');
    harness.app.dispose();
  });

  testWidgets('reopen uses a picked deadline and returns to OPEN', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );
    await _chooseOpportunityAction(tester, 'opp1', 'CLOSE APPLICATIONS');

    await _chooseOpportunityAction(tester, 'opp1', 'REOPEN');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final opportunity = await harness.app.repository.opportunity('opp1');
    expect(opportunity!.status, OpportunityStatus.open);
    expect(
      DateUtils.isSameDay(opportunity.applicationsCloseAt, DateTime.now()),
      isTrue,
    );
    expect(harness.app.toast, 'Opportunity reopened.');
    harness.app.dispose();
  });

  testWidgets('reopen is offered and works for a booking-status opportunity', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
      repositoryBuilder: (auth) => _BookingStatusRepository(auth: auth),
    );
    final card = find.byKey(const ValueKey('org-opp-opp1'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('REOPEN'), findsOneWidget);

    await tester.tap(find.text('REOPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final opportunity = await harness.app.repository.opportunity('opp1');
    // Only the list shows booking; the stored demo record is unchanged, and
    // DemoRepository reopens unconditionally. These assertions check the UI
    // flow; the Convex tests cover the booking-specific refusal rule.
    expect(harness.app.toast, 'Opportunity reopened.');
    expect(opportunity!.status, OpportunityStatus.open);
    harness.app.dispose();
  });

  testWidgets('applicants show both bands and the matching slot guarantees', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );
    final support = find.byKey(const ValueKey('applicant-app1'));
    final headliner = find.byKey(const ValueKey('applicant-app2'));

    expect(support, findsOneWidget);
    expect(headliner, findsOneWidget);
    expect(
      find.descendant(of: support, matching: find.text(r'Slot $150.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: headliner, matching: find.text(r'Slot $300.00')),
      findsOneWidget,
    );
    expect(find.text('2 applicants'), findsOneWidget);
    expect(find.text('We can bring 40 people.'), findsOneWidget);
    expect(
      find.text(DemoData.organizationMembers[DemoData.demoUserId]!.email!),
      findsOneWidget,
    );
    harness.app.dispose();
  });

  testWidgets('only shortlisted applicants have a primary send offer action', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    expect(find.byKey(const ValueKey('applicant-app2-offer')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('applicant-app2-offer'))),
      isA<FilledButton>(),
    );
    expect(find.byKey(const ValueKey('applicant-app1-offer')), findsNothing);
    harness.app.dispose();
  });

  testWidgets('send offer starts with the slot guarantee in whole dollars', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app2-offer')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('send-offer-gross')))
          .controller!
          .text,
      '300',
    );
    expect(
      tester
          .widget<EpChip>(
            find.byKey(const ValueKey('send-offer-terms-standard')),
          )
          .active,
      isTrue,
    );
    expect(
      find.text(CancellationTemplate.standard.description),
      findsOneWidget,
    );
    harness.app.dispose();
  });

  testWidgets('paid offer failure stays in the sheet with an inline error', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app2-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-offer-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-offer-gross')), findsOneWidget);
    expect(
      tester.widget<InlineFormFeedback>(find.byType(InlineFormFeedback)).error,
      'Paid offers open once payments are enabled',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('send-offer-feedback')))
          .data,
      'Paid offers open once payments are enabled',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('send-offer-submit')))
          .onPressed,
      isNotNull,
    );
    harness.app.dispose();
  });

  testWidgets('wrapped paid offer failure shows only the server message', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
      repositoryBuilder: (auth) => _WrappedOfferErrorRepository(auth: auth),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app2-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-offer-submit')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('send-offer-feedback')))
          .data,
      'Paid offers open once payments are enabled',
    );
    harness.app.dispose();
  });

  testWidgets('sending an offer updates the applicant and opens its booking', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );
    (harness.app.repository as DemoRepository).demoPaymentsEnabled = true;

    await tester.tap(find.byKey(const ValueKey('applicant-app2-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-offer-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-offer-submit')), findsNothing);
    expect(_applicantPill(tester, 'app2').label, 'Offered');
    expect(harness.app.toast, 'Offer sent');
    expect(find.byKey(const ValueKey('applicant-app2-offer')), findsNothing);
    final booking = harness.app.organizationBookings.singleWhere(
      (booking) => booking.applicationId == 'app2',
    );
    expect(booking.fee.grossMinor, 30000);
    expect(booking.cancellationTemplate, CancellationTemplate.standard);
    expect(booking.termsNotes, isNull);
    expect(booking.currentOffer!.message, isNull);
    final viewBooking = find.byKey(const ValueKey('applicant-app2-booking'));
    expect(viewBooking, findsOneWidget);
    await tester.ensureVisible(viewBooking);
    await tester.tap(viewBooking);
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, booking.id);
    harness.app.dispose();
  });

  testWidgets('send offer fields stay outside applicant cards', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app2-offer')));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);
    expectNoFieldInCard(tester);
    harness.app.dispose();
  });

  testWidgets('invalid guarantees do not send offers', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );
    (harness.app.repository as DemoRepository).demoPaymentsEnabled = true;

    await tester.tap(find.byKey(const ValueKey('applicant-app2-offer')));
    await tester.pumpAndSettle();
    for (final amount in ['', 'abc', '-1', '1.50', '0x10']) {
      await tester.enterText(
        find.byKey(const ValueKey('send-offer-gross')),
        amount,
      );
      await tester.tap(find.byKey(const ValueKey('send-offer-submit')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('send-offer-feedback')))
            .data,
        'Enter a valid guarantee in dollars.',
      );
      expect(
        harness.app.organizationBookings.where(
          (booking) => booking.applicationId == 'app2',
        ),
        isEmpty,
      );
    }
    harness.app.dispose();
  });

  testWidgets('a zero guarantee sends selected terms and trimmed notes', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app2-offer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('send-offer-gross')), '0');
    await tester.tap(find.byKey(const ValueKey('send-offer-terms-flexible')));
    await tester.pumpAndSettle();
    expect(
      find.text(CancellationTemplate.flexible.description),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('send-offer-notes')),
      '  Backline provided.  ',
    );
    final message = find.byKey(const ValueKey('send-offer-message'));
    await tester.ensureVisible(message);
    await tester.enterText(message, '  Looking forward to the show!  ');
    await tester.tap(find.byKey(const ValueKey('send-offer-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-offer-submit')), findsNothing);
    final booking = harness.app.organizationBookings.singleWhere(
      (booking) => booking.applicationId == 'app2',
    );
    expect(booking.fee.grossMinor, 0);
    expect(booking.cancellationTemplate, CancellationTemplate.flexible);
    expect(booking.termsNotes, 'Backline provided.');
    expect(booking.currentOffer!.message, 'Looking forward to the show!');
    harness.app.dispose();
  });

  testWidgets('closing the offer sheet leaves the applicant shortlisted', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app2-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-offer-submit')), findsNothing);
    expect(_applicantPill(tester, 'app2').label, 'Shortlisted');
    expect(find.byKey(const ValueKey('applicant-app2-booking')), findsNothing);
    expect(harness.app.toast, isNot('Offer sent'));
    harness.app.dispose();
  });

  for (final accepted in [false, true]) {
    testWidgets(
      'loading ${accepted ? 'booked' : 'offered'} applicants shows their booking',
      (tester) async {
        final harness = await _pumpOrganizerScreen(
          tester,
          const SizedBox.shrink(),
        );
        final repository = harness.app.repository;
        final result = await repository.sendOffer(
          applicationId: 'app2',
          grossMinor: 0,
          cancellationTemplate: CancellationTemplate.standard,
        );
        if (accepted) {
          await repository.respondToOffer(
            bookingId: result.bookingId,
            accept: true,
            expectedRevision: result.revision,
          );
        }
        harness.app.organizationBookings = [];
        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: harness.app,
            child: MaterialApp(
              theme: buildEpTheme(),
              home: const Scaffold(
                body: OpportunityApplicantsScreen(opportunityId: 'opp1'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          _applicantPill(tester, 'app2').label,
          accepted ? 'Booked' : 'Offered',
        );
        expect(
          find.byKey(const ValueKey('applicant-app2-offer')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('applicant-app2-decline')),
          findsNothing,
        );
        final viewBooking = find.byKey(
          const ValueKey('applicant-app2-booking'),
        );
        expect(viewBooking, findsOneWidget);
        await tester.ensureVisible(viewBooking);
        await tester.tap(viewBooking);
        await tester.pumpAndSettle();

        expect(harness.app.current.screen, Screen.bookingDetail);
        expect(harness.app.current.param, result.bookingId);
        harness.app.dispose();
      },
    );
  }

  testWidgets('shortlisting updates the applicant status pill', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app1-shortlist')));
    await tester.pumpAndSettle();

    expect(_applicantPill(tester, 'app1').label, 'Shortlisted');
    expect(
      find.byKey(const ValueKey('applicant-app1-shortlist')),
      findsNothing,
    );
    expect(find.text('2 applicants'), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets(
    'declining refreshes the status pill and active applicant count',
    (tester) async {
      final harness = await _pumpOrganizerScreen(
        tester,
        const OpportunityApplicantsScreen(opportunityId: 'opp1'),
      );
      expect(find.text('2 applicants'), findsOneWidget);
      final decline = find.byKey(const ValueKey('applicant-app2-decline'));
      await tester.ensureVisible(decline);
      await tester.tap(decline);
      await tester.pumpAndSettle();
      expect(find.text('Decline this applicant?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
      await tester.pumpAndSettle();

      expect(_applicantPill(tester, 'app2').label, 'Declined');
      expect(find.text('1 applicants'), findsOneWidget);
      expect(find.text('2 applicants'), findsNothing);
      expect(
        find.byKey(const ValueKey('applicant-app2-decline')),
        findsNothing,
      );
      harness.app.dispose();
    },
  );

  testWidgets('keeping an applicant cancels the decline', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app1-decline')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
    await tester.pumpAndSettle();

    expect(_applicantPill(tester, 'app1').label, 'Submitted');
    expect(find.text('2 applicants'), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets('starting review preserves shortlist and decline actions', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app1-review')));
    await tester.pumpAndSettle();

    expect(_applicantPill(tester, 'app1').label, 'Under review');
    expect(find.byKey(const ValueKey('applicant-app1-review')), findsNothing);
    expect(
      find.byKey(const ValueKey('applicant-app1-shortlist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('applicant-app1-decline')),
      findsOneWidget,
    );
    harness.app.dispose();
  });

  testWidgets('slot chips filter applicants and ALL restores both', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    final support = find.byKey(const ValueKey('applicants-slot-opp1-support'));
    await tester.tap(support);
    await tester.pumpAndSettle();
    expect(tester.widget<EpChip>(support).active, isTrue);
    expect(find.byKey(const ValueKey('applicant-app1')), findsOneWidget);
    expect(find.byKey(const ValueKey('applicant-app2')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('applicants-slot-opp1-headliner')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('applicant-app1')), findsNothing);
    expect(find.byKey(const ValueKey('applicant-app2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('applicants-slot-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('applicant-app1')), findsOneWidget);
    expect(find.byKey(const ValueKey('applicant-app2')), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets('tapping the band name opens its profile', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.text(DemoData.bands['b1']!.name));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.band);
    expect(harness.app.current.param, 'b1');
    harness.app.dispose();
  });

  for (final role in [OrganizationRole.finance, OrganizationRole.door]) {
    testWidgets('${role.name} members can read applicants without actions', (
      tester,
    ) async {
      final harness = await _pumpOrganizerScreen(
        tester,
        const OpportunityApplicantsScreen(opportunityId: 'opp1'),
      );
      harness.app.myOrganizations = [
        OrganizationMembership(
          organization: DemoData.organizations['org1']!,
          role: role,
        ),
      ];
      await enterOrganizer(tester, harness, 'org1');

      expect(find.byKey(const ValueKey('applicant-app1')), findsOneWidget);
      expect(find.byKey(const ValueKey('applicant-app2')), findsOneWidget);
      expect(find.text('START REVIEW'), findsNothing);
      expect(find.text('SHORTLIST'), findsNothing);
      expect(find.text('DECLINE'), findsNothing);
      harness.app.dispose();
    });
  }

  testWidgets(
    'applicant insights expander renders numbers for a non-suppressed band',
    (tester) async {
      final harness = await _pumpOrganizerScreen(
        tester,
        const OpportunityApplicantsScreen(opportunityId: 'opp1'),
        repositoryBuilder: (auth) => _ApplicantInsightsRepository(auth: auth),
      );
      final toggle = find.byKey(const ValueKey('applicant-app1-insights'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final panel = find.byKey(const ValueKey('applicant-app1-insights-panel'));
      for (final text in [
        'EVENTS',
        '8',
        'CHECK-INS',
        '180',
        'TICKETS SOLD',
        '96',
        'FOLLOWERS',
        '486',
        'Returning attendees: 42',
        'Estimated draw: 20–30 · medium confidence · based on check-ins',
        'Top area: Mission, SF',
        'Top venue type: bar',
        'Ticket buyers: referral 30 · followers 20 · other 46',
      ]) {
        expect(
          find.descendant(of: panel, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expectNoFieldInCard(tester);
      harness.app.dispose();
    },
  );

  testWidgets(
    'applicant insights expander shows suppressed and no-history states',
    (tester) async {
      final harness = await _pumpOrganizerScreen(
        tester,
        const OpportunityApplicantsScreen(opportunityId: 'opp1'),
        repositoryBuilder: (auth) => _ApplicantInsightsRepository(auth: auth),
      );
      final toggle = find.byKey(const ValueKey('applicant-app2-insights'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final panel = find.byKey(const ValueKey('applicant-app2-insights-panel'));
      for (final text in [
        'Returning attendees: not enough data',
        'Estimated draw: No history yet',
        'Top area: not enough data',
        'Top venue type: not enough data',
      ]) {
        expect(
          find.descendant(of: panel, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: panel,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.data?.startsWith('Ticket buyers:') ?? false),
          ),
        ),
        findsNothing,
      );
      expectNoFieldInCard(tester);
      harness.app.dispose();
    },
  );

  for (final screen in const [
    OrgOpportunitiesScreen(),
    OpportunityApplicantsScreen(opportunityId: 'opp1'),
  ]) {
    testWidgets('${screen.runtimeType} has no text fields inside cards', (
      tester,
    ) async {
      final harness = await _pumpOrganizerScreen(tester, screen);

      expect(find.byType(EpCard), findsWidgets);
      expect(
        find.ancestor(
          of: find.byType(TextField),
          matching: find.byType(EpCard),
        ),
        findsNothing,
      );
      harness.app.dispose();
    });
  }
}

Future<AppHarness> _pumpOrganizerScreen(
  WidgetTester tester,
  Widget screen, {
  DemoRepository Function(FakeAuthService auth)? repositoryBuilder,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final repository =
      repositoryBuilder?.call(auth) ?? DemoRepository(auth: auth);
  final app = AppState(repository: repository, auth: auth);
  final picker = FakeMediaPicker();
  final media = BandMediaController(
    repository: repository,
    picker: picker,
    uploader: app.mediaUploader,
    say: app.say,
  );
  app.attachMediaController(media);
  addTearDown(media.dispose);
  final harness = AppHarness(
    app: app,
    auth: auth,
    media: media,
    picker: picker,
    geocoding: FakeGeocodingService(),
  );

  // Unlike pumpApp, this wrapper leaves disposal to each test body. Providing
  // the existing app by value prevents the provider from disposing it twice.
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  app.switchToOrganization('org1');
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildEpTheme(),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await enterOrganizer(tester, harness, 'org1');
  return harness;
}

class _ApplicantInsightsRepository extends DemoRepository {
  _ApplicantInsightsRepository({required super.auth});

  @override
  Future<ArtistInsights> artistInsights(String applicationId) async {
    if (applicationId == 'app1') return _nonSuppressedApplicantInsights;
    return _suppressedApplicantInsights;
  }
}

const _nonSuppressedApplicantInsights = ArtistInsights(
  band: InsightsBand(bandId: 'b1', name: 'Foghorn Diet'),
  window: InsightsWindow(events: 8, truncated: false),
  followers: 486,
  rsvpTotal: 240,
  ticketsSold: 96,
  checkIns: 180,
  returningAttendees: 42,
  returningSuppressed: false,
  attribution: Attribution(
    referral: 30,
    follow: 20,
    unattributed: 46,
    suppressed: false,
  ),
  byArea: InsightPartition(
    buckets: [
      InsightBucket(key: 'Mission, SF', events: 5, checkIns: 120),
      InsightBucket(key: 'Temescal, Oakland', events: 3, checkIns: 60),
    ],
    suppressed: false,
  ),
  byVenueType: InsightPartition(
    buckets: [
      InsightBucket(key: 'bar', events: 6, checkIns: 140),
      InsightBucket(key: 'club', events: 2, checkIns: 40),
    ],
    suppressed: false,
  ),
  byWeekday: InsightPartition(
    buckets: [InsightBucket(key: '5', events: 8, checkIns: 180)],
    suppressed: false,
  ),
  byPriceBand: InsightPartition(
    buckets: [
      InsightBucket(key: 'under20', events: 5, checkIns: 100),
      InsightBucket(key: '20Plus', events: 3, checkIns: 80),
    ],
    suppressed: false,
  ),
  estimatedDraw: EstimatedDraw(
    low: 20,
    high: 30,
    confidence: DrawConfidence.medium,
    events: 8,
    basis: DrawBasis.checkIns,
  ),
);

const _suppressedApplicantInsights = ArtistInsights(
  band: InsightsBand(bandId: 'b2', name: 'Pigeon Court'),
  window: InsightsWindow(events: 3, truncated: false),
  followers: 1214,
  rsvpTotal: 40,
  ticketsSold: 10,
  checkIns: 22,
  returningAttendees: 0,
  returningSuppressed: true,
  attribution: Attribution(
    referral: 0,
    follow: 0,
    unattributed: 0,
    suppressed: true,
  ),
  byArea: InsightPartition(buckets: [], suppressed: true),
  byVenueType: InsightPartition(buckets: [], suppressed: true),
  byWeekday: InsightPartition(buckets: [], suppressed: true),
  byPriceBand: InsightPartition(buckets: [], suppressed: true),
  estimatedDraw: null,
);

class _PublishedOpportunityRepository extends DemoRepository {
  _PublishedOpportunityRepository({
    required super.auth,
    this.published = true,
    this.ticketing = OpportunityTicketing.paid,
  });

  final bool published;
  final OpportunityTicketing ticketing;
  int salesReads = 0;

  @override
  Future<List<Opportunity>> manageOpportunities(String organizationId) async {
    final opportunities = await super.manageOpportunities(organizationId);
    return opportunities.map((opportunity) {
      if (opportunity.id != 'opp1') return opportunity;
      return Opportunity(
        id: opportunity.id,
        organizationId: opportunity.organizationId,
        mode: opportunity.mode,
        venueId: opportunity.venueId,
        venue: opportunity.venue,
        title: opportunity.title,
        desc: opportunity.desc,
        eventType: opportunity.eventType,
        expectedAttendance: opportunity.expectedAttendance,
        genres: opportunity.genres,
        startsAt: opportunity.startsAt,
        doorsAt: opportunity.doorsAt,
        endsAt: opportunity.endsAt,
        ageRequirement: opportunity.ageRequirement,
        equipment: opportunity.equipment,
        requirements: opportunity.requirements,
        flyKey: opportunity.flyKey,
        flyerUrl: opportunity.flyerUrl,
        applicationsCloseAt: opportunity.applicationsCloseAt,
        visibility: opportunity.visibility,
        ticketing: ticketing,
        ticketPriceMinor: 2500,
        ticketCapacity: 40,
        ticketCurrency: 'usd',
        externalUrl: opportunity.externalUrl,
        status: OpportunityStatus.confirmed,
        slug: opportunity.slug,
        revision: opportunity.revision,
        applicationCount: opportunity.applicationCount,
        slots: opportunity.slots,
        invitedBandIds: opportunity.invitedBandIds,
        createdAt: opportunity.createdAt,
        updatedAt: opportunity.updatedAt,
        area: opportunity.area,
        venueType: opportunity.venueType,
        currency: opportunity.currency,
      );
    }).toList();
  }

  @override
  Stream<FeedSnapshot> feed() => super.feed().map(
    (snapshot) => FeedSnapshot(
      gigs: [
        for (final gig in snapshot.gigs)
          if (published && gig.id == 'g8')
            gig.copyWith(opportunityId: 'opp1')
          else
            gig,
      ],
      venues: snapshot.venues,
      bands: snapshot.bands,
      nextStartsAt: snapshot.nextStartsAt,
    ),
  );

  @override
  Future<TicketSales> ticketSalesForGig(String gigId) {
    salesReads++;
    return super.ticketSalesForGig(gigId);
  }
}

class _BookingStatusRepository extends DemoRepository {
  _BookingStatusRepository({required super.auth});

  @override
  Future<List<Opportunity>> manageOpportunities(String organizationId) async {
    final opportunities = await super.manageOpportunities(organizationId);
    return opportunities.map((opportunity) {
      if (opportunity.id != 'opp1') return opportunity;
      return Opportunity(
        id: opportunity.id,
        organizationId: opportunity.organizationId,
        mode: opportunity.mode,
        venueId: opportunity.venueId,
        venue: opportunity.venue,
        title: opportunity.title,
        desc: opportunity.desc,
        eventType: opportunity.eventType,
        expectedAttendance: opportunity.expectedAttendance,
        genres: opportunity.genres,
        startsAt: opportunity.startsAt,
        doorsAt: opportunity.doorsAt,
        endsAt: opportunity.endsAt,
        ageRequirement: opportunity.ageRequirement,
        equipment: opportunity.equipment,
        requirements: opportunity.requirements,
        flyKey: opportunity.flyKey,
        flyerUrl: opportunity.flyerUrl,
        applicationsCloseAt: opportunity.applicationsCloseAt,
        visibility: opportunity.visibility,
        ticketing: opportunity.ticketing,
        externalUrl: opportunity.externalUrl,
        status: OpportunityStatus.booking,
        slug: opportunity.slug,
        revision: opportunity.revision,
        applicationCount: opportunity.applicationCount,
        slots: opportunity.slots,
        invitedBandIds: opportunity.invitedBandIds,
        createdAt: opportunity.createdAt,
        updatedAt: opportunity.updatedAt,
        area: opportunity.area,
        venueType: opportunity.venueType,
        currency: opportunity.currency,
      );
    }).toList();
  }
}

class _WrappedOfferErrorRepository extends DemoRepository {
  _WrappedOfferErrorRepository({required super.auth});

  @override
  Future<({String bookingId, String offerId, int revision})> sendOffer({
    required String applicationId,
    required int grossMinor,
    required CancellationTemplate cancellationTemplate,
    List<OfferInstallmentInput>? installments,
    String? termsNotes,
    String? message,
  }) async {
    throw Exception(
      '[Request ID: abc123] Server Error\n'
      'Uncaught Error: Paid offers open once payments are enabled\n'
      ' at handler (../../convex/bookings.ts:251:23)\n',
    );
  }
}

Future<void> _chooseOpportunityAction(
  WidgetTester tester,
  String opportunityId,
  String action,
) async {
  final card = find.byKey(ValueKey('org-opp-$opportunityId'));
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

StatusPill _applicantPill(WidgetTester tester, String applicationId) =>
    tester.widget<StatusPill>(
      find.descendant(
        of: find.byKey(ValueKey('applicant-$applicationId')),
        matching: find.byType(StatusPill),
      ),
    );
