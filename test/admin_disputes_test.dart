import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/date_names.dart';
import 'package:earplug/errors.dart';
import 'package:earplug/models.dart';
import 'package:earplug/money.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/admin_disputes.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

// Public checkout confirms the booking; the past start makes it eligible.
Future<Booking> _paidBooking(
  DemoRepository repository, {
  String bandId = 'b2',
}) async {
  repository.demoPaymentsEnabled = true;
  final created = await repository.createOpportunity(
    organizationId: 'org1',
    title: 'Dispute test show',
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
    bandId: bandId,
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
  final payment = (await repository.paymentsForBooking(sent.bookingId)).single;
  final checkout = await repository.startInstallmentCheckout(payment.id);
  await repository.simulateCheckoutCompleted(checkout.sessionId);
  return (await repository.booking(sent.bookingId))!;
}

class _FailingResolutionRepository extends DemoRepository {
  _FailingResolutionRepository({required super.auth});

  bool failResolution = true;

  @override
  Future<void> resolveDispute(
    String disputeId, {
    required DisputeResolution resolution,
    int? refundMinor,
    String? adminNote,
  }) async {
    if (failResolution) throw StateError('Resolution failed.');
    await super.resolveDispute(
      disputeId,
      resolution: resolution,
      refundMinor: refundMinor,
      adminNote: adminNote,
    );
  }
}

class _PagedDisputesRepository extends DemoRepository {
  _PagedDisputesRepository({required super.auth});

  bool failNextPage = true;

  @override
  Future<DisputesPage> openDisputes({String? cursor, int numItems = 25}) {
    if (cursor != null && failNextPage) {
      failNextPage = false;
      throw StateError('Page failed.');
    }
    return super.openDisputes(cursor: cursor, numItems: 1);
  }

  @override
  Future<AdminBookingsPage> adminBookings({
    required AdminBookingFilter filter,
    String? cursor,
    int numItems = 25,
  }) => super.adminBookings(filter: filter, cursor: cursor, numItems: 1);
}

void main() {
  testWidgets('admin reviews a refund request and issues a partial refund', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final booking = await _paidBooking(repository);
    final disputeId = await repository.openDispute(
      bookingId: booking.id,
      category: DisputeCategory.noShow,
      text: 'The band did not arrive for the show.',
      requestedRefundMinor: 5000,
    );
    final dispute = (await repository.disputesForBooking(booking.id)).single;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminDisputesScreen(),
    );

    final row = find.byKey(Key('admin-dispute-$disputeId'));
    expect(row, findsOneWidget);
    expect(find.text('Refund request'), findsOneWidget);
    expect(find.text('No-show'), findsOneWidget);
    expect(find.text(booking.opportunityTitle), findsOneWidget);
    expect(
      find.text('${booking.organizationName} · ${booking.bandName}'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Requested ${Money(5000, 'usd').label} of ${Money(10000, 'usd').label}',
      ),
      findsOneWidget,
    );
    expect(find.text(dateLabel(dispute.createdAt)), findsOneWidget);
    expect(find.text(dispute.text), findsOneWidget);
    expectNoFieldInCard(tester);

    await tester.tap(find.byKey(Key('admin-dispute-open-$disputeId')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, booking.id);

    final review = find.byKey(Key('admin-dispute-review-$disputeId'));
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(review, findsNothing);
    expect(row, findsOneWidget);
    expect(find.text('UNDER REVIEW'), findsOneWidget);
    expect(
      (await repository.disputesForBooking(booking.id)).single.status,
      DisputeStatus.underReview,
    );

    // Re-entering the queue must keep an unresolved case accessible too.
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminDisputesScreen(),
    );
    expect(row, findsOneWidget);
    expect(review, findsNothing);
    await tester.tap(find.byKey(Key('admin-dispute-resolve-$disputeId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-dispute-amount')), findsNothing);
    await tester.tap(
      find.byKey(const Key('admin-dispute-resolution-refunded_partial')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-dispute-amount')),
      '25.50',
    );
    await tester.enterText(
      find.byKey(const Key('admin-dispute-note')),
      '  Partial refund approved after review.  ',
    );
    expectNoFieldInCard(tester);
    final confirm = find.byKey(const Key('admin-dispute-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(row, findsNothing);
    expect(find.text('No open disputes.'), findsOneWidget);
    expect((await repository.booking(booking.id))!.refundedMinor, 2550);
    final resolved = (await repository.disputesForBooking(booking.id)).single;
    expect(resolved.resolution, DisputeResolution.refundedPartial);
    expect(resolved.adminNote, 'Partial refund approved after review.');
  });

  testWidgets('admin releases an artist dispute without refunding payment', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final booking = await _paidBooking(repository, bandId: 'b1');
    final disputeId = await repository.openDispute(
      bookingId: booking.id,
      category: DisputeCategory.other,
      text: 'The performance was cut short without notice.',
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminDisputesScreen(),
    );
    expect(find.text('Dispute'), findsOneWidget);
    expect(
      find.text('Paid ${Money(booking.paidMinor, 'usd').label}'),
      findsOneWidget,
    );
    expectNoFieldInCard(tester);

    await tester.tap(find.byKey(Key('admin-dispute-resolve-$disputeId')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('admin-dispute-resolution-released')),
    );
    await tester.enterText(find.byKey(const Key('admin-dispute-note')), '   ');
    expect(find.byKey(const Key('admin-dispute-amount')), findsNothing);
    await tester.tap(find.byKey(const Key('admin-dispute-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('admin-dispute-$disputeId')), findsNothing);
    final restored = (await repository.booking(booking.id))!;
    expect(restored.refundedMinor, 0);
    expect(restored.status, booking.status);
    expect(restored.status, isNot(BookingStatus.disputed));
    final resolved = (await repository.disputesForBooking(booking.id)).single;
    expect(resolved.resolution, DisputeResolution.released);
    expect(resolved.adminNote, isNull);
  });

  testWidgets('invalid partial refunds stay open and failed saves can retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _FailingResolutionRepository(auth: auth)
      ..platformAdmin = true;
    final booking = await _paidBooking(repository);
    final disputeId = await repository.openDispute(
      bookingId: booking.id,
      category: DisputeCategory.payment,
      text: 'Please review the payment for this show.',
      requestedRefundMinor: 5000,
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminDisputesScreen(),
    );
    await tester.tap(find.byKey(Key('admin-dispute-resolve-$disputeId')));
    await tester.pumpAndSettle();
    final partial = find.byKey(
      const Key('admin-dispute-resolution-refunded_partial'),
    );
    await tester.tap(partial);
    await tester.pumpAndSettle();
    expect(tester.widget<EpChip>(partial).active, isTrue);
    final amount = find.byKey(const Key('admin-dispute-amount'));
    final confirm = find.byKey(const Key('admin-dispute-confirm'));
    for (final invalid in [
      '',
      'bad',
      'NaN',
      'Infinity',
      '-1',
      '0',
      '0.001',
      '100',
      '101',
    ]) {
      await tester.ensureVisible(amount);
      await tester.enterText(amount, invalid);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(InlineFormFeedback), findsOneWidget);
      expect(find.text('RESOLVE DISPUTE'), findsOneWidget);
      expect((await repository.booking(booking.id))!.refundedMinor, 0);
      expect(tester.takeException(), isNull);
    }

    await tester.ensureVisible(amount);
    await tester.enterText(amount, '12.34');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text(genericErrorMessage), findsOneWidget);
    expect(find.text('RESOLVE DISPUTE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectNoFieldInCard(tester);

    repository.failResolution = false;
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('admin-dispute-$disputeId')), findsNothing);
    expect((await repository.booking(booking.id))!.refundedMinor, 1234);
  });

  testWidgets('dispute pagination retries and includes cases under review', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _PagedDisputesRepository(auth: auth)
      ..platformAdmin = true;
    final disputeIds = <String>[];
    for (var index = 0; index < 3; index++) {
      final booking = await _paidBooking(repository);
      disputeIds.add(
        await repository.openDispute(
          bookingId: booking.id,
          category: DisputeCategory.other,
          text: 'Please review performance $index.',
          requestedRefundMinor: 5000,
        ),
      );
    }
    // This older booking must be reached through the supplemental pages.
    await repository.startDisputeReview(disputeIds.first);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminDisputesScreen(),
    );
    final reviewedRow = find.byKey(Key('admin-dispute-${disputeIds.first}'));
    expect(reviewedRow, findsNothing);
    final firstPageRow = find.byKey(Key('admin-dispute-${disputeIds.last}'));
    expect(firstPageRow, findsOneWidget);
    final more = find.byKey(const Key('admin-disputes-more'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(tester.widget<EpButton>(more).label, 'RETRY');
    expect(harness.app.toast, genericErrorMessage);
    expect(firstPageRow, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      more,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<EpButton>(more).label, 'LOAD MORE');
    await tester.scrollUntilVisible(
      more,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(more, findsNothing);
    await tester.scrollUntilVisible(
      reviewedRow,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(reviewedRow, findsOneWidget);
    expect(
      find.byKey(Key('admin-dispute-review-${disputeIds.first}')),
      findsNothing,
    );
    expectNoFieldInCard(tester);
  });

  testWidgets('non-admins cannot view disputes', (tester) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const AdminDisputesScreen(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-not-authorized')), findsOneWidget);
    expect(find.byKey(const Key('admin-disputes-more')), findsNothing);
    expectNoFieldInCard(tester);
  });
}
