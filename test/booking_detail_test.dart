import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/money.dart';
import 'package:earplug/screens/booking_detail.dart';
import 'package:earplug/widgets/common.dart';
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
      screen.value = const BookingDetailScreen(bookingId: 'bk1');
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
