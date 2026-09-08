import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('booking and dispute loads wait for the restored session token', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _ControlledBookingRepository(auth: auth)
      ..pendingAuth = Completer<void>()
      ..disputesForBookingResult = [_dispute()];
    final app = AppState.demo(
      auth: auth,
      repository: repository,
      initialBookingId: 'booking1',
    );
    final disputeLoad = app.loadDisputes('booking1');

    await tester.pump();
    expect(repository.bookingCalls, 0);
    expect(repository.disputesForBookingCalls, isEmpty);
    repository.pendingAuth!.complete();
    await tester.pumpAndSettle();

    expect(repository.bookingCalls, 1);
    expect(app.bookingById('booking1'), same(repository.bookingResult));
    expect(await disputeLoad, same(repository.disputesForBookingResult));
    expect(repository.disputesForBookingCalls, ['booking1']);
    app.dispose();
  });

  testWidgets('organizer list loads and keeps previous values on error', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final bookings = [_booking()];
    final repository = _ControlledBookingRepository(auth: auth)
      ..organizationResults = bookings;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );

    await harness.app.refreshOrganizationBookings('org1');

    expect(harness.app.organizationBookings, same(bookings));
    expect(harness.app.organizationBookingsStatus, DataStatus.ready);
    expect(repository.organizationRequests, ['org1']);
    expect(repository.requestedStatuses, isNull);
    repository.failLoads = true;

    await harness.app.refreshOrganizationBookings('org1');

    expect(harness.app.organizationBookings, same(bookings));
    expect(harness.app.organizationBookingsStatus, DataStatus.error);
    harness.app.dispose();
  });

  testWidgets('band list refreshes on switchToBand', (tester) async {
    final auth = FakeAuthService();
    final bookings = [_booking(viewerSide: BookingSide.artist)];
    final repository = _ControlledBookingRepository(auth: auth)
      ..bandResults = bookings;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();

    expect(repository.bandRequests, ['b1']);
    expect(harness.app.bandBookings, same(bookings));
    expect(harness.app.bandBookingsStatus, DataStatus.ready);
    // The existing opportunity hook still runs through the mixin chain.
    expect(harness.app.myApplications.map((item) => item.application.id), [
      'app1',
    ]);

    harness.app.resetTo(Screen.bandDash);
    await tester.pumpAndSettle();

    expect(repository.bandRequests, ['b1']);
    harness.app.dispose();
  });

  testWidgets('loadBooking caches and refresh forces a re-fetch', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledBookingRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    final booking = repository.bookingResult;

    final first = await harness.app.loadBooking(booking.id);
    final cached = await harness.app.loadBooking(booking.id);

    expect(first, same(booking));
    expect(cached, same(first));
    expect(repository.bookingCalls, 1);
    final updated = _booking(revision: 2);
    repository.bookingResult = updated;

    final refreshed = await harness.app.loadBooking(booking.id, refresh: true);

    expect(repository.bookingCalls, 2);
    expect(repository.viewAsCalls, [null, null]);
    expect(refreshed, same(updated));
    expect(harness.app.bookingById(booking.id), same(updated));
    harness.app.dispose();
  });

  testWidgets('loadBooking adopts the organizer without navigating', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledBookingRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    expect(harness.app.organizationId, isEmpty);
    final current = harness.app.current;

    final booking = await harness.app.loadBooking(repository.bookingResult.id);

    expect(booking, same(repository.bookingResult));
    expect(harness.app.organizationId, 'org1');
    expect(harness.app.current, same(current));
    expect(harness.app.current.screen, Screen.home);
    expect(harness.app.canGoBack, isFalse);
    harness.app.dispose();
  });

  testWidgets('loadBooking adopts the band without navigating', (tester) async {
    final auth = FakeAuthService();
    final repository = _ControlledBookingRepository(auth: auth)
      ..bookingResult = _booking(viewerSide: BookingSide.artist);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    // Demo memberships preselect a band; model an empty selection on startup.
    harness.app.bandId = '';
    expect(harness.app.bandId, isEmpty);
    final current = harness.app.current;

    final booking = await harness.app.loadBooking(repository.bookingResult.id);

    expect(booking, same(repository.bookingResult));
    expect(harness.app.bandId, 'b1');
    expect(harness.app.current, same(current));
    expect(harness.app.current.screen, Screen.home);
    expect(harness.app.canGoBack, isFalse);
    harness.app.dispose();
  });

  testWidgets('loadBooking keeps an already selected organizer', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledBookingRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToOrganization('org1');
    await tester.pumpAndSettle();
    expect(harness.app.organizationId, 'org1');
    final current = harness.app.current;

    final booking = await harness.app.loadBooking(repository.bookingResult.id);

    expect(booking, same(repository.bookingResult));
    expect(harness.app.organizationId, 'org1');
    expect(harness.app.current, same(current));
    expect(harness.app.current.screen, Screen.orgDash);
    harness.app.dispose();
  });

  testWidgets('shared booking screens follow the cached viewer identity', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledBookingRepository(auth: auth)
      ..bookingResult = _booking(viewerSide: BookingSide.organizer);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToOrganization('org1');
    await tester.pumpAndSettle();
    final bookingId = repository.bookingResult.id;

    harness.app.openBooking(bookingId);
    await tester.pumpAndSettle();
    expect(repository.viewAsCalls, [BookingSide.organizer]);
    expect(harness.app.identity, isA<OrganizerIdentity>());
    harness.app.openReviewCompose(bookingId);
    expect(harness.app.identity, isA<OrganizerIdentity>());

    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    repository.bookingResult = _booking(
      id: 'booking2',
      viewerSide: BookingSide.artist,
    );
    final bandBookingId = repository.bookingResult.id;

    harness.app.openBooking(bandBookingId);
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, bandBookingId);
    await tester.pumpAndSettle();
    expect(repository.viewAsCalls, [BookingSide.organizer, BookingSide.artist]);
    expect(
      harness.app.bookingById(bandBookingId)?.viewerSide,
      BookingSide.artist,
    );
    expect(harness.app.organizationId, 'org1');
    expect(harness.app.identity, isA<BandIdentity>());
    harness.app.openReviewCompose(bandBookingId);
    expect(harness.app.identity, isA<BandIdentity>());
    harness.app.dispose();
  });

  testWidgets(
    'reopening a booking refreshes it and shares the pending detail load',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ControlledBookingRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const SizedBox.shrink(),
      );
      harness.app.openBooking('booking1');
      await tester.pumpAndSettle();
      expect(
        harness.app.bookingById('booking1')!.status,
        BookingStatus.offerSent,
      );
      harness.app.back();

      final updated = _booking(status: BookingStatus.confirmed, revision: 3);
      repository.pendingBooking = Completer<Booking?>();
      harness.app.openBooking('booking1');
      final detail = harness.app.loadBooking('booking1');
      await tester.pump();
      expect(repository.bookingCalls, 2);
      repository.pendingBooking!.complete(updated);
      expect(await detail, same(updated));
      expect(harness.app.bookingById('booking1'), same(updated));
      expect(repository.bookingCalls, 2);

      // A lost membership must also evict an earlier authorized payload.
      repository.pendingBooking = Completer<Booking?>();
      final removed = harness.app.loadBooking('booking1', refresh: true);
      repository.pendingBooking!.complete(null);
      expect(await removed, isNull);
      expect(harness.app.bookingById('booking1'), isNull);
      harness.app.dispose();
    },
  );

  testWidgets('sendOffer refreshes the organizer list', (tester) async {
    final auth = FakeAuthService();
    final bookings = [_booking()];
    final repository = _ControlledBookingRepository(auth: auth)
      ..postOfferBookings = bookings;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToOrganization('org1');
    await tester.pumpAndSettle();
    expect(harness.app.organizationBookings, isEmpty);

    final bookingId = await harness.app.sendOffer(
      applicationId: 'application1',
      grossMinor: 50000,
      cancellationTemplate: CancellationTemplate.standard,
      termsNotes: 'Soundcheck at 18:00.',
      message: 'Please join the lineup.',
    );

    expect(bookingId, bookings.single.id);
    expect(repository.offerRequest, (
      applicationId: 'application1',
      grossMinor: 50000,
      cancellationTemplate: CancellationTemplate.standard,
      termsNotes: 'Soundcheck at 18:00.',
      message: 'Please join the lineup.',
    ));
    expect(repository.organizationRequests, ['org1']);
    expect(harness.app.organizationBookings, same(bookings));
    expect(harness.app.organizationBookingsStatus, DataStatus.ready);
    harness.app.dispose();
  });

  testWidgets('cancelBooking forwards the cached viewer side and refreshes', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final booking = _booking(viewerSide: BookingSide.artist);
    final cancelled = _booking(
      viewerSide: BookingSide.artist,
      status: BookingStatus.cancelledByArtist,
      revision: 2,
    );
    final repository = _ControlledBookingRepository(auth: auth)
      ..bookingResult = booking
      ..bandResults = [booking]
      ..cancelledBooking = cancelled;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    harness.app.openBooking(booking.id);
    await tester.pumpAndSettle();
    expect(repository.viewAsCalls, [BookingSide.artist]);

    final refreshed = await harness.app.cancelBooking(
      booking,
      reason: 'conflict',
    );

    expect(repository.cancelRequest, (
      bookingId: booking.id,
      reason: 'conflict',
      expectedRevision: booking.revision,
      side: BookingSide.artist,
      safety: false,
    ));
    expect(refreshed, same(cancelled));
    expect(harness.app.bookingById(booking.id), same(cancelled));
    expect(
      harness.app.bookingById(booking.id)?.status,
      BookingStatus.cancelledByArtist,
    );
    expect(repository.bookingCalls, 2);
    expect(repository.viewAsCalls, [BookingSide.artist, BookingSide.artist]);
    expect(harness.app.bandBookings, [cancelled]);
    expect(repository.bandRequests, ['b1', 'b1']);
    harness.app.dispose();
  });

  testWidgets('respondToOffer accept updates the cached booking', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final booking = _booking(viewerSide: BookingSide.artist);
    final accepted = _booking(
      viewerSide: BookingSide.artist,
      status: BookingStatus.artistAccepted,
      revision: 2,
    );
    final repository = _ControlledBookingRepository(auth: auth)
      ..bookingResult = booking
      ..bandResults = [booking]
      ..acceptedBooking = accepted;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    harness.app.openBooking(booking.id);
    await tester.pumpAndSettle();
    expect(repository.viewAsCalls, [BookingSide.artist]);

    final refreshed = await harness.app.respondToOffer(
      booking,
      accept: true,
      message: 'Looking forward to it.',
    );

    expect(repository.responseRequest, (
      bookingId: booking.id,
      accept: true,
      expectedRevision: booking.revision,
      message: 'Looking forward to it.',
    ));
    expect(refreshed, same(accepted));
    expect(harness.app.bookingById(booking.id), same(accepted));
    expect(
      harness.app.bookingById(booking.id)?.status,
      BookingStatus.artistAccepted,
    );
    expect(repository.bookingCalls, 2);
    expect(repository.viewAsCalls, [BookingSide.artist, BookingSide.artist]);
    expect(harness.app.bandBookings, [accepted]);
    expect(repository.bandRequests, ['b1', 'b1']);
    expect(repository.organizationRequests, isEmpty);
    harness.app.dispose();
  });

  for (final (viewerSide, disputeSide) in [
    (BookingSide.organizer, DisputeSide.organizer),
    (BookingSide.artist, DisputeSide.artist),
  ]) {
    testWidgets(
      'openDispute forwards arguments and refreshes booking state as ${viewerSide.wireValue}',
      (tester) async {
        final auth = FakeAuthService();
        final booking = _booking(
          viewerSide: viewerSide,
          status: BookingStatus.confirmed,
        );
        final disputed = _booking(
          viewerSide: viewerSide,
          status: BookingStatus.disputed,
          revision: 2,
        );
        final disputes = [_dispute(side: disputeSide)];
        final repository = _ControlledBookingRepository(auth: auth)
          ..bookingResult = booking
          ..organizationResults = [booking]
          ..bandResults = [booking]
          ..disputedBooking = disputed
          ..disputesForBookingResult = disputes;
        final harness = await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          home: const SizedBox.shrink(),
        );
        await harness.auth.signInDemo();
        await tester.pumpAndSettle();
        if (viewerSide == BookingSide.organizer) {
          harness.app.switchToOrganization('org1');
        } else {
          harness.app.switchToBand('b1');
        }
        await tester.pumpAndSettle();
        harness.app.openBooking(booking.id);
        await tester.pumpAndSettle();

        final requestedRefundMinor = viewerSide == BookingSide.organizer
            ? 2500
            : null;
        final refreshed = await harness.app.openDispute(
          booking,
          category: DisputeCategory.lateOrShortSet,
          text: 'Only half the agreed set was played.',
          requestedRefundMinor: requestedRefundMinor,
        );

        expect(repository.openDisputeRequest, (
          bookingId: booking.id,
          side: disputeSide,
          category: DisputeCategory.lateOrShortSet,
          text: 'Only half the agreed set was played.',
          requestedRefundMinor: requestedRefundMinor,
        ));
        expect(repository.disputesForBookingCalls, [booking.id]);
        expect(harness.app.disputesFor(booking.id), same(disputes));
        expect(refreshed, same(disputed));
        expect(harness.app.bookingById(booking.id), same(disputed));
        expect(
          harness.app.bookingById(booking.id)!.status,
          BookingStatus.disputed,
        );
        expect(repository.bookingCalls, 2);
        expect(repository.viewAsCalls, [viewerSide, viewerSide]);
        if (viewerSide == BookingSide.organizer) {
          expect(harness.app.organizationBookings, [disputed]);
          expect(repository.organizationRequests, ['org1']);
          expect(repository.bandRequests, ['b1']);
        } else {
          expect(harness.app.bandBookings, [disputed]);
          expect(repository.bandRequests, ['b1', 'b1']);
          expect(repository.organizationRequests, isEmpty);
        }
        harness.app.dispose();
      },
    );
  }

  testWidgets('loadDisputes caches per booking and retains values on error', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final disputes = [_dispute()];
    final repository = _ControlledBookingRepository(auth: auth)
      ..disputesForBookingResult = disputes;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    expect(harness.app.disputesFor('booking1'), isEmpty);

    final loaded = await harness.app.loadDisputes('booking1');

    expect(loaded, same(disputes));
    expect(harness.app.disputesFor('booking1'), same(disputes));
    expect(harness.app.disputesFor('booking2'), isEmpty);
    repository.failLoads = true;

    expect(await harness.app.loadDisputes('booking1'), same(disputes));
    expect(harness.app.disputesFor('booking1'), same(disputes));
    expect(await harness.app.loadDisputes('booking2'), isEmpty);
    expect(repository.disputesForBookingCalls, [
      'booking1',
      'booking1',
      'booking2',
    ]);
    harness.app.dispose();
  });

  testWidgets('admin dispute actions forward their arguments', (tester) async {
    final auth = FakeAuthService();
    final repository = _ControlledBookingRepository(auth: auth)
      ..platformAdmin = true;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    await harness.app.startDisputeReview('dispute1');
    await harness.app.resolveDispute(
      'dispute1',
      resolution: DisputeResolution.refundedPartial,
      refundMinor: 2500,
      adminNote: 'note',
    );

    expect(repository.startDisputeReviewCalls, ['dispute1']);
    expect(repository.resolveDisputeRequest, (
      disputeId: 'dispute1',
      resolution: DisputeResolution.refundedPartial,
      refundMinor: 2500,
      adminNote: 'note',
    ));
    harness.app.dispose();
  });

  testWidgets('admin dispute and booking routes use the admin identity', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledBookingRepository(auth: auth)
      ..platformAdmin = true;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    harness.app.go(Screen.adminDisputes);
    expect(harness.app.current.screen, Screen.adminDisputes);
    expect(harness.app.identity, isA<AdminIdentity>());

    harness.app.go(Screen.adminBookings);
    expect(harness.app.current.screen, Screen.adminBookings);
    expect(harness.app.identity, isA<AdminIdentity>());
    harness.app.dispose();
  });

  testWidgets('sign-out clears booking state', (tester) async {
    final auth = FakeAuthService();
    final booking = _booking();
    final repository = _ControlledBookingRepository(auth: auth)
      ..bookingResult = booking
      ..organizationResults = [booking]
      ..bandResults = [_booking(viewerSide: BookingSide.artist)]
      ..disputesForBookingResult = [_dispute()];
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    await harness.app.refreshOrganizationBookings('org1');
    await harness.app.loadBooking(booking.id, viewAs: BookingSide.artist);
    await harness.app.loadDisputes(booking.id);
    expect(harness.app.organizationBookings, isNotEmpty);
    expect(harness.app.bandBookings, isNotEmpty);
    expect(harness.app.bookingById(booking.id), same(booking));
    expect(harness.app.disputesFor(booking.id), isNotEmpty);

    await harness.app.signOut();

    expect(harness.app.organizationBookings, isEmpty);
    expect(harness.app.bandBookings, isEmpty);
    expect(harness.app.bookingById(booking.id), isNull);
    expect(harness.app.disputesFor(booking.id), isEmpty);
    expect(harness.app.organizationBookingsStatus, DataStatus.connecting);
    expect(harness.app.bandBookingsStatus, DataStatus.connecting);
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    await harness.app.loadBooking(booking.id);
    expect(repository.viewAsCalls, [BookingSide.artist, null]);
    harness.app.dispose();
  });

  testWidgets('late booking loads cannot restore signed-out state', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledBookingRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    final booking = repository.bookingResult;
    final pendingOrganization = Completer<List<Booking>>();
    final pendingBand = Completer<List<Booking>>();
    final pendingBooking = Completer<Booking?>();
    final pendingDisputes = Completer<List<Dispute>>();
    repository.pendingOrganization = pendingOrganization;
    repository.pendingBand = pendingBand;
    repository.pendingBooking = pendingBooking;
    repository.pendingDisputes = pendingDisputes;
    final organizationLoad = harness.app.refreshOrganizationBookings('org1');
    final bandLoad = harness.app.refreshBandBookings();
    final detailLoad = harness.app.loadBooking(booking.id);
    final disputeLoad = harness.app.loadDisputes(booking.id);
    await tester.pump();
    expect(repository.disputesForBookingCalls, [booking.id]);

    await harness.app.signOut();
    pendingOrganization.complete([booking]);
    pendingBand.complete([booking]);
    pendingBooking.complete(booking);
    pendingDisputes.complete([_dispute()]);
    await organizationLoad;
    await bandLoad;

    expect(await detailLoad, isNull);
    expect(await disputeLoad, isEmpty);
    expect(harness.app.organizationBookings, isEmpty);
    expect(harness.app.bandBookings, isEmpty);
    expect(harness.app.bookingById(booking.id), isNull);
    expect(harness.app.disputesFor(booking.id), isEmpty);
    expect(harness.app.organizationBookingsStatus, DataStatus.connecting);
    expect(harness.app.bandBookingsStatus, DataStatus.connecting);
    harness.app.dispose();
  });
}

