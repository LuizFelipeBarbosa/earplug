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

Future<String> _shortlistedApplication(
  DemoRepository repo,
  Opportunity opportunity,
  String slotId,
  String bandId,
) async {
  final applicationId = await repo.applyToOpportunity(
    opportunityId: opportunity.id,
    slotId: slotId,
    bandId: bandId,
    message: 'Ready to play.',
  );
  await repo.reviewApplication(
    applicationId: applicationId,
    action: ArtistApplicationReviewAction.shortlisted,
  );
  return applicationId;
}

Future<Opportunity> _openOpportunity(
  DemoRepository repo, {
  bool optionalSupport = false,
}) async {
  final created = await repo.createOpportunity(
    organizationId: 'org1',
    title: 'Testable Gig',
    venueId: 'v1',
    startsAt: DateTime.now().add(const Duration(days: 30)),
    slots: [
      const SlotInput(
        role: SlotRole.headliner,
        guaranteeMinor: 0,
        required: true,
      ),
      if (optionalSupport)
        const SlotInput(
          role: SlotRole.support,
          guaranteeMinor: 0,
          required: false,
        ),
    ],
  );
  await repo.openOpportunity(
    opportunityId: created.opportunityId,
    expectedRevision: 1,
  );
  return (await repo.opportunity(created.opportunityId))!;
}

