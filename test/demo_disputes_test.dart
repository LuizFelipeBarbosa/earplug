import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    contains(message),
  ),
);

// Public demo checkout reaches confirmed. A past start makes it dispute-eligible
// without changing the shared fixtures or simulating the completion scheduler.
Future<Booking> _paidBooking(
  DemoRepository repo, {
  String bandId = 'b2',
  int grossMinor = 10000,
  DateTime? startsAt,
  bool completeCheckout = true,
}) async {
  repo.demoPaymentsEnabled = true;
  final created = await repo.createOpportunity(
    organizationId: 'org1',
    title: 'Dispute test show',
    venueId: 'v1',
    startsAt: startsAt ?? DateTime.now().subtract(const Duration(days: 5)),
    slots: const [
      SlotInput(role: SlotRole.headliner, guaranteeMinor: 0, required: true),
    ],
  );
  await repo.openOpportunity(
    opportunityId: created.opportunityId,
    expectedRevision: 1,
  );
  final opportunity = (await repo.opportunity(created.opportunityId))!;
  final applicationId = await repo.applyToOpportunity(
    opportunityId: opportunity.id,
    slotId: opportunity.slots.single.id,
    bandId: bandId,
    message: 'Ready to play.',
  );
  await repo.reviewApplication(
    applicationId: applicationId,
    action: ArtistApplicationReviewAction.shortlisted,
  );
  final sent = await repo.sendOffer(
    applicationId: applicationId,
    grossMinor: grossMinor,
    cancellationTemplate: CancellationTemplate.standard,
  );
  await repo.respondToOffer(
    bookingId: sent.bookingId,
    accept: true,
    expectedRevision: sent.revision,
  );
  if (grossMinor > 0 && completeCheckout) {
    final payment = (await repo.paymentsForBooking(sent.bookingId)).single;
    final checkout = await repo.startInstallmentCheckout(payment.id);
    await repo.simulateCheckoutCompleted(checkout.sessionId);
  }
  return (await repo.booking(sent.bookingId))!;
}