Booking _booking({
  String id = 'booking1',
  BookingSide viewerSide = BookingSide.organizer,
  BookingStatus status = BookingStatus.offerSent,
  int revision = 1,
}) => Booking(
  id: id,
  opportunityId: 'opportunity1',
  opportunityTitle: 'Friday Night Live',
  opportunitySlug: 'friday-night-live',
  slotId: 'slot1',
  slotRole: SlotRole.headliner,
  slotRequired: true,
  organizationId: 'org1',
  organizationName: 'Test Organizer',
  bandId: 'b1',
  bandName: 'Test Band',
  bandSlug: 'test-band',
  applicationId: 'application1',
  status: status,
  revision: revision,
  startsAt: DateTime(2026, 10, 2, 20),
  fee: const FeeBreakdown(
    grossMinor: 50000,
    commissionBps: 1000,
    commissionMinor: 5000,
    artistNetMinor: 45000,
    currency: 'USD',
  ),
  cancellationTemplate: CancellationTemplate.standard,
  organizerAcceptedTermsAt: DateTime(2026, 9, 1),
  venue: const BookingVenue(id: 'venue1', name: 'Test Venue'),
  viewerSide: viewerSide,
);

Dispute _dispute({DisputeSide side = DisputeSide.organizer}) => Dispute(
  disputeId: 'dispute1',
  bookingId: 'booking1',
  side: side,
  category: DisputeCategory.lateOrShortSet,
  text: 'Only half the agreed set was played.',
  requestedRefundMinor: side == DisputeSide.organizer ? 2500 : null,
  status: DisputeStatus.open,
  createdAt: DateTime(2026, 10, 3),
);

