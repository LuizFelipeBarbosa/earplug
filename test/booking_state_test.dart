import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
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
    expect(refreshed, same(updated));
    expect(harness.app.bookingById(booking.id), same(updated));
    harness.app.dispose();
  });

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
    await harness.app.loadBooking(booking.id);

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
    expect(harness.app.bandBookings, [accepted]);
    expect(repository.bandRequests, ['b1', 'b1']);
    expect(repository.organizationRequests, isEmpty);
    harness.app.dispose();
  });

  testWidgets('sign-out clears booking state', (tester) async {
    final auth = FakeAuthService();
    final booking = _booking();
    final EarplugRepository repository =
        _ControlledBookingRepository(auth: auth)
          ..bookingResult = booking
          ..organizationResults = [booking]
          ..bandResults = [_booking(viewerSide: BookingSide.artist)];
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
    await harness.app.loadBooking(booking.id);
    expect(harness.app.organizationBookings, isNotEmpty);
    expect(harness.app.bandBookings, isNotEmpty);
    expect(harness.app.bookingById(booking.id), same(booking));

    await harness.app.signOut();

    expect(harness.app.organizationBookings, isEmpty);
    expect(harness.app.bandBookings, isEmpty);
    expect(harness.app.bookingById(booking.id), isNull);
    expect(harness.app.organizationBookingsStatus, DataStatus.connecting);
    expect(harness.app.bandBookingsStatus, DataStatus.connecting);
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
    repository.pendingOrganization = pendingOrganization;
    repository.pendingBand = pendingBand;
    repository.pendingBooking = pendingBooking;
    final organizationLoad = harness.app.refreshOrganizationBookings('org1');
    final bandLoad = harness.app.refreshBandBookings();
    final detailLoad = harness.app.loadBooking(booking.id);

    await harness.app.signOut();
    pendingOrganization.complete([booking]);
    pendingBand.complete([booking]);
    pendingBooking.complete(booking);
    await organizationLoad;
    await bandLoad;

    expect(await detailLoad, isNull);
    expect(harness.app.organizationBookings, isEmpty);
    expect(harness.app.bandBookings, isEmpty);
    expect(harness.app.bookingById(booking.id), isNull);
    expect(harness.app.organizationBookingsStatus, DataStatus.connecting);
    expect(harness.app.bandBookingsStatus, DataStatus.connecting);
    harness.app.dispose();
  });
}

Booking _booking({
  BookingSide viewerSide = BookingSide.organizer,
  BookingStatus status = BookingStatus.offerSent,
  int revision = 1,
}) => Booking(
  id: 'booking1',
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

class _ControlledBookingRepository extends DemoRepository {
  _ControlledBookingRepository({required super.auth});

  bool failLoads = false;
  int bookingCalls = 0;
  final organizationRequests = <String>[];
  final bandRequests = <String>[];
  List<BookingStatus>? requestedStatuses;
  List<Booking> organizationResults = const [];
  List<Booking> bandResults = const [];
  List<Booking> postOfferBookings = const [];
  Booking bookingResult = _booking();
  Booking? acceptedBooking;
  Completer<List<Booking>>? pendingOrganization;
  Completer<List<Booking>>? pendingBand;
  Completer<Booking?>? pendingBooking;
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
  Future<Booking?> booking(String bookingId) {
    bookingCalls++;
    if (failLoads) throw StateError('booking failed');
    return pendingBooking?.future ?? Future.value(bookingResult);
  }

  @override
  Future<({String bookingId, String offerId, int revision})> sendOffer({
    required String applicationId,
    required int grossMinor,
    required CancellationTemplate cancellationTemplate,
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
}
