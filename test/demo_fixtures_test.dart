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

Future<Booking> _acceptPrivateOffer(DemoRepository repo) async {
  final opportunity = (await repo.browseOpportunities(
    mode: OpportunityMode.privateBooking,
  )).items.single.opportunity;
  final applicationId = await repo.applyToOpportunity(
    opportunityId: opportunity.id,
    slotId: opportunity.slots.single.id,
    bandId: 'b1',
    message: 'Ready for the courtyard set.',
  );
  await repo.reviewApplication(
    applicationId: applicationId,
    action: ArtistApplicationReviewAction.shortlisted,
  );
  final sent = await repo.sendOffer(
    applicationId: applicationId,
    grossMinor: opportunity.slots.single.guaranteeMinor,
    cancellationTemplate: CancellationTemplate.standard,
  );
  final offered = (await repo.booking(
    sent.bookingId,
    viewAs: BookingSide.artist,
  ))!;
  expect(offered.privateEvent, isTrue);
  expect(offered.status, BookingStatus.offerSent);
  expect(offered.venue, isNull);
  expect(offered.privateLocation!.area, opportunity.area);
  expect(offered.privateLocation!.addr, isNull);
  expect(offered.privateLocation!.lat, isNull);
  expect(offered.privateLocation!.lng, isNull);
  expect(offered.privateLocation!.notes, isNull);
  await repo.respondToOffer(
    bookingId: sent.bookingId,
    accept: true,
    expectedRevision: sent.revision,
  );
  return (await repo.booking(sent.bookingId, viewAs: BookingSide.artist))!;
}

