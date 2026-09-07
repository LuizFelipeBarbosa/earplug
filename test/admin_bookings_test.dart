import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/errors.dart';
import 'package:earplug/models.dart';
import 'package:earplug/money.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/admin_bookings.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

// Exercise the public checkout flow with a past start so disputes are eligible.
Future<Booking> _paidBooking(
  DemoRepository repository, {
  required String title,
  bool completeCheckout = true,
}) async {
  repository.demoPaymentsEnabled = true;
  final created = await repository.createOpportunity(
    organizationId: 'org1',
    title: title,
    venueId: 'v1',
    startsAt: DateTime.now().subtract(const Duration(days: 5)),
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
    bandId: 'b2',
    message: 'Ready to play.',
  );
  await repository.reviewApplication(
    applicationId: applicationId,
    action: ArtistApplicationReviewAction.shortlisted,
  );
  final sent = await repository.sendOffer(
    applicationId: applicationId,
    grossMinor: 10000,
    cancellationTemplate: CancellationTemplate.standard,
  );
  await repository.respondToOffer(
    bookingId: sent.bookingId,
    accept: true,
    expectedRevision: sent.revision,
  );
  if (completeCheckout) {
    final payment = (await repository.paymentsForBooking(
      sent.bookingId,
    )).single;
    final checkout = await repository.startInstallmentCheckout(payment.id);
    await repository.simulateCheckoutCompleted(checkout.sessionId);
  }
  return (await repository.booking(sent.bookingId))!;
}

class _PagedBookingsRepository extends DemoRepository {
  _PagedBookingsRepository({required super.auth});

  bool failNextPage = true;

  @override
  Future<AdminBookingsPage> adminBookings({
    required AdminBookingFilter filter,
    String? cursor,
    int numItems = 25,
  }) {
    if (cursor != null && failNextPage) {
      failNextPage = false;
      throw StateError('Page failed.');
    }
    return super.adminBookings(filter: filter, cursor: cursor, numItems: 1);
  }
}

void main() {
  testWidgets('admin filters disputed bookings and opens a booking', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final disputed = await _paidBooking(repository, title: 'Disputed show');
    final confirmed = await _paidBooking(repository, title: 'Confirmed show');
    await repository.openDispute(
      bookingId: disputed.id,
      category: DisputeCategory.noShow,
      text: 'The band did not arrive for the show.',
      requestedRefundMinor: 5000,
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminBookingsScreen(),
    );
    final all = find.byKey(const Key('admin-bookings-filter-all'));
    expect(tester.widget<EpChip>(all).active, isTrue);

    await tester.tap(find.byKey(const Key('admin-bookings-filter-disputed')));
    await tester.pumpAndSettle();

    final disputedRow = find.byKey(Key('admin-booking-${disputed.id}'));
    final confirmedRow = find.byKey(Key('admin-booking-${confirmed.id}'));
    expect(disputedRow, findsOneWidget);
    expect(confirmedRow, findsNothing);
    expect(
      find.byKey(Key('admin-booking-${disputed.id}-dispute')),
      findsOneWidget,
    );
    expect(
      find.text('Paid ${Money(disputed.paidMinor, 'usd').label}'),
      findsOneWidget,
    );
    expectNoFieldInCard(tester);

    await tester.tap(all);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      confirmedRow,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(confirmedRow, findsOneWidget);
    expect(
      find.byKey(Key('admin-booking-${confirmed.id}-dispute')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      disputedRow,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(disputedRow, findsOneWidget);

    await tester.tap(disputedRow);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, disputed.id);
  });

  testWidgets('held and awaiting-payment filters use booking state', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final held = await _paidBooking(repository, title: 'Held show');
    final unpaid = await _paidBooking(
      repository,
      title: 'Unpaid show',
      completeCheckout: false,
    );
    await repository.openDispute(
      bookingId: held.id,
      category: DisputeCategory.payment,
      text: 'Please review the show payment.',
      requestedRefundMinor: 5000,
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminBookingsScreen(),
    );

    await tester.tap(find.byKey(const Key('admin-bookings-filter-held')));
    await tester.pumpAndSettle();
    final heldRow = find.byKey(Key('admin-booking-${held.id}'));
    expect(heldRow, findsOneWidget);
    final holdChips = tester.widgetList<EpChip>(
      find.descendant(of: heldRow, matching: find.byType(EpChip)),
    );
    expect(holdChips.map((chip) => chip.label), contains('dispute'));
    expect(
      holdChips.every((chip) => chip.readOnly && chip.onTap == null),
      isTrue,
    );

    final awaiting = find.byKey(
      const Key('admin-bookings-filter-awaitingPayment'),
    );
    await tester.ensureVisible(awaiting);
    await tester.tap(awaiting);
    await tester.pumpAndSettle();
    expect(heldRow, findsNothing);
    expect(find.byKey(Key('admin-booking-${unpaid.id}')), findsOneWidget);
    expectNoFieldInCard(tester);
  });

  testWidgets('booking pagination retains rows on failure and retries', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _PagedBookingsRepository(auth: auth)
      ..platformAdmin = true;
    final first = await _paidBooking(repository, title: 'First disputed show');
    final second = await _paidBooking(
      repository,
      title: 'Second disputed show',
    );
    for (final booking in [first, second]) {
      await repository.openDispute(
        bookingId: booking.id,
        category: DisputeCategory.payment,
        text: 'Please review this show payment.',
        requestedRefundMinor: 5000,
      );
    }
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminBookingsScreen(),
    );
    await tester.tap(find.byKey(const Key('admin-bookings-filter-disputed')));
    await tester.pumpAndSettle();
    final firstRow = find.byKey(Key('admin-booking-${first.id}'));
    final secondRow = find.byKey(Key('admin-booking-${second.id}'));
    expect(secondRow, findsOneWidget);
    expect(firstRow, findsNothing);
    final more = find.byKey(const Key('admin-bookings-more'));
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(tester.widget<EpButton>(more).label, 'RETRY');
    expect(harness.app.toast, genericErrorMessage);
    expect(secondRow, findsOneWidget);
    expect(firstRow, findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(more, findsNothing);
    expect(secondRow, findsOneWidget);
    expect(firstRow, findsOneWidget);
    expectNoFieldInCard(tester);
  });

  testWidgets('non-admins cannot view bookings', (tester) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminBookingsScreen(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-not-authorized')), findsOneWidget);
    expect(find.byKey(const Key('admin-bookings-filter-all')), findsNothing);
    expect(find.byKey(const Key('admin-bookings-more')), findsNothing);
  });
}
