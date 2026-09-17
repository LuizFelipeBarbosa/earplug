import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_manager.dart';
import 'package:earplug/screens/hosted_gig.dart';
import 'package:earplug/screens/opportunity_detail.dart';
import 'package:earplug/screens/org_opportunities.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  group('band gigs flow', () {
    testWidgets('DISCOVER identifies private requests and explains disclosure', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final opportunity = (await repository.opportunity('opp-private'))!;
      await repository.updateOpportunity(
        opportunityId: opportunity.id,
        expectedRevision: opportunity.revision,
        expectedAttendance: 45,
      );
      final harness = await pumpApp(
        tester,
        home: const RootShell(),
        auth: auth,
        repository: repository,
        beforePump: (app) {
          app.switchToBand('b1');
          app.resetTo(Screen.gigMgr);
        },
      );
      await _selectTab(tester, 'DISCOVER');
      expect(
        find.text(
          'Private events: the exact address is shared with the booked '
          'artist after the deposit is paid.',
        ),
        findsOneWidget,
      );
      expect(harness.app.browse.privateCount, 1);
      final card = find.byKey(const Key('opp-card-opp-private'));
      await tester.scrollUntilVisible(
        card,
        300,
        scrollable: find
            .descendant(
              of: find.byType(GigManagerScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      final pill = find.descendant(
        of: card,
        matching: find.byKey(const Key('opp-card-opp-private-private')),
      );
      expect(tester.widget<EpPill>(pill).label, 'Private event');
      expect(
        find.descendant(of: card, matching: find.text('Mission District')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('~45 guests')),
        findsOneWidget,
      );
      for (final privateDetail in [
        "Jordan's courtyard",
        '120 Demo Lane, San Francisco',
        'The Foghorn Club',
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(privateDetail)),
          findsNothing,
        );
      }

      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(OpportunityDetailScreen), findsOneWidget);
      expect(harness.app.current.param, opportunity.slug);
      expect(
        tester
            .widget<EpChip>(find.byKey(const Key('opp-detail-private')))
            .label,
        'PRIVATE EVENT',
      );
      final note = find.byKey(const Key('opp-detail-private-note'));
      await tester.ensureVisible(note);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(note).data,
        'The exact address is shared with the booked artist after the deposit is paid.',
      );
      expect(find.text('Mission District'), findsOneWidget);
      expect(find.byType(VenueMiniMap), findsNothing);
      expect(find.textContaining('120 Demo Lane'), findsNothing);
      expect(find.byKey(const Key('opp-detail-apply')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('EXPECTED GUESTS'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(OpportunityDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('EXPECTED GUESTS'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('45'),
          matching: find.widgetWithText(LedgerRow, 'EXPECTED GUESTS'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'public invitations appear once and retain the invitation label',
      (tester) async {
        final harness = await pumpApp(tester, home: const RootShell());
        await _signInBand(tester, harness);
        await harness.app.repository.inviteBandToOpportunity(
          opportunityId: 'opp1',
          bandId: 'b1',
        );
        harness.app.resetTo(Screen.gigMgr);
        await tester.pumpAndSettle();
        await _selectTab(tester, 'DISCOVER');

        expect(
          harness.app.browse.invited.any(
            (item) => item.opportunity.id == 'opp1',
          ),
          isTrue,
        );
        expect(
          harness.app.browse.items.any((item) => item.opportunity.id == 'opp1'),
          isTrue,
        );
        final card = find.byKey(const Key('opp-card-opp1'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text('INVITED')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'opportunity back returns to the Gigs page through app navigation',
      (tester) async {
        final harness = await pumpApp(tester, home: const RootShell());
        await _signInBand(tester, harness);
        harness.app.resetTo(Screen.gigMgr);
        harness.app.openOpportunity('friday-night-live');
        await tester.pumpAndSettle();

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.gigMgr);
        expect(find.byType(GigManagerScreen), findsOneWidget);
      },
    );

    testWidgets(
      'apply selects the only administered band when another band is active',
      (tester) async {
        final harness = await pumpApp(tester, home: const RootShell());
        await _signInNonAdminMember(tester, harness);
        await harness.app.repository.withdrawApplication('app1');
        await harness.app.repository.withdrawApplication('app2');
        harness.app.openOpportunity('friday-night-live');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('opp-detail-apply')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('opp-apply-submit')));
        await tester.pumpAndSettle();

        expect(find.text('Choose a band you manage to apply.'), findsNothing);
        final applications = await harness.app.repository.myApplications('b1');
        expect(
          applications.where((row) => row.application.status.isActive),
          hasLength(1),
        );
        expect(harness.app.toast, 'Application sent');
      },
    );

    testWidgets('opportunity apply action stays above the band tab bar', (
      tester,
    ) async {
      final harness = await pumpApp(tester, home: const RootShell());
      await _signInBand(tester, harness);
      harness.app.openOpportunity('private-preview');
      await tester.pumpAndSettle();

      expect(find.byType(OpportunityDetailScreen), findsOneWidget);
      expect(find.byType(BandTabBar), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('opp-detail-apply'))).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(BandTabBar)).top),
      );
    });

    testWidgets('non-admin members can browse gigs without write actions', (
      tester,
    ) async {
      final harness = await pumpApp(tester, home: const RootShell());
      await _signInNonAdminMember(tester, harness);
      expect(harness.app.isAdminOf('b2'), isFalse);
      final project = await _publishGig(
        harness.app.repository as DemoRepository,
        'b2',
      );
      harness.app.openGigManager();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('band-gigs-new')), findsNothing);
      await _selectTab(tester, 'DISCOVER');
      await _reveal(tester, find.byKey(const Key('opp-card-opp1')));
      expect(find.byKey(const Key('opp-card-opp1')), findsOneWidget);
      await _selectTab(tester, 'MY GIGS');
      final hosted = find.byKey(Key('my-gigs-hosted-${project.id}'));
      await _reveal(tester, hosted);
      await tester.tap(hosted);
      await tester.pumpAndSettle();

      expect(harness.app.current.screen, Screen.hostedGig);
      expect(harness.app.current.param, project.id);
      expect(find.byType(HostedGigScreen), findsOneWidget);
      expect(find.byKey(const Key('hosted-gig-edit')), findsNothing);
      expect(find.byKey(const Key('hosted-gig-actions')), findsNothing);
    });

    testWidgets('DISCOVER shows invitations first and excludes drafts', (
      tester,
    ) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(body: GigManagerScreen()),
      );
      await _signInBand(tester, harness);

      await _selectTab(tester, 'DISCOVER');
      await _reveal(tester, find.byKey(const Key('opp-card-opp1')));
      expect(find.byKey(const Key('opp-card-opp1')), findsOneWidget);
      expect(find.byKey(const Key('opp-card-opp3')), findsOneWidget);
      expect(find.byKey(const Key('opp-card-opp2')), findsNothing);
      expect(find.text('Patio Sessions'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('opp-card-opp3')),
          matching: find.text('INVITED'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('opp-card-opp3'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('opp-card-opp1'))).dy),
      );
      expect(
        find.text(r'HEADLINER + 1 MORE · $300.00 guarantee'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('opp-card-opp1-applied')), findsOneWidget);
      expect(find.byKey(const Key('opp-card-opp3-apply')), findsOneWidget);
      expect(find.byKey(const Key('band-gigs-load-more')), findsNothing);
      harness.app.dispose();
    });

    testWidgets('an opportunity card opens its slug in app navigation', (
      tester,
    ) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(body: GigManagerScreen()),
      );
      await _signInBand(tester, harness);

      await _selectTab(tester, 'DISCOVER');
      final card = find.byKey(const Key('opp-card-opp1'));
      await _reveal(tester, card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(harness.app.current.screen, Screen.opportunityDetail);
      expect(harness.app.current.param, 'friday-night-live');
      harness.app.dispose();
    });

    testWidgets(
      'APPLICATIONS confirms withdrawal and refreshes the browse status',
      (tester) async {
        final harness = await _pumpScreen(
          tester,
          home: const Scaffold(body: GigManagerScreen()),
        );
        await _signInBand(tester, harness);
        await _selectTab(tester, 'APPLICATIONS');

        final row = find.byKey(const Key('band-app-app1'));
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text('IN REVIEW')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('band-app-app1-withdraw')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('KEEP'));
        await tester.pumpAndSettle();
        expect(
          harness.app.myApplications.single.application.status,
          ArtistApplicationStatus.submitted,
        );

        await _withdrawFromApplications(tester);

        expect(
          harness.app.myApplications.single.application.status,
          ArtistApplicationStatus.withdrawn,
        );
        expect(find.byKey(const Key('band-app-app1-withdraw')), findsNothing);
        expect(
          find.descendant(
            of: row,
            matching: find.widgetWithText(EpBadge, 'WITHDRAWN'),
          ),
          findsOneWidget,
        );
        expect(
          harness.app.browse.items
                  .firstWhere((item) => item.opportunity.id == 'opp1')
                  .myApplicationStatus
                  ?.isActive ??
              false,
          isFalse,
        );
        harness.app.dispose();
      },
    );

    testWidgets('MY GIGS upcoming row opens booking detail', (tester) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(body: GigManagerScreen()),
      );
      await _signInBand(tester, harness);
      final row = find.byKey(const Key('band-booking-bk2'));
      expect(find.text('UPCOMING · 1'), findsOneWidget);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('THE FOGHORN CLUB')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('band-booking-bk1')), findsNothing);
      expect(find.byKey(const ValueKey('band-booking-bk3')), findsNothing);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.bookingDetail);
      expect(harness.app.current.param, 'bk2');
      harness.app.dispose();
    });

    for (final refundedMinor in [0, 2550]) {
      testWidgets(
        refundedMinor == 0
            ? 'MY GIGS lists a paid booking with no refunds'
            : 'MY GIGS lists a paid booking after a refund',
        (tester) async {
          final auth = FakeAuthService();
          await auth.signInDemo();
          final booking = Booking(
            id: 'paid-booking',
            opportunityId: 'opp1',
            opportunityTitle: 'Paid show',
            opportunitySlug: 'paid-show',
            slotId: 'opp1-headliner',
            slotRole: SlotRole.headliner,
            slotRequired: true,
            organizationId: 'org1',
            organizationName: 'The Foghorn Club',
            bandId: 'b1',
            bandName: 'Foghorn Diet',
            bandSlug: 'foghorn-diet',
            applicationId: 'app1',
            status: BookingStatus.confirmed,
            revision: 3,
            startsAt: DateTime.now().add(const Duration(days: 5)),
            fee: const FeeBreakdown(
              grossMinor: 10000,
              commissionBps: 1000,
              commissionMinor: 1000,
              artistNetMinor: 9000,
              currency: 'usd',
            ),
            paidMinor: 10000,
            refundedMinor: refundedMinor,
            cancellationTemplate: CancellationTemplate.standard,
            organizerAcceptedTermsAt: DateTime.now(),
            viewerSide: BookingSide.artist,
          );
          final repository = StubRepository(auth: auth)
            ..returns('bandBookings', [booking]);
          await pumpApp(
            tester,
            home: const Scaffold(body: GigManagerScreen()),
            auth: auth,
            repository: repository,
            beforePump: (app) => app.switchToBand('b1'),
          );
          final row = find.byKey(const Key('band-booking-paid-booking'));
          expect(row, findsOneWidget);
          expect(
            find.descendant(of: row, matching: find.text('BOOKED')),
            findsOneWidget,
          );
          expectNoFieldInCard(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'MY GIGS past lists completed bookings and opens booking detail',
      (tester) async {
        final harness = await _pumpScreen(
          tester,
          home: const Scaffold(body: GigManagerScreen()),
        );
        await _signInBand(tester, harness);
        expect(find.byKey(const Key('band-booking-bk3')), findsNothing);
        final past = find.byKey(const Key('my-gigs-past-toggle'));
        await _reveal(tester, past);
        await tester.tap(past);
        await tester.pumpAndSettle();

        final card = find.byKey(const ValueKey('band-booking-bk3'));
        await _reveal(tester, card);
        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('my-gigs-past-body')),
            matching: find.byKey(const ValueKey('band-booking-bk2')),
          ),
          findsNothing,
        );

        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.bookingDetail);
        expect(harness.app.current.param, 'bk3');
        harness.app.dispose();
      },
    );

    testWidgets(
      'APPLICATIONS offers show RESPOND once their booking is loaded',
      (tester) async {
        final harness = await _pumpScreen(
          tester,
          home: const Scaffold(body: GigManagerScreen()),
        );
        await _signInBand(tester, harness);
        final repository = harness.app.repository as DemoRepository;
        repository.demoPaymentsEnabled = true;
        await repository.reviewApplication(
          applicationId: 'app1',
          action: ArtistApplicationReviewAction.shortlisted,
        );
        final sent = await repository.sendOffer(
          applicationId: 'app1',
          grossMinor: 0,
          cancellationTemplate: CancellationTemplate.standard,
        );
        await harness.app.refreshMyApplications();
        await tester.pumpAndSettle();
        await _selectTab(tester, 'APPLICATIONS');

        final row = find.byKey(const Key('band-app-app1'));
        final respond = find.byKey(const ValueKey('band-app-app1-respond'));
        expect(
          find.descendant(of: row, matching: find.text('OFFER RECEIVED')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('band-app-app1-withdraw')), findsNothing);
        expect(respond, findsNothing);

        await harness.app.refreshBandBookings();
        await tester.pumpAndSettle();
        expect(respond, findsOneWidget);
        expect(
          find.descendant(of: respond, matching: find.text('RESPOND')),
          findsOneWidget,
        );
        await tester.tap(respond);
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.bookingDetail);
        expect(harness.app.current.param, sent.bookingId);
        expect(
          harness.app.bookingById(sent.bookingId)?.viewerSide,
          BookingSide.artist,
        );
        harness.app.dispose();
      },
    );

    testWidgets('booked applications move from APPLICATIONS to MY GIGS', (
      tester,
    ) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(body: GigManagerScreen()),
      );
      await _signInBand(tester, harness);
      final repository = harness.app.repository as DemoRepository;
      final opportunity = (await repository.opportunity('opp1'))!;
      await repository.updateOpportunity(
        opportunityId: opportunity.id,
        expectedRevision: opportunity.revision,
        startsAt: DateTime.now().add(const Duration(days: 30)),
      );
      await repository.reviewApplication(
        applicationId: 'app1',
        action: ArtistApplicationReviewAction.shortlisted,
      );
      final sent = await repository.sendOffer(
        applicationId: 'app1',
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.standard,
      );
      await repository.respondToOffer(
        bookingId: sent.bookingId,
        accept: true,
        expectedRevision: sent.revision,
      );
      await harness.app.refreshMyApplications();
      await tester.pumpAndSettle();
      await _selectTab(tester, 'APPLICATIONS');

      expect(find.byKey(const Key('band-app-app1')), findsNothing);
      expect(find.byKey(const Key('band-app-app1-withdraw')), findsNothing);
      expect(find.byKey(const Key('band-app-app1-respond')), findsNothing);

      await _selectTab(tester, 'MY GIGS');
      final booking = find.byKey(Key('band-booking-${sent.bookingId}'));
      await _reveal(tester, booking);
      expect(booking, findsOneWidget);
      await tester.tap(booking);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.bookingDetail);
      expect(harness.app.current.param, sent.bookingId);
      harness.app.dispose();
    });

    testWidgets('organizer opportunities count booked slots and omit drafts', (
      tester,
    ) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(body: OrgOpportunitiesScreen()),
      );
      await enterOrganizer(tester, harness, 'org1');
      final openCard = find.byKey(const ValueKey('org-opp-opp1'));
      final draftCard = find.byKey(const ValueKey('org-opp-opp2'));
      expect(openCard, findsOneWidget);
      expect(draftCard, findsOneWidget);
      // Nothing is booked yet: both listings sit under ACTIVE, where the meta
      // line counts slots and the pill counts applications instead of bookings.
      expect(find.textContaining('CONFIRMED ·'), findsNothing);
      expect(
        find.descendant(
          of: openCard,
          matching: find.textContaining('2 slots · closes'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: openCard, matching: find.text('2 APPLIED')),
        findsOneWidget,
      );
      expect(find.textContaining('slots booked'), findsNothing);
      expect(
        find.descendant(of: draftCard, matching: find.text('DRAFT')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: draftCard, matching: find.text('0 APPLIED')),
        findsOneWidget,
      );

      final repository = harness.app.repository as DemoRepository;
      Future<void> book(String applicationId) async {
        final sent = await repository.sendOffer(
          applicationId: applicationId,
          grossMinor: 0,
          cancellationTemplate: CancellationTemplate.standard,
        );
        await repository.respondToOffer(
          bookingId: sent.bookingId,
          accept: true,
          expectedRevision: sent.revision,
        );
      }

      // One of two slots booked keeps the listing ACTIVE; the booked application
      // leaves the applied count.
      await repository.reviewApplication(
        applicationId: 'app1',
        action: ArtistApplicationReviewAction.shortlisted,
      );
      await book('app1');
      await harness.app.refreshOpportunities('org1');
      await tester.pumpAndSettle();
      expect(find.textContaining('CONFIRMED ·'), findsNothing);
      expect(
        find.descendant(of: openCard, matching: find.text('1 APPLIED')),
        findsOneWidget,
      );
      expect(find.textContaining('slots booked'), findsNothing);

      // Both slots booked moves the listing under CONFIRMED, where the meta line
      // counts slots whose status is booked; the draft stays behind.
      await book('app2');
      await harness.app.refreshOpportunities('org1');
      await tester.pumpAndSettle();
      expect(find.text('CONFIRMED · 1'), findsOneWidget);
      expect(
        find.descendant(
          of: openCard,
          matching: find.textContaining('2/2 slots booked'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('org-opp-applied-opp1')), findsNothing);
      expect(
        find.descendant(of: draftCard, matching: find.text('DRAFT')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: draftCard,
          matching: find.textContaining('slots booked'),
        ),
        findsNothing,
      );
      harness.app.dispose();
    });

    testWidgets(
      'hosted gigs are listed and cancelled projects stay behind PAST',
      (tester) async {
        final harness = await _pumpScreen(
          tester,
          home: const Scaffold(body: GigManagerScreen()),
        );
        await _signInBand(tester, harness);
        final repository = harness.app.repository as DemoRepository;
        final project = await _publishGig(repository, 'b1');
        await harness.app.refreshManagedGigs();
        await tester.pumpAndSettle();
        final hosted = find.byKey(Key('my-gigs-hosted-${project.id}'));
        await _reveal(tester, hosted);
        expect(hosted, findsOneWidget);

        await repository.cancelGig(project.id);
        await harness.app.refreshManagedGigs();
        await tester.pumpAndSettle();
        expect(hosted, findsNothing);
        expect(find.byKey(const Key('my-gigs-past-body')), findsNothing);
        final past = find.byKey(const Key('my-gigs-past-toggle'));
        await _reveal(tester, past);
        await tester.tap(past);
        await tester.pumpAndSettle();
        await _reveal(tester, hosted);
        expect(
          find.descendant(
            of: find.byKey(const Key('my-gigs-past-body')),
            matching: hosted,
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: hosted, matching: find.text('CANCELLED')),
          findsOneWidget,
        );
        harness.app.dispose();
      },
    );

    testWidgets(
      'DISCOVER filters apply area and venue type while preserving genre and pay',
      (tester) async {
        final harness = await _pumpScreen(
          tester,
          home: const Scaffold(body: GigManagerScreen()),
        );
        await _signInBand(tester, harness);
        await _selectTab(tester, 'DISCOVER');
        await tester.ensureVisible(
          find.byKey(const Key('discover-chip-genre')),
        );
        await tester.tap(find.byKey(const Key('discover-chip-genre')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('punk'));
        await tester.tap(find.text('punk'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('discover-chip-pay')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(r'$100+'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('discover-more-filters')),
        );
        await tester.tap(find.byKey(const Key('discover-more-filters')));
        await tester.pumpAndSettle();
        expectNoFieldInCard(tester);

        await tester.enterText(
          find.byKey(const Key('band-gigs-filter-area')),
          'Oakland',
        );
        await tester.tap(find.widgetWithText(EpPill, 'BAR'));
        await tester.tap(find.byKey(const Key('band-gigs-filter-apply')));
        await tester.pumpAndSettle();

        expect(harness.app.browseFilters.area, 'Oakland');
        expect(harness.app.browseFilters.genre, 'punk');
        expect(harness.app.browseFilters.venueType, VenueType.bar);
        expect(harness.app.browseFilters.minGuaranteeMinor, 10000);
        expect(find.byKey(const Key('opp-card-opp1')), findsNothing);
        harness.app.dispose();
      },
    );

    testWidgets('withdraw then apply to the headliner slot from detail', (
      tester,
    ) async {
      final screen = ValueNotifier<Widget>(const GigManagerScreen());
      addTearDown(screen.dispose);
      final harness = await _pumpScreen(
        tester,
        home: Scaffold(
          body: ValueListenableBuilder<Widget>(
            valueListenable: screen,
            builder: (_, child, _) => child,
          ),
        ),
      );
      await _signInBand(tester, harness);
      await _selectTab(tester, 'APPLICATIONS');
      await _withdrawFromApplications(tester);

      // Keep the same repository: app1 must be withdrawn before b1 applies again.
      screen.value = const OpportunityDetailScreen(opportunityRef: 'opp1');
      await tester.pumpAndSettle();
      expect(find.text('SLOTS'), findsOneWidget);
      expect(
        find.byKey(const Key('opp-detail-slot-opp1-headliner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opp-detail-slot-opp1-support')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('opp-detail-apply')), findsOneWidget);

      await tester.tap(find.byKey(const Key('opp-detail-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('opp-apply-band-b1')), findsNothing);
      expect(
        tester
            .widget<EpChip>(
              find.byKey(const Key('opp-apply-slot-opp1-headliner')),
            )
            .active,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('opp-apply-fee')))
            .controller!
            .text,
        '300',
      );
      expectNoFieldInCard(tester);
      await tester.enterText(find.byKey(const Key('opp-apply-fee')), '325.50');
      await tester.enterText(
        find.byKey(const Key('opp-apply-availability')),
        'Available after 6',
      );
      await tester.enterText(
        find.byKey(const Key('opp-apply-lineup')),
        'Four musicians',
      );
      await tester.ensureVisible(find.byKey(const Key('opp-apply-message')));
      await tester.enterText(
        find.byKey(const Key('opp-apply-message')),
        'Ready for a full set.',
      );
      await tester.tap(find.byKey(const Key('opp-apply-submit')));
      await tester.pumpAndSettle();

      final applications = await (harness.app.repository as DemoRepository)
          .myApplications('b1');
      final active = applications
          .singleWhere((row) => row.application.status.isActive)
          .application;
      expect(active.id, isNot('app1'));
      expect(active.slotId, 'opp1-headliner');
      expect(active.askMinor, 32550);
      expect(active.availabilityNote, 'Available after 6');
      expect(active.lineupNote, 'Four musicians');
      expect(active.message, 'Ready for a full set.');
      expect(harness.app.toast, 'Application sent');
      expect(find.text('APPLIED · SUBMITTED'), findsOneWidget);
      expect(find.byKey(const Key('opp-detail-apply')), findsNothing);
      expect(find.byKey(const Key('opp-detail-withdraw')), findsOneWidget);
      harness.app.dispose();
    });

    testWidgets('detail can withdraw an existing application', (tester) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(
          body: OpportunityDetailScreen(opportunityRef: 'opp1'),
        ),
      );
      await _signInBand(tester, harness);
      expect(find.text('APPLIED · SUBMITTED'), findsOneWidget);
      await tester.tap(find.byKey(const Key('opp-detail-withdraw')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONFIRM'));
      await tester.pumpAndSettle();

      expect(
        harness.app.myApplications.single.application.status,
        ArtistApplicationStatus.withdrawn,
      );
      expect(find.byKey(const Key('opp-detail-apply')), findsOneWidget);
      expect(find.byKey(const Key('opp-detail-withdraw')), findsNothing);
      harness.app.dispose();
    });

    testWidgets(
      'an application race shows the repository error inside the sheet',
      (tester) async {
        final harness = await _pumpScreen(
          tester,
          home: const Scaffold(
            body: OpportunityDetailScreen(opportunityRef: 'opp3'),
          ),
        );
        await _signInBand(tester, harness);
        expect(find.text('INVITED'), findsOneWidget);
        await tester.tap(find.byKey(const Key('opp-detail-apply')));
        await tester.pumpAndSettle();

        // Another client applies after this sheet has opened.
        await harness.app.repository.applyToOpportunity(
          opportunityId: 'opp3',
          slotId: 'opp3-headliner',
          bandId: 'b1',
          message: 'Already sent elsewhere',
        );
        await tester.tap(find.byKey(const Key('opp-apply-submit')));
        await tester.pumpAndSettle();

        expect(
          find.text('You already applied to this opportunity'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('opp-apply-submit')), findsOneWidget);
        expect(tester.takeException(), isNull);
        harness.app.dispose();
      },
    );

    testWidgets('unavailable detail has a safe back action at the root', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        home: const RootShell(),
        initialOpportunityRef: 'missing',
      );
      expect(find.text("This opportunity isn't available."), findsOneWidget);
      await tester.tap(find.text('BACK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(harness.app.current.screen, Screen.home);
      expect(find.byType(OpportunityDetailScreen), findsNothing);
    });
  });
}

