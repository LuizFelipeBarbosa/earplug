import 'dart:async';

import 'package:earplug/app_links.dart';
import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/money.dart';
import 'package:earplug/screens/booking_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:earplug/widgets/status_timeline.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

void main() {
  for (final side in [BookingSide.organizer, BookingSide.artist]) {
    testWidgets('${side.name} opens a dispute and sees review and resolution', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final booking = await _createDisputeEligibleBooking(
        repository,
        bandId: side == BookingSide.organizer ? 'b2' : 'b1',
      );
      final harness = await pumpApp(
        tester,
        home: Scaffold(body: BookingDetailScreen(bookingId: booking.id)),
        auth: auth,
        repository: repository,
        beforePump: (app) async {
          if (side == BookingSide.artist) {
            app.switchToBand(booking.bandId);
          } else {
            app.switchToOrganization('org1');
          }
          await app.loadBooking(booking.id, viewAs: side);
        },
      );
      expect(
        harness.app.bookingById(booking.id)?.status,
        BookingStatus.confirmed,
      );
      expect(find.byKey(const Key('booking-cancel')), findsOneWidget);
      final open = find.byKey(const Key('booking-dispute-open'));
      await _reveal(tester, open);
      expect(tester.widget<EpButton>(open).kind, EpButtonKind.outline);
      expect(
        tester.widget<EpButton>(open).label,
        side == BookingSide.organizer ? 'REQUEST A REFUND' : 'OPEN A DISPUTE',
      );
      await tester.tap(open);
      await tester.pumpAndSettle();
      expectNoFieldInCard(tester);
      await tester.enterText(
        find.byKey(const Key('dispute-text')),
        'Please review what happened at this performance.',
      );
      final submit = find.byKey(const Key('dispute-submit'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.byType(EpFormSheet), findsNothing);
      expect(
        harness.app.bookingById(booking.id)?.status,
        BookingStatus.disputed,
      );
      expect(find.byKey(const Key('booking-cancel')), findsNothing);
      expect(open, findsNothing);
      await _reveal(
        tester,
        find.widgetWithText(StatusPill, 'UNDER DISPUTE'),
        delta: -300,
      );
      expect(
        tester
            .widget<StatusPill>(
              find.widgetWithText(StatusPill, 'UNDER DISPUTE'),
            )
            .label,
        'Under dispute',
      );
      expect(
        tester
            .widget<StatusTimeline>(find.byType(StatusTimeline))
            .steps
            .single
            .label,
        'Under dispute',
      );
      expect(find.text('Cancelled'), findsNothing);
      final dispute = harness.app.disputesFor(booking.id).single;
      expect(
        dispute.side,
        side == BookingSide.organizer
            ? DisputeSide.organizer
            : DisputeSide.artist,
      );
      final row = find.byKey(Key('booking-dispute-${dispute.disputeId}'));
      await _reveal(tester, row);
      expect(find.widgetWithText(SectionBar, 'DISPUTE'), findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.widgetWithText(StatusPill, 'OPEN'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            side == BookingSide.organizer ? 'Refund request' : 'Dispute',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('No-show')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(Money(booking.paidMinor).label),
        ),
        side == BookingSide.organizer ? findsOneWidget : findsNothing,
      );

      repository.platformAdmin = true;
      await repository.startDisputeReview(dispute.disputeId);
      await _refreshDisputeBooking(tester);
      await _reveal(tester, row);
      expect(
        find.descendant(
          of: row,
          matching: find.widgetWithText(StatusPill, 'UNDER REVIEW'),
        ),
        findsOneWidget,
      );
      expect(open, findsNothing);
      expect(find.byKey(const Key('booking-cancel')), findsNothing);

      await repository.resolveDispute(
        dispute.disputeId,
        resolution: DisputeResolution.released,
        adminNote: 'The performance met the agreed terms.',
      );
      repository.platformAdmin = false;
      await _refreshDisputeBooking(tester);
      await _reveal(tester, row);
      expect(
        find.descendant(
          of: row,
          matching: find.widgetWithText(StatusPill, 'RESOLVED'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Released to artist')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(r'$0.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('The performance met the agreed terms.'),
        ),
        findsOneWidget,
      );
      expectNoFieldInCard(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, future, grossMinor, pay) in [
    ('event has not started', true, 10005, true),
    ('zero booking fee', false, 0, false),
    ('awaiting payment', false, 10005, false),
  ]) {
    testWidgets('dispute action stays hidden: $name', (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final booking = await _createDisputeEligibleBooking(
        repository,
        startsAt: future ? DateTime.now().add(const Duration(days: 2)) : null,
        grossMinor: grossMinor,
        pay: pay,
      );
      await pumpApp(
        tester,
        home: Scaffold(body: BookingDetailScreen(bookingId: booking.id)),
        auth: auth,
        repository: repository,
      );
      // TERMS follows the dispute action, so its reveal builds that part of the list.
      await _reveal(tester, find.widgetWithText(SectionBar, 'TERMS'));
      expect(find.byKey(const Key('booking-dispute-open')), findsNothing);
      expect(find.widgetWithText(SectionBar, 'DISPUTE'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('refunded booking loads dispute history newest first', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final booking = await _createDisputeEligibleBooking(repository);
    final firstId = await repository.openDispute(
      bookingId: booking.id,
      side: DisputeSide.organizer,
      category: DisputeCategory.payment,
      text: 'Please review the payment for this event.',
      requestedRefundMinor: 1000,
    );
    repository.platformAdmin = true;
    await repository.resolveDispute(
      firstId,
      resolution: DisputeResolution.dismissed,
    );
    final latestId = await repository.openDispute(
      bookingId: booking.id,
      side: DisputeSide.organizer,
      category: DisputeCategory.noShow,
      text: 'The artist never arrived for the performance.',
      requestedRefundMinor: booking.paidMinor,
    );
    await repository.resolveDispute(
      latestId,
      resolution: DisputeResolution.refundedFull,
      adminNote: 'The full payment has been refunded.',
    );
    repository.platformAdmin = false;
    final harness = await pumpApp(
      tester,
      home: Scaffold(body: BookingDetailScreen(bookingId: booking.id)),
      auth: auth,
      repository: repository,
    );
    expect(harness.app.bookingById(booking.id)?.status, BookingStatus.refunded);
    expect(
      tester
          .widget<StatusPill>(find.widgetWithText(StatusPill, 'REFUNDED'))
          .label,
      'Refunded',
    );
    expect(
      tester
          .widget<StatusTimeline>(find.byType(StatusTimeline))
          .steps
          .single
          .label,
      'Refunded',
    );
    expect(find.text('Cancelled'), findsNothing);
    expect(find.byKey(const Key('booking-cancel')), findsNothing);

    final firstRow = find.byKey(Key('booking-dispute-$firstId'));
    final latestRow = find.byKey(Key('booking-dispute-$latestId'));
    await _reveal(tester, latestRow);
    expect(harness.app.disputesFor(booking.id), hasLength(2));
    expect(
      tester.getTopLeft(latestRow).dy,
      lessThan(tester.getTopLeft(firstRow).dy),
    );
    expect(find.byKey(const Key('booking-dispute-open')), findsNothing);
    expect(
      find.descendant(
        of: latestRow,
        matching: find.widgetWithText(StatusPill, 'RESOLVED'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: latestRow, matching: find.text('Refunded in full')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: latestRow,
        matching: find.widgetWithText(LedgerRow, 'Refunded'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: latestRow,
        matching: find.text(Money(booking.paidMinor).label),
      ),
      findsNWidgets(2),
    );
    expect(find.text('The full payment has been refunded.'), findsOneWidget);
    expectNoFieldInCard(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private address and host notes appear only after payment', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final bookingId = await _createPrivateBookingAwaitingPayment(repository);
    final harness = await pumpApp(
      tester,
      home: Scaffold(body: BookingDetailScreen(bookingId: bookingId)),
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.switchToBand('b1');
        await app.loadBooking(bookingId, viewAs: BookingSide.artist);
      },
    );

    expect(harness.app.bookingById(bookingId)?.viewerSide, BookingSide.artist);
    expect(
      harness.app.bookingById(bookingId)?.status,
      BookingStatus.awaitingPayment,
    );
    final pending = find.byKey(const Key('booking-location-pending'));
    await _reveal(tester, pending);
    expect(
      tester.widget<Text>(pending).data,
      'The exact address is shared once the deposit is paid.',
    );
    expect(find.text('Private event'), findsOneWidget);
    expect(find.text('Mission District · San Francisco'), findsOneWidget);
    expect(find.text("Jordan's courtyard"), findsNothing);
    expect(
      find.textContaining('120 Demo Lane', skipOffstage: false),
      findsNothing,
    );
    expect(find.text('Use the side gate for load-in.'), findsNothing);
    expect(find.byKey(const Key('booking-exact-address')), findsNothing);
    expect(find.byType(VenueMiniMap), findsNothing);
    expectNoFieldInCard(tester);

    final payment = (await repository.paymentsForBooking(bookingId)).single;
    final checkout = await repository.startInstallmentCheckout(payment.id);
    await repository.simulateCheckoutCompleted(checkout.sessionId);
    final refresh = find.byKey(const Key('booking-refresh'));
    await _reveal(tester, refresh, delta: -300);
    await tester.tap(refresh);
    await tester.pumpAndSettle();

    expect(harness.app.bookingById(bookingId)?.status, BookingStatus.confirmed);
    expect(harness.app.bookingById(bookingId)?.viewerSide, BookingSide.artist);
    final address = find.byKey(const Key('booking-exact-address'));
    await _reveal(tester, address);
    expect(tester.widget<Text>(address).data, '120 Demo Lane, San Francisco');
    expect(pending, findsNothing);
    expect(find.text('Mission District · San Francisco'), findsOneWidget);
    expect(find.text('HOST NOTES'), findsOneWidget);
    expect(find.text('Use the side gate for load-in.'), findsOneWidget);
    final map = tester.widget<VenueMiniMap>(find.byType(VenueMiniMap));
    final location = (await repository.privateLocationsFor('org2')).single;
    expect(map.approximate, isFalse);
    expect(map.venue.name, "Jordan's courtyard");
    expect(map.venue.addr, location.addr);
    expect(map.venue.point.latitude, location.lat);
    expect(map.venue.point.longitude, location.lng);
    expectNoFieldInCard(tester);
    expect(tester.takeException(), isNull);
  });

  for (final side in [BookingSide.artist, BookingSide.organizer]) {
    testWidgets(
      '${side.name} can report a live private booking safety concern',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final repository = DemoRepository(auth: auth);
        final bookingId = await _createPrivateBookingAwaitingPayment(
          repository,
        );
        final payment = (await repository.paymentsForBooking(bookingId)).single;
        final checkout = await repository.startInstallmentCheckout(payment.id);
        await repository.simulateCheckoutCompleted(checkout.sessionId);
        final harness = await pumpApp(
          tester,
          home: Scaffold(body: BookingDetailScreen(bookingId: bookingId)),
          auth: auth,
          repository: repository,
          beforePump: (app) async {
            if (side == BookingSide.artist) {
              app.switchToBand('b1');
            } else {
              app.switchToOrganization('org2');
            }
            await app.loadBooking(bookingId, viewAs: side);
          },
        );

        expect(harness.app.bookingById(bookingId)?.viewerSide, side);
        expect(
          harness.app.bookingById(bookingId)?.status,
          BookingStatus.confirmed,
        );
        final reportButton = find.byKey(const Key('booking-safety-report'));
        await _reveal(tester, reportButton);
        expect(
          tester.widget<EpButton>(reportButton).kind,
          EpButtonKind.outline,
        );
        expect(
          find.text(
            'EarPlug reviews every report. Reporting never affects your payout.',
          ),
          findsOneWidget,
        );
        await tester.tap(reportButton);
        await tester.pumpAndSettle();

        expect(find.byType(EpFormSheet), findsOneWidget);
        for (final category in [
          'safety',
          'harassment',
          'misrepresentation',
          'other',
        ]) {
          final chip = tester.widget<EpChip>(
            find.byKey(Key('booking-safety-category-$category')),
          );
          expect(chip.label, category.toUpperCase());
          expect(chip.active, category == 'safety');
        }
        final text = find.byKey(const Key('booking-safety-text'));
        expect(tester.widget<TextField>(text).minLines, greaterThan(1));
        final submit = find.byKey(const Key('booking-safety-submit'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('Report text is required'), findsOneWidget);
        expect(await repository.mySafetyReports(bookingId), isEmpty);
        expectNoFieldInCard(tester);

        final harassment = find.byKey(
          const Key('booking-safety-category-harassment'),
        );
        await tester.ensureVisible(harassment);
        await tester.tap(harassment);
        await tester.pumpAndSettle();
        expect(tester.widget<EpChip>(harassment).active, isTrue);
        const concern = 'A guest threatened the band during load-in.';
        await tester.enterText(text, '  $concern  ');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();

        expect(find.byType(EpFormSheet), findsNothing);
        final report = (await repository.mySafetyReports(bookingId)).single;
        expect(report.category, SafetyCategory.harassment);
        expect(report.text, concern);
        expect(report.status, 'open');
        expect(
          harness.app.safetyReportsFor(bookingId).single.reportId,
          report.reportId,
        );
        final card = find.byKey(
          Key('booking-safety-report-${report.reportId}'),
        );
        await _reveal(tester, card);
        expect(find.widgetWithText(SectionBar, 'SAFETY'), findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text('HARASSMENT')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text(concern)),
          findsOneWidget,
        );
        final dates = MaterialLocalizations.of(tester.element(card));
        expect(
          find.descendant(
            of: card,
            matching: find.text(
              dates.formatFullDate(report.createdAt.toLocal()),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.widgetWithText(StatusPill, 'OPEN'),
          ),
          findsOneWidget,
        );
        expectNoFieldInCard(tester);

        // Refresh must load reports again, including an admin's resolution.
        repository.platformAdmin = true;
        await repository.resolveSafetyReport(
          report.reportId,
          adminNote: 'Host contacted; access is safe.',
        );
        final refresh = find.byKey(const Key('booking-refresh'));
        await _reveal(tester, refresh, delta: -300);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        await _reveal(tester, card);
        expect(
          find.descendant(
            of: card,
            matching: find.widgetWithText(StatusPill, 'RESOLVED'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('Host contacted; access is safe.'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('artist cancels a private booking for safety without a reason', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final bookingId = await _createPrivateBookingAwaitingPayment(repository);
    final payment = (await repository.paymentsForBooking(bookingId)).single;
    final checkout = await repository.startInstallmentCheckout(payment.id);
    await repository.simulateCheckoutCompleted(checkout.sessionId);
    final harness = await pumpApp(
      tester,
      home: Scaffold(body: BookingDetailScreen(bookingId: bookingId)),
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.switchToBand('b1');
        await app.loadBooking(bookingId, viewAs: BookingSide.artist);
      },
    );

    expect(harness.app.bookingById(bookingId)?.status, BookingStatus.confirmed);
    await tester.tap(find.byKey(const Key('booking-cancel')));
    await tester.pumpAndSettle();
    final safety = find.byKey(const Key('booking-cancel-safety'));
    expect(tester.widget<CheckboxListTile>(safety).value, isFalse);
    expect(find.text("I don't feel safe"), findsOneWidget);
    expect(
      find.text(
        'Safety cancellations carry no penalty and refund the host in full.',
      ),
      findsOneWidget,
    );
    final reason = find.byKey(const Key('booking-cancel-reason'));
    final reasonField = find.ancestor(
      of: reason,
      matching: find.byType(EpLabeledField),
    );
    expect(tester.widget<EpLabeledField>(reasonField).required, isTrue);
    await tester.tap(safety);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(safety).value, isTrue);
    expect(tester.widget<EpLabeledField>(reasonField).required, isFalse);
    expect(tester.widget<TextField>(reason).controller!.text, isEmpty);
    expectNoFieldInCard(tester);
    final confirm = find.byKey(const Key('booking-cancel-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final cancelled = (await repository.booking(
      bookingId,
      viewAs: BookingSide.artist,
    ))!;
    expect(cancelled.status, BookingStatus.cancelledByArtist);
    expect(cancelled.cancellationKind, CancellationKind.safety);
    expect(cancelled.cancelReason, 'Safety concern');
    expect(cancelled.refundedMinor, payment.amountMinor);
    expect(
      harness.app.bookingById(bookingId)?.cancellationKind,
      CancellationKind.safety,
    );
    expect(find.byType(EpFormSheet), findsNothing);
    expect(find.byKey(const Key('booking-cancel')), findsNothing);
    expect(
      find.widgetWithText(StatusPill, 'CANCELLED FOR SAFETY'),
      findsOneWidget,
    );
    expect(find.textContaining('Cancelled for safety '), findsOneWidget);
    await _reveal(tester, find.byType(StatusTimeline), delta: -300);
    final step = tester
        .widget<StatusTimeline>(find.byType(StatusTimeline))
        .steps
        .single;
    expect(step.label, 'Cancelled for safety');
    expect(step.state, TimelineStepState.blocked);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh shows booking changes made elsewhere', (tester) async {
    final harness = await pumpApp(tester, home: const RootShell());
    await enterOrganizer(tester, harness, 'org1');
    harness.app.openBooking('bk1');
    await tester.pumpAndSettle();

    final booking = harness.app.bookingById('bk1')!;
    await harness.app.repository.withdrawOffer(
      bookingId: booking.id,
      expectedRevision: booking.revision,
    );
    expect(find.byKey(const Key('booking-withdraw')), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking-refresh')));
    await tester.pumpAndSettle();

    expect(harness.app.bookingById('bk1')?.status, BookingStatus.withdrawn);
    expect(find.byKey(const Key('booking-withdraw')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.text('WITHDRAWN'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('organizer sees the fee and can confirm withdrawal', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const RootShell());
    await enterOrganizer(tester, harness, 'org1');
    harness.app.openBooking('bk1');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.text('OFFER SENT'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('booking-withdraw')), findsOneWidget);
    expect(find.byKey(const Key('booking-accept')), findsNothing);
    expect(find.byKey(const Key('booking-decline')), findsNothing);
    expect(
      tester
          .widget<StatusTimeline>(find.byType(StatusTimeline))
          .steps
          .map((step) => step.state),
      [
        TimelineStepState.current,
        TimelineStepState.pending,
        TimelineStepState.pending,
        TimelineStepState.pending,
      ],
    );

    // The sticky action stays above RootShell's organizer tab bar.
    final sticky = find
        .ancestor(
          of: find.byKey(const Key('booking-withdraw')),
          matching: find.byType(SafeArea),
        )
        .first;
    expect(
      tester.getBottomRight(sticky).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(OrganizerTabBar)).dy),
    );

    final fee = find.byKey(const Key('booking-fee'));
    await _reveal(tester, fee);
    for (final label in [
      'Guarantee',
      const Money(30000).label,
      'EarPlug commission (10%)',
      const Money(3000).label,
      'Artist receives',
      const Money(27000).label,
    ]) {
      expect(
        find.descendant(of: fee, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expectNoFieldInCard(tester);

    await tester.tap(find.byKey(const Key('booking-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KEEP'));
    await tester.pumpAndSettle();
    expect(harness.app.bookingById('bk1')?.status, BookingStatus.offerSent);

    await tester.tap(find.byKey(const Key('booking-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM'));
    await tester.pumpAndSettle();
    expect(harness.app.bookingById('bk1')?.status, BookingStatus.withdrawn);
    expect(find.byKey(const Key('booking-withdraw')), findsNothing);
    await _reveal(tester, find.byType(StatusTimeline), delta: -300);
    final terminalStep = tester
        .widget<StatusTimeline>(find.byType(StatusTimeline))
        .steps
        .single;
    expect(terminalStep.label, BookingStatus.withdrawn.label);
    expect(terminalStep.state, TimelineStepState.blocked);
    expect(tester.takeException(), isNull);
  });

  testWidgets('band sees its own tab bar for a shared booking screen', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const RootShell());
    await enterOrganizer(tester, harness, 'org1');
    await (harness.app.repository as DemoRepository).removeOrganizationMember(
      organizationId: 'org1',
      userId: DemoData.demoUserId,
    );
    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    harness.app.openBooking('bk2');
    await tester.pumpAndSettle();

    // The cached viewer side wins even with an organization still selected.
    expect(harness.app.organizationId, 'org1');
    expect(find.byType(BandTabBar), findsOneWidget);
    expect(find.byType(OrganizerTabBar), findsNothing);
    expect(harness.app.identity, isA<BandIdentity>());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'artist accepts terms, awaits payment, and sees an address only when live',
    (tester) async {
      final screen = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(screen.dispose);
      final harness = await _pumpScreen(tester, screen);
      await _enterArtist(tester, harness, 'b2');
      final opened = <Uri>[];
      screen.value = BookingDetailScreen(
        bookingId: 'bk1',
        launch: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await tester.pumpAndSettle();

      expect(harness.app.bookingById('bk1')?.viewerSide, BookingSide.artist);
      expect(find.byKey(const Key('booking-accept')), findsOneWidget);
      expect(find.byKey(const Key('booking-decline')), findsOneWidget);
      expect(find.byKey(const Key('booking-withdraw')), findsNothing);
      await _reveal(tester, find.byType(VenueMiniMap));
      expect(
        tester.widget<VenueMiniMap>(find.byType(VenueMiniMap)).approximate,
        isTrue,
      );
      expect(find.byKey(const Key('booking-exact-address')), findsNothing);

      await tester.tap(find.byKey(const Key('booking-accept')));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'ACCEPT');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(harness.app.bookingById('bk1')?.status, BookingStatus.offerSent);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(
          'This booking is governed by the Artist Agreement.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.tapOnText(
        find.textRange.ofSubstring(
          'Artist Agreement',
          descendentOf: find.byType(AlertDialog),
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse(legalArtistAgreementUrl)]);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('booking-accept-terms')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('booking-accept-terms')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(
        harness.app.bookingById('bk1')?.status,
        BookingStatus.awaitingPayment,
      );
      expect(harness.app.bookingById('bk1')?.artistAcceptedTermsAt, isNotNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('booking-accept')), findsNothing);
      expect(find.byKey(const Key('booking-decline')), findsNothing);
      expect(find.byKey(const Key('booking-cancel')), findsOneWidget);
      await _reveal(tester, find.byType(VenueMiniMap));
      expect(find.byKey(const Key('booking-exact-address')), findsNothing);

      // Keep the same state to also exercise didUpdateWidget's booking-id reload.
      harness.app.switchToBand('b1');
      await tester.pumpAndSettle();
      screen.value = const BookingDetailScreen(bookingId: 'bk2');
      await tester.pumpAndSettle();
      expect(harness.app.bookingById('bk2')?.viewerSide, BookingSide.artist);
      expect(harness.app.bookingById('bk2')?.status, BookingStatus.confirmed);
      final address = find.byKey(const Key('booking-exact-address'));
      await _reveal(tester, address);
      expect(
        tester.widget<Text>(address).data,
        contains('2455 Harrison St, San Francisco'),
      );
      expect(
        tester.widget<VenueMiniMap>(find.byType(VenueMiniMap)).approximate,
        isFalse,
      );
      expect(find.byKey(const Key('booking-cancel')), findsOneWidget);
      await _reveal(
        tester,
        find.byKey(const Key('booking-counterparty-email')),
      );
      expect(find.text('hello@foghorn.example'), findsOneWidget);
      expect(tester.takeException(), isNull);
      harness.app.dispose();
    },
  );

  testWidgets(
    'organizer launches Checkout, refreshes payment, and previews a refund',
    (tester) async {
      final screen = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(screen.dispose);
      final harness = await _pumpScreen(tester, screen);
      await enterOrganizer(tester, harness, 'org1');
      final repository = harness.app.repository as DemoRepository;
      final bookingId = await _createAwaitingPaymentBooking(repository);
      final payment = (await repository.paymentsForBooking(bookingId)).single;
      final launched = <String>[];
      final launchPending = Completer<void>();
      harness.app.hostedUrlLauncher = (url) async {
        launched.add(url);
        await launchPending.future;
      };
      screen.value = BookingDetailScreen(bookingId: bookingId);
      await tester.pumpAndSettle();

      expect(
        harness.app.bookingById(bookingId)?.viewerSide,
        BookingSide.organizer,
      );
      final dates = MaterialLocalizations.of(
        tester.element(find.byType(BookingDetailScreen)),
      );
      expect(
        find.text(
          'Awaiting payment · due ${dates.formatFullDate(payment.dueAt.toLocal())}',
        ),
        findsOneWidget,
      );
      final row = find.byKey(const Key('booking-payment-0'));
      final pay = find.byKey(const Key('booking-pay-0'));
      final payNow = find.byKey(const Key('booking-pay-now'));
      await _reveal(tester, row);
      expect(find.byKey(const Key('booking-payments')), findsOneWidget);
      expect(row, findsOneWidget);
      expect(pay, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('PENDING')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(payment.label)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(payment.amount.label)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            'Due ${dates.formatFullDate(payment.dueAt.toLocal())}',
          ),
        ),
        findsOneWidget,
      );

      // Both actions share a guard, including taps before the next rebuild.
      await tester.tap(payNow);
      await tester.tap(payNow);
      await tester.pump();
      expect(launched, ['https://demo.stripe/checkout/${payment.id}']);
      expect(tester.widget<FilledButton>(payNow).onPressed, isNull);
      expect(tester.widget<TextButton>(pay).onPressed, isNull);
      launchPending.complete();
      await tester.pumpAndSettle();
      await _reveal(tester, pay);
      await tester.tap(pay);
      await tester.pumpAndSettle();
      expect(
        launched,
        List.filled(2, 'https://demo.stripe/checkout/${payment.id}'),
      );

      // Reopening the same installment provides a session for demo completion.
      final checkout = await repository.startInstallmentCheckout(payment.id);
      await repository.simulateCheckoutCompleted(checkout.sessionId);
      await _reveal(
        tester,
        find.byKey(const Key('booking-refresh')),
        delta: -300,
      );
      await tester.tap(find.byKey(const Key('booking-refresh')));
      await tester.pumpAndSettle();
      expect(
        harness.app.bookingById(bookingId)?.status,
        BookingStatus.confirmed,
      );
      expect(payNow, findsNothing);
      await _reveal(tester, row);
      final paidPayment = (await repository.paymentsForBooking(
        bookingId,
      )).single;
      expect(
        tester
            .widget<StatusPill>(
              find.descendant(of: row, matching: find.byType(StatusPill)),
            )
            .label,
        'Paid ${dates.formatFullDate(paidPayment.paidAt!.toLocal())}',
      );
      expect(pay, findsNothing);
      await _reveal(tester, find.byKey(const Key('booking-fee')), delta: -300);
      expect(
        find.text('Paid ${payment.amount.label} of ${payment.amount.label}'),
        findsOneWidget,
      );

      final booking = harness.app.bookingById(bookingId)!;
      final preview = (await harness.app.previewCancellation(booking))!;
      await tester.tap(find.byKey(const Key('booking-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Refund: ${Money(preview.refundMinor, booking.fee.currency).label} · Forfeited: ${Money(preview.forfeitedMinor, booking.fee.currency).label}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The artist receives ${Money(preview.artistPayoutMinor, booking.fee.currency).label}',
        ),
        findsOneWidget,
      );
      expectNoFieldInCard(tester);
      expect(tester.takeException(), isNull);
      harness.app.dispose();
    },
  );

  testWidgets(
    'artist sees payment progress, cancellation preview, and refunds without pay actions',
    (tester) async {
      final screen = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(screen.dispose);
      final harness = await _pumpScreen(tester, screen);
      await enterOrganizer(tester, harness, 'org1');
      final repository = harness.app.repository as DemoRepository;
      final bookingId = await _createAwaitingPaymentBooking(repository);
      await _enterArtist(tester, harness, 'b1');
      screen.value = BookingDetailScreen(bookingId: bookingId);
      await tester.pumpAndSettle();

      expect(
        harness.app.bookingById(bookingId)?.viewerSide,
        BookingSide.artist,
      );
      expect(
        find.text("Accepted · awaiting the organizer's payment"),
        findsOneWidget,
      );
      expect(find.byKey(const Key('booking-pay-now')), findsNothing);
      expect(find.byKey(const Key('booking-cancel')), findsOneWidget);
      await _reveal(tester, find.text("Waiting for the organizer's payment"));
      expect(find.byKey(const Key('booking-payment-0')), findsOneWidget);
      expect(find.byKey(const Key('booking-pay-0')), findsNothing);
      expect(find.text('PAY'), findsNothing);
      expect(find.text("Waiting for the organizer's payment"), findsOneWidget);

      final payment = (await repository.paymentsForBooking(bookingId)).single;
      final checkout = await repository.startInstallmentCheckout(payment.id);
      await repository.simulateCheckoutCompleted(checkout.sessionId);
      await _reveal(
        tester,
        find.byKey(const Key('booking-refresh')),
        delta: -300,
      );
      await tester.tap(find.byKey(const Key('booking-refresh')));
      await tester.pumpAndSettle();
      final booking = harness.app.bookingById(bookingId)!;
      final preview = (await harness.app.previewCancellation(booking))!;
      await tester.tap(find.byKey(const Key('booking-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Refund: ${Money(preview.refundMinor, booking.fee.currency).label} · Forfeited: ${Money(preview.forfeitedMinor, booking.fee.currency).label}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'You would receive ${Money(preview.artistPayoutMinor, booking.fee.currency).label}',
        ),
        findsOneWidget,
      );
      expectNoFieldInCard(tester);
      await tester.enterText(
        find.byKey(const Key('booking-cancel-reason')),
        'Schedule conflict',
      );
      await tester.tap(find.byKey(const Key('booking-cancel-confirm')));
      await tester.pumpAndSettle();
      final refunds = find.byKey(const Key('booking-refunds'));
      await _reveal(tester, refunds);
      expect(
        find.descendant(of: refunds, matching: find.text(payment.amount.label)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: refunds, matching: find.text('SUCCEEDED')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: refunds,
          matching: find.text('Artist cancellation'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      harness.app.dispose();
    },
  );

  testWidgets('Checkout launch failures show feedback and allow retry', (
    tester,
  ) async {
    final screen = ValueNotifier<Widget>(const SizedBox.shrink());
    addTearDown(screen.dispose);
    final harness = await _pumpScreen(tester, screen);
    await enterOrganizer(tester, harness, 'org1');
    final repository = harness.app.repository as DemoRepository;
    final bookingId = await _createAwaitingPaymentBooking(repository);
    harness.app.hostedUrlLauncher = (_) async {
      throw StateError('Could not open Checkout');
    };
    screen.value = BookingDetailScreen(bookingId: bookingId);
    await tester.pumpAndSettle();
    final pay = find.byKey(const Key('booking-pay-0'));
    await _reveal(tester, pay);
    await tester.tap(pay);
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('booking-feedback')));
    expect(find.text('Could not open Checkout'), findsOneWidget);

    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async {
      launched.add(url);
    };
    await tester.tap(find.byKey(const Key('booking-pay-now')));
    await tester.pumpAndSettle();
    expect(launched.single, startsWith('https://demo.stripe/checkout/'));
    expect(find.byKey(const Key('booking-feedback')), findsNothing);
    expect(tester.takeException(), isNull);
    harness.app.dispose();
  });

  testWidgets('artist can keep or decline a pending offer', (tester) async {
    final screen = ValueNotifier<Widget>(const SizedBox.shrink());
    addTearDown(screen.dispose);
    final harness = await _pumpScreen(tester, screen);
    await _enterArtist(tester, harness, 'b2');
    screen.value = const BookingDetailScreen(bookingId: 'bk1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('booking-decline')));
    await tester.pumpAndSettle();
    expect(find.text('Decline offer?'), findsOneWidget);
    await tester.tap(find.text('KEEP'));
    await tester.pumpAndSettle();
    expect(harness.app.bookingById('bk1')?.status, BookingStatus.offerSent);

    await tester.tap(find.byKey(const Key('booking-decline')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM'));
    await tester.pumpAndSettle();
    expect(harness.app.bookingById('bk1')?.status, BookingStatus.declined);
    expect(find.byKey(const Key('booking-accept')), findsNothing);
    expect(find.byKey(const Key('booking-decline')), findsNothing);
    expect(tester.takeException(), isNull);
    harness.app.dispose();
  });

  testWidgets(
    'organizer cancels a confirmed booking and can correct a rejected reason',
    (tester) async {
      final screen = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(screen.dispose);
      final harness = await _pumpScreen(tester, screen);
      await enterOrganizer(tester, harness, 'org1');
      screen.value = const BookingDetailScreen(bookingId: 'bk2');
      await tester.pumpAndSettle();
      await _reveal(tester, find.byKey(const Key('booking-fee')));
      expect(find.text('No fee · confirms on acceptance'), findsOneWidget);

      await tester.tap(find.byKey(const Key('booking-cancel')));
      await tester.pumpAndSettle();
      expectNoFieldInCard(tester);
      expect(find.textContaining('Refund:'), findsNothing);
      expect(find.textContaining('The artist receives'), findsNothing);
      final confirm = find.byKey(const Key('booking-cancel-confirm'));
      final reason = find.byKey(const Key('booking-cancel-reason'));
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Cancellation reason is required'), findsOneWidget);
      expect(find.byType(EpFormSheet), findsOneWidget);

      await tester.enterText(reason, 'x' * 501);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(EpFormSheet), findsOneWidget);
      expect(find.byKey(const Key('booking-feedback')), findsOneWidget);
      expect(
        find.text('Cancellation reason must be at most 500 characters'),
        findsOneWidget,
      );
      expect(harness.app.bookingById('bk2')?.status, BookingStatus.confirmed);

      await tester.enterText(reason, '  Schedule conflict  ');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        harness.app.bookingById('bk2')?.status,
        BookingStatus.cancelledByOrganizer,
      );
      expect(harness.app.bookingById('bk2')?.cancelReason, 'Schedule conflict');
      expect(find.byType(EpFormSheet), findsNothing);
      expect(find.byKey(const Key('booking-cancel')), findsNothing);
      expect(tester.takeException(), isNull);
      harness.app.dispose();
    },
  );

  testWidgets(
    'completed booking shows both published reviews without a write action',
    (tester) async {
      final screen = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(screen.dispose);
      final harness = await _pumpScreen(tester, screen);
      await enterOrganizer(tester, harness, 'org1');
      screen.value = const BookingDetailScreen(bookingId: 'bk3');
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('REVIEWS'));
      await _reveal(tester, find.text('A welcoming room and helpful crew.'));

      expect(find.text('Your review · 5/5'), findsOneWidget);
      expect(
        find.text('A prepared band and a wonderful show.'),
        findsOneWidget,
      );
      expect(find.text('Their review · 4/5'), findsOneWidget);
      expect(find.text('A welcoming room and helpful crew.'), findsOneWidget);
      expect(find.byKey(const Key('booking-review')), findsNothing);
      expect(find.byKey(const Key('booking-cancel')), findsNothing);
      expectNoFieldInCard(tester);
      expect(tester.takeException(), isNull);
      harness.app.dispose();
    },
  );

  testWidgets(
    'unreviewed completed booking keeps the other review blind and opens compose',
    (tester) async {
      final screen = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(screen.dispose);
      final harness = await _pumpScreen(tester, screen);
      await enterOrganizer(tester, harness, 'org1');
      screen.value = const BookingDetailScreen(bookingId: 'bk4');
      await tester.pumpAndSettle();
      final review = find.byKey(const Key('booking-review'));
      await _reveal(tester, review);

      expect(find.text('Hidden until both sides review'), findsOneWidget);
      expect(find.textContaining('Your review'), findsNothing);
      expect(
        find.text('Good show, though load-in could have been clearer.'),
        findsNothing,
      );
      expect(review, findsOneWidget);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.reviewCompose);
      expect(harness.app.current.param, 'bk4');
      expect(tester.takeException(), isNull);
      harness.app.dispose();
    },
  );

  testWidgets('event page action opens the public gig', (tester) async {
    final screen = ValueNotifier<Widget>(const SizedBox.shrink());
    addTearDown(screen.dispose);
    final harness = await _pumpScreen(tester, screen);
    await enterOrganizer(tester, harness, 'org1');
    screen.value = const BookingDetailScreen(bookingId: 'bk2');
    await tester.pumpAndSettle();
    final event = find.byKey(const Key('booking-view-gig'));
    await _reveal(tester, event);
    await tester.tap(event);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, 'demo-gig-bk2');
    expect(tester.takeException(), isNull);
    harness.app.dispose();
  });

  testWidgets('offer action failures show feedback in the page', (
    tester,
  ) async {
    final screen = ValueNotifier<Widget>(const SizedBox.shrink());
    addTearDown(screen.dispose);
    final harness = await _pumpScreen(tester, screen);
    await enterOrganizer(tester, harness, 'org1');
    screen.value = const BookingDetailScreen(bookingId: 'bk1');
    await tester.pumpAndSettle();
    // A concurrent repository write leaves the screen with a stale revision.
    await harness.app.repository.withdrawOffer(
      bookingId: 'bk1',
      expectedRevision: 1,
    );
    await tester.tap(find.byKey(const Key('booking-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('booking-feedback')));
    expect(find.text('Booking changed elsewhere'), findsOneWidget);
    expect(tester.takeException(), isNull);
    harness.app.dispose();
  });

  testWidgets('unknown booking shows not-found copy and supports retry', (
    tester,
  ) async {
    final screen = ValueNotifier<Widget>(
      const BookingDetailScreen(bookingId: 'does-not-exist'),
    );
    addTearDown(screen.dispose);
    final harness = await _pumpScreen(tester, screen);
    expect(find.text("This booking isn't available."), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();
    expect(find.text("This booking isn't available."), findsOneWidget);
    expect(tester.takeException(), isNull);
    harness.app.dispose();
  });
}

Future<void> _refreshDisputeBooking(WidgetTester tester) async {
  final refresh = find.byKey(const Key('booking-refresh'));
  await _reveal(tester, refresh, delta: -300);
  await tester.tap(refresh);
  await tester.pumpAndSettle();
}

Future<Booking> _createDisputeEligibleBooking(
  DemoRepository repository, {
  String bandId = 'b2',
  DateTime? startsAt,
  int grossMinor = 10005,
  bool pay = true,
}) async {
  repository.demoPaymentsEnabled = true;
  final created = await repository.createOpportunity(
    organizationId: 'org1',
    title: 'Booking dispute show',
    venueId: 'v1',
    startsAt: startsAt ?? DateTime.now().subtract(const Duration(hours: 2)),
    slots: const [
      SlotInput(role: SlotRole.headliner, guaranteeMinor: 0, required: true),
    ],
  );
  await repository.openOpportunity(
    opportunityId: created.opportunityId,
    expectedRevision: 1,
  );
  final opportunity = (await repository.opportunity(created.opportunityId))!;
  final applicationId = await repository.applyToOpportunity(
    opportunityId: opportunity.id,
    slotId: opportunity.slots.single.id,
    bandId: bandId,
    message: 'Ready to play.',
  );
  await repository.reviewApplication(
    applicationId: applicationId,
    action: ArtistApplicationReviewAction.shortlisted,
  );
  final sent = await repository.sendOffer(
    applicationId: applicationId,
    grossMinor: grossMinor,
    cancellationTemplate: CancellationTemplate.standard,
  );
  await repository.respondToOffer(
    bookingId: sent.bookingId,
    accept: true,
    expectedRevision: sent.revision,
  );
  if (pay && grossMinor > 0) {
    final payment = (await repository.paymentsForBooking(
      sent.bookingId,
    )).single;
    final checkout = await repository.startInstallmentCheckout(payment.id);
    await repository.simulateCheckoutCompleted(checkout.sessionId);
  }
  return (await repository.booking(sent.bookingId))!;
}

Future<String> _createPrivateBookingAwaitingPayment(
  DemoRepository repository,
) async {
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
  final sent = await repository.sendOffer(
    applicationId: applicationId,
    grossMinor: opportunity.slots.single.guaranteeMinor,
    cancellationTemplate: CancellationTemplate.standard,
  );
  await repository.respondToOffer(
    bookingId: sent.bookingId,
    accept: true,
    expectedRevision: sent.revision,
  );
  return sent.bookingId;
}

Future<String> _createAwaitingPaymentBooking(DemoRepository repository) async {
  repository.demoPaymentsEnabled = true;
  await repository.reviewApplication(
    applicationId: 'app1',
    action: ArtistApplicationReviewAction.shortlisted,
  );
  final sent = await repository.sendOffer(
    applicationId: 'app1',
    grossMinor: 15000,
    cancellationTemplate: CancellationTemplate.standard,
  );
  await repository.respondToOffer(
    bookingId: sent.bookingId,
    accept: true,
    expectedRevision: sent.revision,
  );
  return sent.bookingId;
}

Future<void> _enterArtist(
  WidgetTester tester,
  AppHarness harness,
  String bandId,
) async {
  await harness.auth.signInDemo();
  await tester.pumpAndSettle();
  await (harness.app.repository as DemoRepository).removeOrganizationMember(
    organizationId: 'org1',
    userId: DemoData.demoUserId,
  );
  harness.app.switchToBand(bandId);
  await tester.pumpAndSettle();
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

// Shadow the harness's lazy owning provider: these tests dispose AppState.
Future<AppHarness> _pumpScreen(
  WidgetTester tester,
  ValueNotifier<Widget> screen,
) {
  late AppState app;
  return pumpApp(
    tester,
    beforePump: (state) => app = state,
    home: Builder(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<Widget>(
                  valueListenable: screen,
                  builder: (_, child, _) => child,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