class _ControlledBookingRepository extends DemoRepository {
  _ControlledBookingRepository({required super.auth});

  bool failLoads = false;
  int bookingCalls = 0;
  final viewAsCalls = <BookingSide?>[];
  final organizationRequests = <String>[];
  final bandRequests = <String>[];
  List<BookingStatus>? requestedStatuses;
  List<Booking> organizationResults = const [];
  List<Booking> bandResults = const [];
  List<Booking> postOfferBookings = const [];
  Booking bookingResult = _booking();
  Booking? acceptedBooking;
  Booking? cancelledBooking;
  Booking? disputedBooking;
  List<Dispute> disputesForBookingResult = const [];
  final disputesForBookingCalls = <String>[];
  final startDisputeReviewCalls = <String>[];
  Completer<void>? pendingAuth;
  Completer<List<Booking>>? pendingOrganization;
  Completer<List<Booking>>? pendingBand;
  Completer<Booking?>? pendingBooking;
  Completer<List<Dispute>>? pendingDisputes;
  ({
    String applicationId,
    int grossMinor,
    CancellationTemplate cancellationTemplate,
    String? termsNotes,
    String? message,
  })?
  offerRequest;
  ({String bookingId, bool accept, int expectedRevision, String? message})?
  responseRequest;
  ({
    String bookingId,
    String reason,
    int expectedRevision,
    BookingSide? side,
    bool? safety,
  })?
  cancelRequest;
  ({
    String bookingId,
    DisputeSide side,
    DisputeCategory category,
    String text,
    int? requestedRefundMinor,
  })?
  openDisputeRequest;
  ({
    String disputeId,
    DisputeResolution resolution,
    int? refundMinor,
    String? adminNote,
  })?
  resolveDisputeRequest;