Future<void> _signInBand(WidgetTester tester, AppHarness harness) async {
  await harness.auth.signInDemo();
  await tester.pumpAndSettle();
  harness.app.switchToBand('b1');
  await tester.pumpAndSettle();
}

Future<void> _signInNonAdminMember(
  WidgetTester tester,
  AppHarness harness,
) async {
  await harness.auth.signInDemo();
  await tester.pumpAndSettle();
  final invite = await harness.app.repository.createBandInvite('b2');
  await harness.app.repository.acceptBandInvite(invite.token);
  await tester.pumpAndSettle();
  harness.app.switchToBand('b2');
  await tester.pumpAndSettle();
}

Future<void> _withdrawFromApplications(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('band-app-app1-withdraw')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CONFIRM'));
  await tester.pumpAndSettle();
}

// These tests explicitly dispose AppState. Shadow the harness's lazy owning
// provider so only this non-owning provider subscribes to the test's state.
Future<AppHarness> _pumpScreen(WidgetTester tester, {required Widget home}) {
  late AppState app;
  return pumpApp(
    tester,
    beforePump: (state) => app = state,
    home: Builder(
      builder: (_) =>
          ChangeNotifierProvider<AppState>.value(value: app, child: home),
    ),
  );
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('band-gigs-tabs')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    180,
    scrollable: find
        .descendant(
          of: find.byType(GigManagerScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<GigProject> _publishGig(DemoRepository repository, String bandId) async {
  final draft = await repository.createGigDraft(bandId);
  final startsAt = DateTime.now().add(const Duration(days: 2));
  await repository.saveGigDraft(
    projectId: draft.id,
    revision: draft.revision,
    title: 'Legacy show',
    doorsAt: startsAt.subtract(const Duration(hours: 1)),
    startsAt: startsAt,
    venueId: 'v1',
    price: 0,
    flyKey: 'xerox',
    flyStorageId: null,
    overlay: true,
    desc: '',
    ticketing: Ticketing.rsvp,
    ageRequirement: AgeRequirement.allAges,
    externalUrl: null,
    cap: 'No cap',
  );
  await repository.publishGigDraft(draft.id);
  return repository.getGigProject(draft.id);
}