void main() {
  test('A: payments gate, fee snapshot, and duplicate pending offer', () async {
    final repo = DemoRepository(auth: FakeAuthService());
    await repo.reviewApplication(
      applicationId: 'app1',
      action: ArtistApplicationReviewAction.shortlisted,
    );
    expect(repo.demoPaymentsEnabled, isFalse);
    await expectLater(
      repo.sendOffer(
        applicationId: 'app1',
        grossMinor: 20000,
        cancellationTemplate: CancellationTemplate.standard,
      ),
      _stateError('Paid offers open once payments are enabled'),
    );
    repo.demoPaymentsEnabled = true;
    final sent = await repo.sendOffer(
      applicationId: 'app1',
      grossMinor: 20000,
      cancellationTemplate: CancellationTemplate.standard,
      termsNotes: 'Bring a backline.',
      message: 'See you there.',
    );
    expect(sent.revision, 1);
    expect(sent.offerId, '${sent.bookingId}-offer-1');
    final booking = (await repo.booking(sent.bookingId))!;
    expect(booking.fee.grossMinor, 20000);
    expect(booking.fee.commissionBps, 1000);
    expect(booking.fee.commissionMinor, 2000);
    expect(booking.fee.artistNetMinor, 18000);
    expect(booking.fee.currency, 'usd');
    expect(booking.termsNotes, 'Bring a backline.');
    expect(booking.currentOffer!.message, 'See you there.');
    expect(
      booking.expiresAt!.difference(booking.organizerAcceptedTermsAt),
      const Duration(hours: 72),
    );
    expect(
      (await repo.myApplicationFor(
        opportunityId: 'opp1',
        bandId: 'b1',
      ))!.status,
      ArtistApplicationStatus.offered,
    );

    final competitor = await repo.applyToOpportunity(
      opportunityId: 'opp1',
      slotId: 'opp1-support',
      bandId: 'b3',
      message: 'x',
    );
    await repo.reviewApplication(
      applicationId: competitor,
      action: ArtistApplicationReviewAction.shortlisted,
    );
    await expectLater(
      repo.sendOffer(
        applicationId: competitor,
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.flexible,
      ),
      _stateError('This slot already has a pending offer'),
    );
    expect(
      DemoData.artistApplications['app1']!.status,
      ArtistApplicationStatus.submitted,
    );
    expect(DemoData.opportunities['opp1']!.applicationCount, 2);
  });

  test(
    'B: free confirmation publishes, cancellation releases and unpublishes',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      final opportunity = await _openOpportunity(repo);
      final slotId = opportunity.slots.single.id;
      final appA = await _shortlistedApplication(
        repo,
        opportunity,
        slotId,
        'b4',
      );
      final appB = await _shortlistedApplication(
        repo,
        opportunity,
        slotId,
        'b5',
      );
      final sent = await repo.sendOffer(
        applicationId: appA,
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.flexible,
      );
      final pending = (await repo.booking(sent.bookingId))!;
      expect(pending.status, BookingStatus.offerSent);
      expect(pending.revision, 1);
      expect(pending.fee.commissionBps, 0);
      expect(pending.fee.commissionMinor, 0);
      expect(pending.fee.artistNetMinor, 0);
      expect(pending.publicGigId, isNull);
      final artistView = (await repo.bandBookings('b4')).single;
      expect(artistView.viewerSide, BookingSide.artist);
      expect(artistView.venue.exactAddress, isNull);
      expect(artistView.counterpartyEmail, isNull);
      final organizerView = (await repo.organizationBookings(
        'org1',
      )).firstWhere((booking) => booking.id == sent.bookingId);
      expect(organizerView.viewerSide, BookingSide.organizer);
      expect(organizerView.venue.exactAddress, isNotNull);

      final accepted = await repo.respondToOffer(
        bookingId: sent.bookingId,
        accept: true,
        expectedRevision: 1,
      );
      expect(accepted, (status: BookingStatus.confirmed, revision: 3));
      final applicants = {
        for (final row in await repo.applicantsFor(opportunity.id))
          row.application.id: row.application,
      };
      expect(applicants[appA]!.status, ArtistApplicationStatus.booked);
      expect(applicants[appB]!.status, ArtistApplicationStatus.declined);
      expect(applicants[appB]!.decidedAt, isNotNull);
      final confirmedOpportunity = (await repo.opportunity(opportunity.id))!;
      expect(confirmedOpportunity.slots.single.status, SlotStatus.booked);
      expect(confirmedOpportunity.slots.single.bandId, 'b4');
      expect(confirmedOpportunity.applicationCount, 0);
      expect(confirmedOpportunity.status, OpportunityStatus.confirmed);
      final confirmed = (await repo.booking(sent.bookingId))!;
      expect(confirmed.currentOffer!.response, OfferResponse.accepted);
      expect(confirmed.artistAcceptedTermsAt, isNotNull);
      expect(confirmed.confirmedAt, isNotNull);
      expect(confirmed.publicGigId, isNotNull);
      final gigId = confirmed.publicGigId!;
      final gig = (await repo.publicGig(gigId).first)!;
      expect(gig.ownerKind, GigOwnerKind.organization);
      expect(gig.opportunityId, opportunity.id);
      expect(gig.lineup, ['b4']);
      expect(gig.performers.single.role, GigPerformerRole.headliner);
      expect(gig.performers.single.name, DemoData.bands['b4']!.name);
      expect(gig.lifecycle, GigLifecycle.published);
      expect(gig.discoveryListingReady, isTrue);
      expect(confirmed.publicGigSlug, gig.slug);
      expect((await repo.publicGig(gig.slug).first)!.id, gigId);
      final liveArtistView = (await repo.bandBookings('b4')).single;
      expect(liveArtistView.venue.exactAddress, isNotNull);
      expect(liveArtistView.counterpartyEmail, 'hello@foghorn.example');
      // A previous payload remains private even after the booking changes.
      expect(artistView.venue.exactAddress, isNull);

      final cancelled = await repo.cancelBooking(
        bookingId: sent.bookingId,
        reason: ' schedule conflict ',
        expectedRevision: 3,
      );
      expect(cancelled, (
        status: BookingStatus.cancelledByOrganizer,
        revision: 4,
      ));
      final released = (await repo.opportunity(opportunity.id))!;
      expect(released.slots.single.status, SlotStatus.open);
      expect(released.slots.single.bandId, isNull);
      expect(released.status, OpportunityStatus.booking);
      final cancelledBooking = (await repo.booking(sent.bookingId))!;
      expect(cancelledBooking.cancelledBy, BookingCancelledBy.organizer);
      expect(cancelledBooking.cancelledAt, isNotNull);
      expect(cancelledBooking.cancelReason, 'schedule conflict');
      expect(cancelledBooking.publicGigId, gigId);
      expect(cancelledBooking.publicGigSlug, gig.slug);
      expect(
        (await repo.myApplicationFor(
          opportunityId: opportunity.id,
          bandId: 'b4',
        ))!.status,
        ArtistApplicationStatus.declined,
      );
      final unpublished = (await repo.publicGig(gigId).first)!;
      expect(unpublished.lifecycle, GigLifecycle.unpublished);
      expect(unpublished.discoveryListingReady, isFalse);
      expect(
        (await repo.feed().first).gigs.map((gig) => gig.id),
        isNot(contains(gigId)),
      );
      expect(await repo.bandBookings('b4'), isEmpty);
      final summary = (await repo.organization('org1'))!.reviewSummary!;
      expect(summary.cancellations, 1);
      expect(summary.completedBookings, 2);
      expect(summary.count, 1);
      expect(summary.mean, 4);
      expect(DemoData.gigs.map((gig) => gig.id), isNot(contains(gigId)));
      expect(DemoData.opportunities.containsKey(opportunity.id), isFalse);
    },
  );

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
      (await repo.myOrganizations().first).single.organization.reviewSummary,
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
        booking.venue.exactAddress,
        DemoData.venuePrivateDetails['v1']!.addr,
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
      expect((await repo.bandBookings('b2')).first.venue.exactAddress, isNull);
      await repo.setVenueAddressDisclosure(
        venueId: 'v1',
        disclosure: AddressDisclosure.public,
      );
      expect(
        (await repo.bandBookings('b2')).first.venue.exactAddress,
        isNotNull,
      );
      expect(DemoData.bookings['bk1']!.venue.exactAddress, isNull);
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
    'withdraw and decline reshortlist, preserve offers, and reject stale writes',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      await expectLater(
        repo.sendOffer(
          applicationId: 'app1',
          grossMinor: 0,
          cancellationTemplate: CancellationTemplate.flexible,
        ),
        _stateError('Shortlist the application'),
      );
      await repo.reviewApplication(
        applicationId: 'app1',
        action: ArtistApplicationReviewAction.shortlisted,
      );
      await expectLater(
        repo.sendOffer(
          applicationId: 'app1',
          grossMinor: -1,
          cancellationTemplate: CancellationTemplate.flexible,
        ),
        _stateError('Gross fee must be a non-negative integer'),
      );
      final first = await repo.sendOffer(
        applicationId: 'app1',
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.flexible,
      );
      await expectLater(
        repo.withdrawOffer(bookingId: first.bookingId, expectedRevision: 0),
        _stateError('Booking changed elsewhere'),
      );
      expect(
        await repo.withdrawOffer(
          bookingId: first.bookingId,
          expectedRevision: 1,
        ),
        2,
      );
      final withdrawn = (await repo.booking(first.bookingId))!;
      expect(withdrawn.status, BookingStatus.withdrawn);
      expect(withdrawn.currentOffer!.response, OfferResponse.withdrawn);
      final application = (await repo.myApplicationFor(
        opportunityId: 'opp1',
        bandId: 'b1',
      ))!;
      expect(application.status, ArtistApplicationStatus.shortlisted);
      expect(application.decidedAt, isNull);
      await expectLater(
        repo.withdrawOffer(bookingId: first.bookingId, expectedRevision: 2),
        _stateError('Booking cannot go from withdrawn to withdrawn'),
      );
      final second = await repo.sendOffer(
        applicationId: 'app1',
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.standard,
      );
      expect(second.bookingId, isNot(first.bookingId));
      await expectLater(
        repo.respondToOffer(
          bookingId: second.bookingId,
          accept: false,
          expectedRevision: 0,
        ),
        _stateError('Booking changed elsewhere'),
      );
      expect(
        await repo.respondToOffer(
          bookingId: second.bookingId,
          accept: false,
          expectedRevision: 1,
        ),
        (status: BookingStatus.declined, revision: 2),
      );
      expect(
        (await repo.booking(second.bookingId))!.currentOffer!.response,
        OfferResponse.declined,
      );
      expect(
        (await repo.myApplicationFor(
          opportunityId: 'opp1',
          bandId: 'b1',
        ))!.status,
        ArtistApplicationStatus.shortlisted,
      );
      await expectLater(
        repo.respondToOffer(
          bookingId: second.bookingId,
          accept: true,
          expectedRevision: 2,
        ),
        _stateError('Only a pending offer can be accepted or declined'),
      );
      expect(
        (await repo.organizationBookings(
          'org1',
          statuses: [BookingStatus.withdrawn],
        )).single.id,
        first.bookingId,
      );
      expect(
        (await repo.opportunity('opp1'))!.slots.last.status,
        SlotStatus.open,
      );
      expect((await repo.opportunity('opp1'))!.applicationCount, 2);
    },
  );

  test(
    'paid acceptance awaits payment and cancels without booking a slot',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      repo.demoPaymentsEnabled = true;
      repo.demoCommissionBps = 1250;
      await repo.reviewApplication(
        applicationId: 'app1',
        action: ArtistApplicationReviewAction.shortlisted,
      );
      final sent = await repo.sendOffer(
        applicationId: 'app1',
        grossMinor: 10004,
        cancellationTemplate: CancellationTemplate.strict,
      );
      expect((await repo.booking(sent.bookingId))!.fee.commissionMinor, 1251);
      expect((await repo.booking(sent.bookingId))!.fee.artistNetMinor, 8753);
      expect(
        await repo.respondToOffer(
          bookingId: sent.bookingId,
          accept: true,
          expectedRevision: 1,
        ),
        (status: BookingStatus.awaitingPayment, revision: 3),
      );
      final accepted = (await repo.booking(sent.bookingId))!;
      expect(accepted.confirmedAt, isNull);
      expect(accepted.publicGigId, isNull);
      expect(accepted.artistAcceptedTermsAt, isNotNull);
      expect(
        (await repo.bandBookings('b1'))
            .firstWhere((booking) => booking.id == sent.bookingId)
            .venue
            .exactAddress,
        isNull,
      );
      await expectLater(
        repo.cancelBooking(
          bookingId: sent.bookingId,
          reason: 'conflict',
          expectedRevision: 1,
        ),
        _stateError('Booking changed elsewhere'),
      );
      await expectLater(
        repo.cancelBooking(
          bookingId: sent.bookingId,
          reason: ' ',
          expectedRevision: 3,
        ),
        _stateError('Cancellation reason is required'),
      );
      await expectLater(
        repo.cancelBooking(
          bookingId: sent.bookingId,
          reason: 'x' * 501,
          expectedRevision: 3,
        ),
        _stateError('Cancellation reason must be at most 500 characters'),
      );
      expect(
        await repo.cancelBooking(
          bookingId: sent.bookingId,
          reason: 'conflict',
          expectedRevision: 3,
        ),
        (status: BookingStatus.cancelledByOrganizer, revision: 4),
      );
      expect(
        (await repo.myApplicationFor(
          opportunityId: 'opp1',
          bandId: 'b1',
        ))!.status,
        ArtistApplicationStatus.shortlisted,
      );
      expect(
        (await repo.opportunity('opp1'))!.slots.last.status,
        SlotStatus.open,
      );
      expect((await repo.opportunity('opp1'))!.applicationCount, 2);
      expect(
        (await repo.organization('org1'))!.reviewSummary!.cancellations,
        0,
      );
    },
  );

  test(
    'optional bookings sync the lineup; replacements reuse the public gig',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      final opportunity = await _openOpportunity(repo, optionalSupport: true);
      final headliner = await _shortlistedApplication(
        repo,
        opportunity,
        opportunity.slots.first.id,
        'b4',
      );
      final support = await _shortlistedApplication(
        repo,
        opportunity,
        opportunity.slots.last.id,
        'b5',
      );
      final headlinerOffer = await repo.sendOffer(
        applicationId: headliner,
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.flexible,
      );
      await repo.respondToOffer(
        bookingId: headlinerOffer.bookingId,
        accept: true,
        expectedRevision: 1,
      );
      final gigId = (await repo.booking(
        headlinerOffer.bookingId,
      ))!.publicGigId!;
      final supportOffer = await repo.sendOffer(
        applicationId: support,
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.flexible,
      );
      await repo.respondToOffer(
        bookingId: supportOffer.bookingId,
        accept: true,
        expectedRevision: 1,
      );
      expect((await repo.booking(supportOffer.bookingId))!.publicGigId, gigId);
      expect((await repo.publicGig(gigId).first)!.lineup, ['b4', 'b5']);
      expect(
        (await repo.publicGig(gigId).first)!.performers.map(
          (performer) => performer.role,
        ),
        [GigPerformerRole.headliner, GigPerformerRole.support],
      );
      await repo.cancelBooking(
        bookingId: supportOffer.bookingId,
        reason: 'unavailable',
        expectedRevision: 3,
      );
      final withoutSupport = (await repo.publicGig(gigId).first)!;
      expect(withoutSupport.lineup, ['b4']);
      expect(withoutSupport.lifecycle, GigLifecycle.published);
      expect(withoutSupport.discoveryListingReady, isTrue);
      expect(
        (await repo.opportunity(opportunity.id))!.status,
        OpportunityStatus.confirmed,
      );
      await repo.cancelBooking(
        bookingId: headlinerOffer.bookingId,
        reason: 'unavailable',
        expectedRevision: 3,
      );
      await repo.reviewApplication(
        applicationId: headliner,
        action: ArtistApplicationReviewAction.shortlisted,
      );
      final replacement = await repo.sendOffer(
        applicationId: headliner,
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.flexible,
      );
      await repo.respondToOffer(
        bookingId: replacement.bookingId,
        accept: true,
        expectedRevision: 1,
      );
      expect((await repo.booking(replacement.bookingId))!.publicGigId, gigId);
      expect(
        (await repo.publicGig(gigId).first)!.lifecycle,
        GigLifecycle.published,
      );
      expect(
        (await repo.feed().first).gigs.where(
          (gig) => gig.opportunityId == opportunity.id,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'review validation rejects incomplete, closed, and invalid submissions',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      await expectLater(
        repo.submitReview(
          bookingId: 'bk2',
          rating: 5,
          categories: [],
          text: '',
        ),
        _stateError('Booking has not been completed yet'),
      );
      await expectLater(
        repo.submitReview(
          bookingId: 'bk3',
          rating: 5,
          categories: [],
          text: '',
        ),
        _stateError('The review window has closed'),
      );
      for (final rating in [0, 6]) {
        await expectLater(
          repo.submitReview(
            bookingId: 'bk4',
            rating: rating,
            categories: [],
            text: '',
          ),
          _stateError('Rating must be an integer between 1 and 5'),
        );
      }
      await expectLater(
        repo.submitReview(
          bookingId: 'bk4',
          rating: 5,
          categories: ['unknown'],
          text: '',
        ),
        _stateError('Unknown review category: unknown'),
      );
      await expectLater(
        repo.submitReview(
          bookingId: 'bk4',
          rating: 5,
          categories: List.filled(7, 'sound'),
          text: '',
        ),
        _stateError('Review must have at most 6 categories'),
      );
      await expectLater(
        repo.submitReview(
          bookingId: 'bk4',
          rating: 5,
          categories: [],
          text: 'x' * 1001,
        ),
        _stateError('Review text must be at most 1000 characters'),
      );
      expect((await repo.reviewsForBooking('bk4')).mine, isNull);
      final categories = ['sound'];
      await repo.submitReview(
        bookingId: 'bk4',
        rating: 5,
        categories: categories,
        text: '  Great  ',
      );
      categories.add('unknown');
      final mine = (await repo.reviewsForBooking('bk4')).mine!;
      expect(mine.text, 'Great');
      expect(mine.categories, ['sound']);
    },
  );

  test(
    'party precedence, artist cancellation, and unauthorized review access',
    () async {
      final repo = DemoRepository(auth: FakeAuthService());
      // The demo user owns org1 and belongs to b1; organizer takes precedence.
      expect((await repo.booking('bk2'))!.viewerSide, BookingSide.organizer);
      await repo.removeOrganizationMember(
        organizationId: 'org1',
        userId: DemoData.demoUserId,
      );
      expect((await repo.booking('bk2'))!.viewerSide, BookingSide.artist);
      expect(
        await repo.cancelBooking(
          bookingId: 'bk2',
          reason: 'artist conflict',
          expectedRevision: 3,
        ),
        (status: BookingStatus.cancelledByArtist, revision: 4),
      );
      final cancelled = (await repo.booking('bk2'))!;
      expect(cancelled.venue.exactAddress, isNull);
      expect(cancelled.counterpartyEmail, isNull);
      expect(cancelled.publicGigId, 'demo-gig-bk2');
      expect((await repo.band('b1'))!.reviewSummary!.cancellations, 1);
      expect(
        (await repo.myBands().first).single.band.reviewSummary!.cancellations,
        1,
      );
      expect(
        (await repo.organization('org1'))!.reviewSummary!.cancellations,
        0,
      );
      await expectLater(
        repo.cancelBooking(bookingId: 'bk1', reason: 'x', expectedRevision: 1),
        _stateError('Not permitted to cancel this booking'),
      );
      await expectLater(
        repo.reviewsForBooking('bk4'),
        _stateError('Only booking parties can review'),
      );
      await expectLater(
        repo.submitReview(
          bookingId: 'bk4',
          rating: 5,
          categories: [],
          text: '',
        ),
        _stateError('Only booking parties can review'),
      );
    },
  );
}