  @override
  Future<void> refreshAuth() => pendingAuth?.future ?? super.refreshAuth();

  @override
  Future<List<Booking>> organizationBookings(
    String organizationId, {
    List<BookingStatus>? statuses,
  }) {
    organizationRequests.add(organizationId);
    requestedStatuses = statuses;
    if (failLoads) throw StateError('organizationBookings failed');
    return pendingOrganization?.future ?? Future.value(organizationResults);
  }

  @override
  Future<List<Booking>> bandBookings(String bandId) {
    bandRequests.add(bandId);
    if (failLoads) throw StateError('bandBookings failed');
    return pendingBand?.future ?? Future.value(bandResults);
  }

  @override
  Future<Booking?> booking(String bookingId, {BookingSide? viewAs}) {
    bookingCalls++;
    viewAsCalls.add(viewAs);
    if (failLoads) throw StateError('booking failed');
    return pendingBooking?.future ?? Future.value(bookingResult);
  }

  @override
  Future<({String bookingId, String offerId, int revision})> sendOffer({
    required String applicationId,
    required int grossMinor,
    required CancellationTemplate cancellationTemplate,
    List<OfferInstallmentInput>? installments,
    String? termsNotes,
    String? message,
  }) async {
    offerRequest = (
      applicationId: applicationId,
      grossMinor: grossMinor,
      cancellationTemplate: cancellationTemplate,
      termsNotes: termsNotes,
      message: message,
    );
    organizationResults = postOfferBookings;
    return (
      bookingId: postOfferBookings.single.id,
      offerId: 'offer1',
      revision: postOfferBookings.single.revision,
    );
  }

