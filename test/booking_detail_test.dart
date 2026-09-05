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
      expect(find.byKey(const Key('booking-cancel')), findsNothing);
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