void main() {
  test('organizer refund request is reviewed and partially refunded', () async {
    final repo = DemoRepository(auth: FakeAuthService());
    expect((await repo.featureFlags()).disputes, isTrue);
    final booking = await _paidBooking(repo);
    expect(booking.status, BookingStatus.confirmed);
    expect(booking.paidMinor, 10000);
    final disputeId = await repo.openDispute(
      bookingId: booking.id,
      category: DisputeCategory.noShow,
      text: '  The band did not show up for the performance.  ',
      requestedRefundMinor: 5000,
    );
    final disputed = (await repo.booking(booking.id))!;
    expect(disputed.status, BookingStatus.disputed);
    expect(disputed.revision, booking.revision + 1);
    expect(disputed.payoutHoldReasons, contains('dispute'));
    final opened = (await repo.disputesForBooking(booking.id)).single;
    expect(opened.disputeId, disputeId);
    expect(opened.side, DisputeSide.organizer);
    expect(opened.category, DisputeCategory.noShow);
    expect(opened.text, 'The band did not show up for the performance.');
    expect(opened.requestedRefundMinor, 5000);
    expect(opened.status, DisputeStatus.open);
    expect(opened.resolution, isNull);
    expect(opened.resolvedAt, isNull);
    await expectLater(
      repo.openDispute(
        bookingId: booking.id,
        category: DisputeCategory.payment,
        text: 'A second refund request.',
        requestedRefundMinor: 5000,
      ),
      _stateError('already has an open dispute'),
    );

    // User and admin actions share the same in-memory store.
    repo.platformAdmin = true;
    final adminRow = (await repo.adminBookings(
      filter: AdminBookingFilter.disputed,
    )).items.single;
    expect(adminRow.bookingId, booking.id);
    expect(adminRow.title, booking.opportunityTitle);
    expect(adminRow.organizationName, booking.organizationName);
    expect(adminRow.bandName, booking.bandName);
    expect(adminRow.status, BookingStatus.disputed);
    expect(adminRow.paidMinor, booking.paidMinor);
    expect(adminRow.refundedMinor, 0);
    expect(adminRow.openDisputeId, disputeId);
    expect(
      (await repo.adminBookings(
        filter: AdminBookingFilter.held,
      )).items.map((row) => row.bookingId),
      contains(booking.id),
    );
    final openRow = (await repo.openDisputes()).items.single;
    expect(openRow.disputeId, disputeId);
    expect(openRow.bookingTitle, booking.opportunityTitle);
    expect(openRow.organizationName, booking.organizationName);
    expect(openRow.bandName, booking.bandName);
    expect(openRow.paidMinor, booking.paidMinor);
    expect(openRow.bookingStatus, BookingStatus.disputed);
    await repo.startDisputeReview(disputeId);
    expect(
      (await repo.disputesForBooking(booking.id)).single.status,
      DisputeStatus.underReview,
    );
    expect((await repo.openDisputes()).items, isEmpty);
    expect(
      (await repo.adminBookings(
        filter: AdminBookingFilter.disputed,
      )).items.single.openDisputeId,
      isNull,
    );
    await expectLater(
      repo.startDisputeReview(disputeId),
      _stateError('Only open disputes'),
    );
    await expectLater(
      repo.openDispute(
        bookingId: booking.id,
        category: DisputeCategory.payment,
        text: 'Another request while under review.',
        requestedRefundMinor: 5000,
      ),
      _stateError('already has an open dispute'),
    );
    await repo.resolveDispute(
      disputeId,
      resolution: DisputeResolution.refundedPartial,
      refundMinor: 2500,
      adminNote: 'Partial refund issued.',
    );
    final restored = (await repo.booking(booking.id))!;
    expect(restored.status, booking.status);
    expect(restored.refundedMinor, 2500);
    expect(restored.paidMinor, booking.paidMinor);
    expect(restored.payoutHoldReasons, booking.payoutHoldReasons);
    expect(restored.revision, booking.revision + 2);
    repo.platformAdmin = false;
    final resolved = (await repo.disputesForBooking(booking.id)).single;
    expect(resolved.status, DisputeStatus.resolved);
    expect(resolved.resolution, DisputeResolution.refundedPartial);
    expect(resolved.resolvedRefundMinor, 2500);
    expect(resolved.adminNote, 'Partial refund issued.');
    expect(resolved.createdAt, opened.createdAt);
    expect(resolved.resolvedAt!.isBefore(opened.createdAt), isFalse);
  });

  test(
    'band admin takes precedence and release restores the booking',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      final booking = await _paidBooking(repo, bandId: 'b1');
      await expectLater(
        repo.openDispute(
          bookingId: booking.id,
          category: DisputeCategory.other,
          text: 'Set was cut short without notice.',
          requestedRefundMinor: 100,
        ),
        _stateError('Artists cannot request a refund'),
      );
      final id = await repo.openDispute(
        bookingId: booking.id,
        category: DisputeCategory.other,
        text: 'Set was cut short without notice.',
      );
      expect(
        (await repo.disputesForBooking(booking.id)).single.side,
        DisputeSide.artist,
      );
      expect((await repo.booking(booking.id))!.status, BookingStatus.disputed);
      repo.platformAdmin = true;
      await repo.resolveDispute(id, resolution: DisputeResolution.released);
      final restored = (await repo.booking(booking.id))!;
      expect(restored.status, BookingStatus.confirmed);
      expect(restored.refundedMinor, 0);
      expect(
        (await repo.disputesForBooking(booking.id)).single.resolvedRefundMinor,
        0,
      );
      await expectLater(
        repo.resolveDispute(id, resolution: DisputeResolution.released),
        _stateError('already resolved'),
      );
    },
  );

  test(
    'invalid requests leave bookings and dispute history unchanged',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      final booking = await _paidBooking(repo);
      for (final amount in <int?>[null, 0, -1, booking.paidMinor + 1]) {
        await expectLater(
          repo.openDispute(
            bookingId: booking.id,
            category: DisputeCategory.payment,
            text: 'Please review this payment.',
            requestedRefundMinor: amount,
          ),
          _stateError('refund amount must be positive'),
        );
      }
      for (final details in ['', 'short', 'x' * 2001]) {
        await expectLater(
          repo.openDispute(
            bookingId: booking.id,
            category: DisputeCategory.payment,
            text: details,
            requestedRefundMinor: 100,
          ),
          _stateError('between 10 and 2000 characters'),
        );
      }
      final future = await _paidBooking(
        repo,
        startsAt: DateTime.now().add(const Duration(days: 5)),
      );
      final free = await _paidBooking(repo, grossMinor: 0);
      final unpaid = await _paidBooking(repo, completeCheckout: false);
      for (final (invalid, message) in [
        (future, 'after the show starts'),
        (free, 'positive fee'),
        (unpaid, 'confirmed, completed, or paid'),
      ]) {
        await expectLater(
          repo.openDispute(
            bookingId: invalid.id,
            category: DisputeCategory.payment,
            text: 'Please review this payment.',
            requestedRefundMinor: 100,
          ),
          _stateError(message),
        );
        expect((await repo.booking(invalid.id))!.status, invalid.status);
        expect(await repo.disputesForBooking(invalid.id), isEmpty);
      }
      expect((await repo.booking(booking.id))!.status, booking.status);
      expect(await repo.disputesForBooking(booking.id), isEmpty);
    },
  );

  test('admin and booking-party access is enforced', () async {
    final repo = DemoRepository(auth: FakeAuthService());
    final booking = await _paidBooking(repo);
    final id = await repo.openDispute(
      bookingId: booking.id,
      category: DisputeCategory.payment,
      text: 'Please review this payment.',
      requestedRefundMinor: 1000,
    );
    await expectLater(
      repo.openDisputes(),
      _stateError('Platform admin access required'),
    );
    await expectLater(
      repo.adminBookings(filter: AdminBookingFilter.all),
      _stateError('Platform admin access required'),
    );
    await expectLater(
      repo.startDisputeReview(id),
      _stateError('Platform admin access required'),
    );
    await expectLater(
      repo.resolveDispute(id, resolution: DisputeResolution.dismissed),
      _stateError('Platform admin access required'),
    );
    await repo.removeOrganizationMember(
      organizationId: 'org1',
      userId: DemoData.demoUserId,
    );
    await expectLater(
      repo.disputesForBooking(booking.id),
      _stateError('Not permitted'),
    );
    await expectLater(
      repo.openDispute(
        bookingId: booking.id,
        category: DisputeCategory.payment,
        text: 'Another refund request.',
        requestedRefundMinor: 100,
      ),
      _stateError('Not permitted'),
    );
    repo.platformAdmin = true;
    expect((await repo.disputesForBooking(booking.id)).single.disputeId, id);
    await expectLater(
      repo.startDisputeReview('missing'),
      _stateError('Dispute not found'),
    );
    await expectLater(
      repo.resolveDispute('missing', resolution: DisputeResolution.dismissed),
      _stateError('Dispute not found'),
    );
  });

  test('resolution validation, dismissal, history and full refund', () async {
    final repo = DemoRepository(auth: FakeAuthService());
    final booking = await _paidBooking(repo);
    final id = await repo.openDispute(
      bookingId: booking.id,
      category: DisputeCategory.noShow,
      text: 'The band did not show up for the performance.',
      requestedRefundMinor: booking.paidMinor,
    );
    repo.platformAdmin = true;
    for (final amount in <int?>[
      null,
      -1,
      0,
      booking.paidMinor,
      booking.paidMinor + 1,
    ]) {
      await expectLater(
        repo.resolveDispute(
          id,
          resolution: DisputeResolution.refundedPartial,
          refundMinor: amount,
        ),
        _stateError('partial refund must be positive'),
      );
    }
    for (final resolution in [
      DisputeResolution.released,
      DisputeResolution.dismissed,
    ]) {
      await expectLater(
        repo.resolveDispute(id, resolution: resolution, refundMinor: 100),
        _stateError('cannot include a refund'),
      );
    }
    await expectLater(
      repo.resolveDispute(id, resolution: DisputeResolution.unknown),
      _stateError('Unknown dispute resolution'),
    );
    expect(
      (await repo.disputesForBooking(booking.id)).single.status,
      DisputeStatus.open,
    );
    expect((await repo.booking(booking.id))!.refundedMinor, 0);
    await repo.resolveDispute(id, resolution: DisputeResolution.dismissed);
    expect((await repo.booking(booking.id))!.status, booking.status);
    final secondId = await repo.openDispute(
      bookingId: booking.id,
      category: DisputeCategory.noShow,
      text: 'Additional details about the missed performance.',
      requestedRefundMinor: booking.paidMinor,
    );
    final history = await repo.disputesForBooking(booking.id);
    expect(history.map((dispute) => dispute.disputeId), [secondId, id]);
    await repo.resolveDispute(
      secondId,
      resolution: DisputeResolution.refundedFull,
    );
    final refunded = (await repo.booking(booking.id))!;
    expect(refunded.status, BookingStatus.refunded);
    expect(refunded.refundedMinor, booking.paidMinor);
    expect(refunded.payoutHoldReasons, booking.payoutHoldReasons);
    expect(
      (await repo.disputesForBooking(booking.id)).first.resolvedRefundMinor,
      booking.paidMinor,
    );
    expect(
      (await repo.adminBookings(filter: AdminBookingFilter.disputed)).items,
      isEmpty,
    );
  });

  test('admin lists paginate and filter current booking state', () async {
    final repo = DemoRepository(auth: FakeAuthService());
    final first = await _paidBooking(repo);
    final second = await _paidBooking(repo, bandId: 'b1');
    final unpaid = await _paidBooking(repo, completeCheckout: false);
    for (final booking in [first, second]) {
      await repo.openDispute(
        bookingId: booking.id,
        category: DisputeCategory.other,
        text: 'Please review the performance details.',
        requestedRefundMinor: booking.bandId == 'b2' ? 100 : null,
      );
    }
    repo.platformAdmin = true;
    final firstPage = await repo.openDisputes(numItems: 1);
    expect(firstPage.items, hasLength(1));
    expect(firstPage.isDone, isFalse);
    final secondPage = await repo.openDisputes(
      cursor: firstPage.continueCursor,
      numItems: 1,
    );
    expect(secondPage.items, hasLength(1));
    expect(secondPage.isDone, isTrue);
    expect([
      firstPage.items.single.bookingId,
      secondPage.items.single.bookingId,
    ], unorderedEquals([first.id, second.id]));
    expect(
      firstPage.items.single.createdAt.isBefore(
        secondPage.items.single.createdAt,
      ),
      isFalse,
    );
    expect(
      (await repo.openDisputes(cursor: secondPage.continueCursor)).items,
      isEmpty,
    );
    final all = await repo.adminBookings(filter: AdminBookingFilter.all);
    expect(
      all.items.map((row) => row.bookingId),
      containsAll([first.id, second.id, unpaid.id]),
    );
    final bookingsPage = await repo.adminBookings(
      filter: AdminBookingFilter.disputed,
      numItems: 1,
    );
    final nextPage = await repo.adminBookings(
      filter: AdminBookingFilter.disputed,
      cursor: bookingsPage.continueCursor,
      numItems: 1,
    );
    expect(bookingsPage.isDone, isFalse);
    expect(nextPage.isDone, isTrue);
    expect(
      [...bookingsPage.items, ...nextPage.items].map((row) => row.bookingId),
      unorderedEquals([first.id, second.id]),
    );
    final awaitingPayment = await repo.adminBookings(
      filter: AdminBookingFilter.awaitingPayment,
    );
    expect(
      awaitingPayment.items.map((row) => row.bookingId),
      contains(unpaid.id),
    );
    expect(
      awaitingPayment.items.every(
        (row) => row.status == BookingStatus.awaitingPayment,
      ),
      isTrue,
    );
  });
}