  @override
  Future<({BookingStatus status, int revision})> respondToOffer({
    required String bookingId,
    required bool accept,
    required int expectedRevision,
    String? message,
  }) async {
    responseRequest = (
      bookingId: bookingId,
      accept: accept,
      expectedRevision: expectedRevision,
      message: message,
    );
    final accepted = acceptedBooking!;
    bookingResult = accepted;
    bandResults = [accepted];
    return (status: accepted.status, revision: accepted.revision);
  }

  @override
  Future<({BookingStatus status, int revision})> cancelBooking({
    required String bookingId,
    required String reason,
    required int expectedRevision,
    BookingSide? side,
    bool? safety,
  }) async {
    cancelRequest = (
      bookingId: bookingId,
      reason: reason,
      expectedRevision: expectedRevision,
      side: side,
      safety: safety,
    );
    final cancelled = cancelledBooking!;
    bookingResult = cancelled;
    bandResults = [cancelled];
    return (status: cancelled.status, revision: cancelled.revision);
  }

  @override
  Future<String> openDispute({
    required String bookingId,
    required DisputeSide side,
    required DisputeCategory category,
    required String text,
    int? requestedRefundMinor,
  }) async {
    openDisputeRequest = (
      bookingId: bookingId,
      side: side,
      category: category,
      text: text,
      requestedRefundMinor: requestedRefundMinor,
    );
    final disputed = disputedBooking!;
    bookingResult = disputed;
    organizationResults = [disputed];
    bandResults = [disputed];
    return 'dispute1';
  }

  @override
  Future<List<Dispute>> disputesForBooking(String bookingId) {
    disputesForBookingCalls.add(bookingId);
    if (failLoads) throw StateError('disputesForBooking failed');
    return pendingDisputes?.future ?? Future.value(disputesForBookingResult);
  }

  @override
  Future<void> startDisputeReview(String disputeId) async {
    startDisputeReviewCalls.add(disputeId);
  }

  @override
  Future<void> resolveDispute(
    String disputeId, {
    required DisputeResolution resolution,
    int? refundMinor,
    String? adminNote,
  }) async {
    resolveDisputeRequest = (
      disputeId: disputeId,
      resolution: resolution,
      refundMinor: refundMinor,
      adminNote: adminNote,
    );
  }
}
