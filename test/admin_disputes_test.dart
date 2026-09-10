import 'dart:async';

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
import 'support/stub_repository.dart';

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

class _DelayedResolutionRepository extends DemoRepository {
  _DelayedResolutionRepository({
    required super.auth,
    required this.completeResolution,
    this.acknowledgeResolution,
  });

  final Completer<void> completeResolution;
  final Completer<void>? acknowledgeResolution;
  bool resolutionStarted = false;
  bool resolutionApplied = false;
  int openDisputesCalls = 0;
  VoidCallback? onOpenDisputes;

  @override
  Future<void> resolveDispute(
    String disputeId, {
    required DisputeResolution resolution,
    int? refundMinor,
    String? adminNote,
  }) async {
    resolutionStarted = true;
    await completeResolution.future;
    // The demo mutation removes the case from openDisputes and restores the
    // booking's status, so the review queue also stops returning it.
    await super.resolveDispute(
      disputeId,
      resolution: resolution,
      refundMinor: refundMinor,
      adminNote: adminNote,
    );
    resolutionApplied = true;
    await acknowledgeResolution?.future;
  }

  @override
  Future<DisputesPage> openDisputes({String? cursor, int numItems = 25}) {
    openDisputesCalls++;
    onOpenDisputes?.call();
    return super.openDisputes(cursor: cursor, numItems: numItems);
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
  // Exercise both response orderings: the queue stays unchanged until success,
  // or it receives resolved data before the mutation response arrives.
  for (final refreshBeforeAcknowledgement in [false, true]) {
    testWidgets(
      refreshBeforeAcknowledgement
          ? 'late dispute resolution closes after the queue refreshes to empty'
          : 'late dispute resolution closes the sheet before refreshing',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final completeResolution = Completer<void>();
        final acknowledgeResolution = refreshBeforeAcknowledgement
            ? Completer<void>()
            : null;
        final repository = _DelayedResolutionRepository(
          auth: auth,
          completeResolution: completeResolution,
          acknowledgeResolution: acknowledgeResolution,
        )..platformAdmin = true;
        final booking = await _paidBooking(repository);
        final disputeId = await repository.openDispute(
          bookingId: booking.id,
          side: DisputeSide.organizer,
          category: DisputeCategory.noShow,
          text: 'The band did not arrive for the show.',
          requestedRefundMinor: 5000,
        );
        final harness = await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          home: const AdminDisputesScreen(),
        );
        final row = find.byKey(Key('admin-dispute-$disputeId'));
        expect(row, findsOneWidget);
        expect(repository.openDisputesCalls, 1);
        final adminRoute = ModalRoute.of(
          tester.element(find.byType(AdminDisputesScreen)),
        )!;
        final routeCurrentOnReload = <bool>[];
        repository.onOpenDisputes = () =>
            routeCurrentOnReload.add(adminRoute.isCurrent);

        await tester.tap(find.byKey(Key('admin-dispute-resolve-$disputeId')));
        await tester.pumpAndSettle();
        expect(adminRoute.isCurrent, isFalse);
        expectNoFieldInCard(tester);
        final confirm = find.byKey(const Key('admin-dispute-confirm'));
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pump();

        expect(repository.resolutionStarted, isTrue);
        expect(completeResolution.isCompleted, isFalse);
        expect(repository.resolutionApplied, isFalse);
        expect(find.text('Resolve dispute'), findsOneWidget);
        expect(tester.widget<EpButton>(confirm).onTap, isNull);
        expect(repository.openDisputesCalls, 1);

        // Rebuild the listening screen while the mutation is still in flight.
        await harness.app.refreshOrganizationBookings(booking.organizationId);
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('Resolve dispute'), findsOneWidget);
        expect(tester.widget<EpButton>(confirm).onTap, isNull);
        expect(repository.openDisputesCalls, 1);

        completeResolution.complete();
        if (acknowledgeResolution != null) {
          await tester.pump();
          expect(repository.resolutionApplied, isTrue);
          expect(acknowledgeResolution.isCompleted, isFalse);

          // Model the queue receiving resolved data before the mutation response
          // reaches onConfirm. Drive the screen's real reload while the sheet stays
          // open, rather than replacing the screen or disposing its route.
          await tester
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh();
          await tester.pump();
          expect(find.text('No open disputes.'), findsOneWidget);
          expect(row, findsNothing);
          expect(find.text('Resolve dispute'), findsOneWidget);
          expect(tester.widget<EpButton>(confirm).onTap, isNull);
          expect(adminRoute.isCurrent, isFalse);
          expect(routeCurrentOnReload, [false]);

          acknowledgeResolution.complete();
        }
        await tester.pumpAndSettle();

        expect(find.text('Resolve dispute'), findsNothing);
        expect(confirm, findsNothing);
        expect(row, findsNothing);
        expect(find.text('No open disputes.'), findsOneWidget);
        expect(adminRoute.isCurrent, isTrue);
        // Observing the route when the query starts also catches a refresh moved
        // inside onConfirm, even if the sheet eventually closes after that query.
        expect(routeCurrentOnReload, [
          if (refreshBeforeAcknowledgement) false,
          true,
        ]);
        expect(
          repository.openDisputesCalls,
          refreshBeforeAcknowledgement ? 3 : 2,
        );
        repository.onOpenDisputes = null;
        expect(
          (await repository.disputesForBooking(booking.id)).single.status,
          DisputeStatus.resolved,
        );
        expect((await repository.openDisputes()).items, isEmpty);
        expect(
          (await repository.adminBookings(
            filter: AdminBookingFilter.disputed,
          )).items,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('admin reviews a refund request and issues a partial refund', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth)..platformAdmin = true;
    final booking = await _paidBooking(repository);
    final disputeId = await repository.openDispute(
      bookingId: booking.id,
      side: DisputeSide.organizer,
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
      side: DisputeSide.artist,
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
    final repository = StubRepository(auth: auth)
      ..platformAdmin = true
      ..failOnce('resolveDispute');
    final booking = await _paidBooking(repository);
    final disputeId = await repository.openDispute(
      bookingId: booking.id,
      side: DisputeSide.organizer,
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
      expect(find.text('Resolve dispute'), findsOneWidget);
      expect((await repository.booking(booking.id))!.refundedMinor, 0);
      expect(tester.takeException(), isNull);
    }

    await tester.ensureVisible(amount);
    await tester.enterText(amount, '12.34');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text(genericErrorMessage), findsOneWidget);
    expect(find.byType(InlineFormFeedback), findsOneWidget);
    expect(find.text('Resolve dispute'), findsOneWidget);
    expect(tester.widget<EpButton>(confirm).onTap, isNotNull);
    expect(tester.takeException(), isNull);
    expectNoFieldInCard(tester);

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
          side: DisputeSide.organizer,
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
  });
}