void main() {
  group('bookings', () {
  test('C: pending reviews stay blind until both sides submit', () async {
    final repo = DemoRepository(auth: FakeAuthService());
    final before = await repo.reviewsForBooking('bk4');
    expect(before.mine, isNull);
    expect(before.theirs, isNull);
    expect(before.canSubmit, isTrue);
    expect(await repo.reviewsForBand('b2'), isEmpty);
    expect(
      (await repo.reviewsForOrganization(
        'org1',
      )).map((review) => review.rating),
      [4],
    );

    final result = await repo.submitReview(
      bookingId: 'bk4',
      rating: 5,
      categories: ['professionalism'],
      text: 'Great show',
    );
    expect(result.visible, isTrue);
    final after = await repo.reviewsForBooking('bk4');
    expect(after.mine!.reviewId, result.reviewId);
    expect(after.mine!.rating, 5);
    expect(after.theirs!.rating, 3);
    expect(after.mine!.visibleAt, after.theirs!.visibleAt);
    expect(after.mine!.visibleAt, isNotNull);
    expect(after.canSubmit, isFalse);
    final organization = (await repo.organization('org1'))!;
    expect(organization.reviewSummary!.count, 2);
    expect(organization.reviewSummary!.mean, 3.5);
    expect(organization.reviewSummary!.completedBookings, 2);
    final band = (await repo.band('b2'))!;
    expect(band.reviewSummary!.count, 1);
    expect(band.reviewSummary!.mean, 5);
    expect(band.reviewSummary!.completedBookings, 1);
    expect(
      (await repo.myOrganizations().first)
          .singleWhere((membership) => membership.organization.id == 'org1')
          .organization
          .reviewSummary,
      same(organization.reviewSummary),
    );
    final bandReviews = await repo.reviewsForBand('b2');
    expect(bandReviews.single.counterpartyName, 'The Foghorn Club');
    expect(bandReviews.single.opportunityTitle, 'Late Night Wrap');
    expect(bandReviews.single.monthLabel, isNotEmpty);
    final organizationReviews = await repo.reviewsForOrganization('org1');
    expect(organizationReviews.map((review) => review.rating), [3, 4]);
    expect(organizationReviews.first.counterpartyName, 'Pigeon Court');
    expect(
      (await repo.reviewsForOrganization('org1', limit: 1)).single.rating,
      3,
    );
    expect(await repo.reviewsForBand('b2', limit: 0), isEmpty);
    await expectLater(
      repo.submitReview(
        bookingId: 'bk4',
        rating: 5,
        categories: [],
        text: 'Again',
      ),
      _stateError('You already reviewed this booking'),
    );
    expect(DemoData.organizations['org1']!.reviewSummary!.count, 1);
  });

  test(
    'D: isolated booking fixtures load with query-specific visibility',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      expect(
        (await repo.organizationBookings('org1')).map((booking) => booking.id),
        ['bk1', 'bk2', 'bk4', 'bk3'],
      );
      expect((await repo.bandBookings('b1')).map((booking) => booking.id), [
        'bk2',
        'bk3',
      ]);
      expect((await repo.bandBookings('b2')).map((booking) => booking.id), [
        'bk1',
        'bk4',
      ]);
      final booking = (await repo.booking('bk2'))!;
      expect(booking.publicGigId, 'demo-gig-bk2');
      expect(booking.publicGigSlug, 'riverside-sessions-live');
      expect(booking.viewerSide, BookingSide.organizer);
      expect(
        booking.venue!.exactAddress,
        DemoData.venuePrivateDetails['v1']!.addr,
      );
      final artistBooking = (await repo.booking(
        'bk2',
        viewAs: BookingSide.artist,
      ))!;
      expect(artistBooking.viewerSide, BookingSide.artist);
      // Confirmed bookings disclose the exact address to both parties.
      expect(artistBooking.venue!.exactAddress, booking.venue!.exactAddress);
      final organizerBooking = (await repo.booking(
        'bk2',
        viewAs: BookingSide.organizer,
      ))!;
      expect(organizerBooking.viewerSide, BookingSide.organizer);
      expect(organizerBooking.venue!.exactAddress, isNotNull);
      // The user does not hold bk1's artist role (band b2).
      expect(
        (await repo.booking('bk1', viewAs: BookingSide.artist))!.viewerSide,
        BookingSide.organizer,
      );
      expect((await repo.organization('org1'))!.reviewSummary!.count, 1);
      expect((await repo.band('b1'))!.reviewSummary!.mean, 5);
      expect(await repo.booking('missing'), isNull);
      expect(await repo.organizationBookings('missing'), isEmpty);
      expect(await repo.bandBookings('missing'), isEmpty);
      expect(await repo.organizationBookings('org1', statuses: []), isEmpty);
      expect(
        (await repo.organizationBookings(
          'org1',
          statuses: [BookingStatus.completed],
        )).map((booking) => booking.id),
        ['bk4', 'bk3'],
      );
      expect((await repo.bandBookings('b2')).first.venue!.exactAddress, isNull);
      await repo.setVenueAddressDisclosure(
        venueId: 'v1',
        disclosure: AddressDisclosure.public,
      );
      expect(
        (await repo.bandBookings('b2')).first.venue!.exactAddress,
        isNotNull,
      );
      expect(DemoData.bookings['bk1']!.venue!.exactAddress, isNull);
      for (final fixture in DemoData.bookings.values) {
        expect(
          DemoData.opportunities.containsKey(fixture.opportunityId),
          isFalse,
        );
        expect(
          DemoData.artistApplications.containsKey(fixture.applicationId),
          isFalse,
        );
        expect(
          DemoData.opportunitySlots.values
              .expand((slots) => slots)
              .map((slot) => slot.id),
          isNot(contains(fixture.slotId)),
        );
        expect(
          DemoData.gigs.any((gig) => gig.id == fixture.publicGigId),
          isFalse,
        );
      }
    },
  );

  test(
    'pending offers honor held sides and hide the address from artists',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      await repo.reviewApplication(
        applicationId: 'app1',
        action: ArtistApplicationReviewAction.shortlisted,
      );
      final sent = await repo.sendOffer(
        applicationId: 'app1',
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.standard,
      );
      final artistBooking = (await repo.booking(
        sent.bookingId,
        viewAs: BookingSide.artist,
      ))!;
      expect(artistBooking.organizationId, 'org1');
      expect(artistBooking.bandId, 'b1');
      expect(artistBooking.viewerSide, BookingSide.artist);
      expect(artistBooking.venue!.exactAddress, isNull);
      final organizerBooking = (await repo.booking(
        sent.bookingId,
        viewAs: BookingSide.organizer,
      ))!;
      expect(organizerBooking.viewerSide, BookingSide.organizer);
      expect(organizerBooking.venue!.exactAddress, isNotNull);
    },
  );
  });

  group('opportunities', () {
    late DemoRepository repository;

    setUp(() {
      repository = DemoRepository(auth: FakeAuthService());
    });

    test(
      'public browsing includes opp1 and hides drafts and invitations',
      () async {
        final page = await repository.browseOpportunities(
          mode: OpportunityMode.publicEvent,
        );

        expect(page.items.map((item) => item.opportunity.id), ['opp1']);
        expect(page.items.single.invited, isFalse);
        expect(page.items.single.myApplicationStatus, isNull);
        expect(page.items.single.opportunity.venue!.name, 'The Foghorn Club');
        expect(page.items.single.opportunity.applicationCount, 2);
        expect(page.continueCursor, isNull);
        expect(page.isDone, isTrue);
      },
    );

    test(
      'management lists drafts first and sorts each partition by start time',
      () async {
        final earlierDraft = await repository.createOpportunity(
          organizationId: 'org1',
          title: 'Earlier Draft',
          venueId: 'v1',
          startsAt: DateTime.now().add(const Duration(days: 10)),
        );
        await repository.createOpportunity(
          organizationId: 'another-organization',
          title: 'Other Organization',
          venueId: 'v1',
          startsAt: DateTime.now(),
        );
        expect(
          (await repository.manageOpportunities(
            'org1',
          )).map((opportunity) => opportunity.id),
          [earlierDraft.opportunityId, 'opp2', 'opp1', 'opp3'],
        );
        expect(await repository.manageOpportunities('missing'), isEmpty);
      },
    );
  });

  group('tickets', () {
    late FakeAuthService auth;
    late DemoRepository repo;

    setUp(() async {
      auth = FakeAuthService();
      await auth.signInDemo();
      repo = DemoRepository(auth: auth);
    });

  test(
    'ticket sales parse refunds and tolerate absent or malformed fields',
    () {
      final sales = TicketSales.fromJson({
        'refundedMinor': 2675,
        'refundedOrgMinor': 2500,
        'truncated': true,
      });
      expect(sales.refundedMinor, 2675);
      expect(sales.refundedOrgMinor, 2500);
      expect(sales.truncated, isTrue);
      for (final json in <Map<String, dynamic>>[
        {},
        {
          'refundedMinor': 'bad',
          'refundedOrgMinor': <String, dynamic>{},
          'truncated': 'true',
        },
      ]) {
        final sales = TicketSales.fromJson(json);
        expect(sales.refundedMinor, 0);
        expect(sales.refundedOrgMinor, 0);
        expect(sales.truncated, isFalse);
      }
    },
  );

  test(
    'organizer door flow supports RSVP tokens with direct gig IDs',
    () async {
      const payload = 'earplug:ticket:v1:demo-g1';
      expect(
        (await repo.organizerCheckIn(gigId: 'g1', payload: payload)).kind,
        TicketDoorKind.unknown,
      );
      await repo.ensureRsvp('g1');
      final ticket = await repo.ticketForGig('g1');
      expect(ticket.payload, payload);
      expect(
        (await repo.organizerCheckIn(gigId: 'g8', payload: payload)).kind,
        TicketDoorKind.wrongEvent,
      );
      final first = await repo.organizerCheckIn(gigId: 'g1', payload: payload);
      expect(first.kind, TicketDoorKind.checkedIn);
      expect(first.source, 'rsvp');
      expect(first.holderName, 'Earplug Fan');
      expect(first.checkedInAt, isNotNull);
      final repeated = await repo.organizerCheckIn(
        gigId: 'g1',
        payload: payload,
      );
      expect(repeated.kind, TicketDoorKind.alreadyUsed);
      expect(repeated.source, 'rsvp');
      final counts = await repo.organizerDoorRoster('g1');
      expect(counts.rsvpTotal, 1);
      expect(counts.rsvpCheckedIn, 1);
      expect(counts.ticketsSold, 0);
      expect(counts.ticketsCheckedIn, 0);
      expect(counts.truncated, isFalse);
    },
  );
  });

  group('private bookings', () {
    late DemoRepository repo;

    setUp(() {
      repo = DemoRepository(auth: FakeAuthService());
    });

  test(
    'private bookings reveal the address only after guarantee payment',
    () async {
      final accepted = await _acceptPrivateOffer(repo);
      expect(accepted.privateEvent, isTrue);
      expect(accepted.status, BookingStatus.awaitingPayment);
      expect(accepted.confirmedAt, isNull);
      expect(accepted.privateLocation!.addr, isNull);
      expect(accepted.privateLocation!.lat, isNull);
      expect(accepted.privateLocation!.lng, isNull);
      expect(accepted.privateLocation!.notes, isNull);
      final bandView = (await repo.bandBookings(
        'b1',
      )).singleWhere((booking) => booking.id == accepted.id);
      expect(bandView.privateLocation!.addr, isNull);
      final hostView = (await repo.organizationBookings('org2')).single;
      final location = (await repo.privateLocationsFor('org2')).single;
      expect(hostView.privateLocation!.addr, location.addr);
      final payment = (await repo.paymentsForBooking(accepted.id)).single;
      expect(payment.amountMinor, greaterThan(0));
      expect(payment.status, PaymentRecordStatus.pending);
      final checkout = await repo.startInstallmentCheckout(payment.id);
      await repo.simulateCheckoutCompleted(checkout.sessionId);
      final confirmed = (await repo.booking(
        accepted.id,
        viewAs: BookingSide.artist,
      ))!;
      expect(confirmed.status, BookingStatus.confirmed);
      expect(confirmed.privateEvent, isTrue);
      expect(confirmed.confirmedAt, isNotNull);
      expect(confirmed.privateLocation!.addr, location.addr);
      expect(confirmed.privateLocation!.lat, location.lat);
      expect(confirmed.privateLocation!.lng, location.lng);
      expect(confirmed.privateLocation!.notes, location.notes);
      expect(confirmed.venue, isNull);
      expect(confirmed.paidMinor, payment.amountMinor);
      expect(
        (await repo.paymentsForBooking(accepted.id)).single.status,
        PaymentRecordStatus.paid,
      );
      expect(
        (await repo.bandBookings('b1'))
            .singleWhere((booking) => booking.id == accepted.id)
            .privateLocation!
            .addr,
        location.addr,
      );
      expect(confirmed.publicGigId, isNull);
      expect(confirmed.publicGigSlug, isNull);
      expect(
        (await repo.feed().first).gigs.where(
          (gig) => gig.opportunityId == accepted.opportunityId,
        ),
        isEmpty,
      );
      final opportunity = (await repo.opportunity(accepted.opportunityId))!;
      expect(opportunity.status, OpportunityStatus.confirmed);
      expect(opportunity.privateEvent, isTrue);
      expect(opportunity.venue, isNull);
      expect(opportunity.slots.single.status, SlotStatus.booked);
      expect(
        (await repo.myApplicationFor(
          opportunityId: opportunity.id,
          bandId: 'b1',
        ))!.status,
        ArtistApplicationStatus.booked,
      );
      // Completion is idempotent, and earlier query payloads stay redacted.
      await repo.simulateCheckoutCompleted(checkout.sessionId);
      expect((await repo.booking(accepted.id))!.paidMinor, payment.amountMinor);
      expect(accepted.privateLocation!.addr, isNull);
    },
  );

  test('private browsing exposes only the area and filters by mode', () async {
    final opportunity = (await repo.browseOpportunities(
      mode: OpportunityMode.privateBooking,
    )).items.single.opportunity;
    expect(opportunity.mode, OpportunityMode.privateBooking);
    expect(opportunity.privateEvent, isTrue);
    expect(
      opportunity.privateLocationId,
      (await repo.privateLocationsFor('org2')).single.id,
    );
    expect(opportunity.venue, isNull);
    expect(opportunity.venueId, isNull);
    expect(opportunity.venueType, VenueType.private);
    expect(opportunity.area, 'Mission District');
    expect(
      (await repo.browseOpportunities()).items.map(
        (item) => item.opportunity.id,
      ),
      isNot(contains(opportunity.id)),
    );
    expect(
      (await repo.browseOpportunities(
        mode: OpportunityMode.privateBooking,
      )).items.map((item) => item.opportunity.id),
      contains(opportunity.id),
    );
    expect(
      (await repo.browseOpportunities(
        mode: OpportunityMode.publicEvent,
      )).items.map((item) => item.opportunity.id),
      ['opp1'],
    );
    expect(
      (await repo.browseOpportunities(mode: OpportunityMode.unknown)).items,
      isEmpty,
    );
  });
  });
}
