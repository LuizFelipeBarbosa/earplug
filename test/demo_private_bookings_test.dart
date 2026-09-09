import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late DemoRepository repo;

  setUp(() {
    repo = DemoRepository(auth: FakeAuthService());
  });

  test('the demo private host location is available', () async {
    final host = (await repo.myOrganizations().first).singleWhere(
      (membership) => membership.organization.id == 'org2',
    );
    expect(host.organization.name, 'Jordan (host)');
    expect(host.organization.orgType, OrganizationType.privateHost);
    expect(host.role, OrganizationRole.owner);
    final location = (await repo.privateLocationsFor('org2')).single;
    expect(location.organizationId, 'org2');
    expect(location.addr, isNotEmpty);
    expect(location.lat, isNonZero);
    expect(location.lng, isNonZero);
    expect(await repo.privateLocationsFor('org1'), isEmpty);
  });

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

  test('private offers reject zero guarantees', () async {
    final opportunity = (await repo.opportunity('opp-private'))!;
    final applicationId = await repo.applyToOpportunity(
      opportunityId: opportunity.id,
      slotId: opportunity.slots.single.id,
      bandId: 'b1',
      message: 'Ready.',
    );
    await repo.reviewApplication(
      applicationId: applicationId,
      action: ArtistApplicationReviewAction.shortlisted,
    );
    await expectLater(
      repo.sendOffer(
        applicationId: applicationId,
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.standard,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('positive guarantee'),
        ),
      ),
    );
    expect(await repo.organizationBookings('org2'), isEmpty);
  });

  test(
    'safety reports are scoped, paginated, and resolved by admins',
    () async {
      final booking = await _acceptPrivateOffer(repo);
      final reportId = await repo.reportSafety(
        bookingId: booking.id,
        category: SafetyCategory.safety,
        text: '  The exit was blocked.  ',
      );
      final report = (await repo.mySafetyReports(booking.id)).single;
      expect(report.reportId, reportId);
      expect(report.bookingId, booking.id);
      expect(report.category, SafetyCategory.safety);
      expect(report.text, 'The exit was blocked.');
      expect(report.status, 'open');
      expect(report.reporterUserId, DemoData.demoUserId);
      expect(await repo.mySafetyReports('bk2'), isEmpty);
      await expectLater(repo.openSafetyReports(), throwsStateError);
      await expectLater(repo.resolveSafetyReport(reportId), throwsStateError);
      await expectLater(
        repo.safetyReportsForBookingAdmin(booking.id),
        throwsStateError,
      );
      await repo.reportSafety(
        bookingId: 'bk2',
        category: SafetyCategory.other,
        text: 'Another concern.',
      );
      repo.platformAdmin = true;
      expect(
        (await repo.safetyReportsForBookingAdmin(booking.id)).single.reportId,
        reportId,
      );
      final first = await repo.openSafetyReports(numItems: 1);
      expect(first.items, hasLength(1));
      expect(first.isDone, isFalse);
      final second = await repo.openSafetyReports(
        numItems: 1,
        cursor: first.continueCursor,
      );
      expect(second.isDone, isTrue);
      final rows = [...first.items, ...second.items];
      expect(rows.map((row) => row.reportId).toSet(), hasLength(2));
      final row = rows.singleWhere((row) => row.reportId == reportId);
      expect(row.bookingTitle, booking.opportunityTitle);
      expect(row.bandName, booking.bandName);
      expect(row.reporterSide, BookingSide.organizer);
      await repo.resolveSafetyReport(
        reportId,
        adminNote: 'Exit access restored.',
      );
      expect(
        (await repo.openSafetyReports()).items.map((row) => row.reportId),
        isNot(contains(reportId)),
      );
      final resolved = (await repo.mySafetyReports(booking.id)).single;
      expect(resolved.status, 'resolved');
      expect(resolved.resolvedAt, isNotNull);
      expect(resolved.adminNote, 'Exit access restored.');
      expect(
        await DemoRepository(auth: FakeAuthService()).mySafetyReports('bk2'),
        isEmpty,
      );
    },
  );

  test(
    'safety cancellation records its kind and hides private details again',
    () async {
      final booking = await _acceptPrivateOffer(repo);
      final payment = (await repo.paymentsForBooking(booking.id)).single;
      final checkout = await repo.startInstallmentCheckout(payment.id);
      await repo.simulateCheckoutCompleted(checkout.sessionId);
      final confirmed = (await repo.booking(booking.id))!;
      await repo.cancelBooking(
        bookingId: booking.id,
        reason: 'Unsafe conditions at the location',
        expectedRevision: confirmed.revision,
        side: BookingSide.artist,
        safety: true,
      );
      final cancelled = (await repo.booking(
        booking.id,
        viewAs: BookingSide.artist,
      ))!;
      expect(cancelled.cancellationKind, CancellationKind.safety);
      expect(cancelled.status, BookingStatus.cancelledByArtist);
      expect(cancelled.privateEvent, isTrue);
      expect(cancelled.privateLocation!.addr, isNull);
      expect(cancelled.privateLocation!.lat, isNull);
      expect(cancelled.privateLocation!.lng, isNull);
      expect(cancelled.privateLocation!.notes, isNull);
    },
  );

  test(
    'private location CRUD and optional opportunity locations are isolated',
    () async {
      final id = await repo.createPrivateLocation(
        organizationId: 'org2',
        label: 'Garden',
        addr: '1 Demo Road',
        city: 'Oakland',
        area: 'Temescal',
        lat: 37.8,
        lng: -122.2,
      );
      final original = (await repo.privateLocationsFor(
        'org2',
      )).singleWhere((location) => location.id == id);
      await repo.updatePrivateLocation(
        id,
        label: 'Back garden',
        notes: 'Gate code on arrival',
        lat: 37.9,
      );
      final updated = (await repo.privateLocationsFor(
        'org2',
      )).singleWhere((location) => location.id == id);
      expect(updated.label, 'Back garden');
      expect(updated.addr, original.addr);
      expect(updated.createdAt, original.createdAt);
      expect(updated.lat, 37.9);
      expect(updated.notes, 'Gate code on arrival');
      final created = await repo.createOpportunity(
        organizationId: 'org2',
        title: 'Location to be decided',
        mode: OpportunityMode.privateBooking,
        startsAt: DateTime.now().add(const Duration(days: 30)),
      );
      final draft = (await repo.opportunity(created.opportunityId))!;
      expect(draft.privateEvent, isTrue);
      expect(draft.privateLocationId, isNull);
      expect(draft.venue, isNull);
      await repo.updateOpportunity(
        opportunityId: draft.id,
        expectedRevision: draft.revision,
        privateLocationId: id,
      );
      final linked = (await repo.opportunity(draft.id))!;
      expect(linked.privateLocationId, id);
      expect(linked.area, updated.area);
      expect(linked.venue, isNull);
      await expectLater(repo.removePrivateLocation(id), throwsStateError);
      await repo.deleteOpportunityDraft(draft.id);
      await repo.removePrivateLocation(id);
      expect(
        (await repo.privateLocationsFor('org2')).map((location) => location.id),
        isNot(contains(id)),
      );
      expect(
        await DemoRepository(
          auth: FakeAuthService(),
        ).privateLocationsFor('org2'),
        hasLength(1),
      );
    },
  );

  test(
    'host application drafts preserve fields through submission and review',
    () async {
      final saved = await repo.saveOrganizationApplicationDraft(
        orgName: 'Jordan',
        orgType: OrganizationType.privateHost,
        contactName: 'Jordan',
        businessEmail: 'jordan@example.com',
        kind: ApplicationKind.host,
        hostDisplayName: 'Jordan (host)',
        hostPhone: '415-555-0100',
        hostArea: 'Mission',
        hostAgreementAccepted: true,
      );
      final draft = (await repo.organizationApplication(saved.applicationId))!;
      expect(draft.kind, ApplicationKind.host);
      expect(draft.hostAgreementAcceptedAt, isNotNull);
      final edited = await repo.saveOrganizationApplicationDraft(
        applicationId: saved.applicationId,
        expectedRevision: saved.revision,
        orgName: 'Jordan',
        orgType: OrganizationType.privateHost,
        contactName: 'Jordan',
        businessEmail: 'jordan@example.com',
      );
      await repo.submitOrganizationApplication(
        applicationId: saved.applicationId,
        expectedRevision: edited.revision,
      );
      final row = (await repo.applicationsForReview(
        kind: ApplicationKind.host,
      )).items.single;
      expect(row.kind, ApplicationKind.host);
      expect(row.application.hostDisplayName, 'Jordan (host)');
      expect(row.application.hostPhone, '415-555-0100');
      expect(row.application.hostArea, 'Mission');
      expect(
        row.application.hostAgreementAcceptedAt,
        draft.hostAgreementAcceptedAt,
      );
      expect(
        (await repo.applicationsForReview(
          kind: ApplicationKind.organization,
        )).items.map((row) => row.application.id),
        isNot(contains(saved.applicationId)),
      );
      expect((await repo.adminOverview()).hostApplications.submitted, 1);
      repo.platformAdmin = true;
      await repo.decideOrganizationApplication(
        applicationId: saved.applicationId,
        decision: ApplicationDecision.underReview,
      );
      expect((await repo.adminOverview()).hostApplications.underReview, 1);
      expect((await repo.adminOverview()).hostApplications.submitted, 0);
    },
  );
}
