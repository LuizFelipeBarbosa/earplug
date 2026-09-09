import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoRepository venue consents', () {
    test('organizer reads surface venue consent status', () async {
      final repository = DemoRepository(auth: FakeAuthService());
      final opportunity = (await repository.opportunity('opp-promoter'))!;
      expect(opportunity.venueConsentStatus, VenueConsentStatus.pending);

      final managed = await repository.manageOpportunities('org3');
      expect(
        managed
            .singleWhere((opportunity) => opportunity.id == 'opp-promoter')
            .venueConsentStatus,
        VenueConsentStatus.pending,
      );
      expect(
        (await repository.opportunity('opp1'))!.venueConsentStatus,
        isNull,
      );
    });

    test(
      'dashboard counts pending consents for the venue organization',
      () async {
        final repository = DemoRepository(auth: FakeAuthService());
        final venueDashboard = await repository.organizationDashboard('org1');
        expect(venueDashboard.pendingVenueConsents, 1);

        final requesterDashboard = await repository.organizationDashboard(
          'org3',
        );
        expect(requesterDashboard.pendingVenueConsents, 0);
      },
    );

    test(
      'venue approval unlocks opening and owned venues need no consent',
      () async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final repository = DemoRepository(auth: auth);
        final promoter = (await repository.myOrganizations().first).singleWhere(
          (membership) => membership.organization.id == 'org3',
        );
        expect(promoter.role, OrganizationRole.owner);
        expect(promoter.organization.orgType, OrganizationType.promoter);
        final consent = (await repository.venueConsentForOpportunity(
          'opp-promoter',
        ))!;
        expect(consent.id, 'consent-1');
        expect(consent.status, VenueConsentStatus.pending);
        await expectLater(
          repository.requestVenueConsent(opportunityId: 'opp-promoter'),
          throwsStateError,
        );
        await expectLater(
          repository.openOpportunity(
            opportunityId: 'opp-promoter',
            expectedRevision: 1,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'The venue has not approved this event yet',
            ),
          ),
        );
        await repository.decideVenueConsent(
          consentId: consent.id,
          granted: true,
          note: '  Welcome aboard!  ',
        );
        final granted = (await repository.venueConsentForOpportunity(
          'opp-promoter',
        ))!;
        expect(granted.status, VenueConsentStatus.granted);
        expect(granted.note, 'Welcome aboard!');
        expect(granted.createdAt, consent.createdAt);
        expect(granted.decidedAt, isNotNull);
        await expectLater(
          repository.withdrawVenueConsent(consent.id),
          throwsStateError,
        );
        await expectLater(
          repository.decideVenueConsent(consentId: consent.id, granted: false),
          throwsStateError,
        );
        await repository.openOpportunity(
          opportunityId: 'opp-promoter',
          expectedRevision: 1,
        );
        expect(
          (await repository.opportunity('opp-promoter'))!.status,
          OpportunityStatus.open,
        );
        await expectLater(
          repository.requestVenueConsent(opportunityId: 'opp2'),
          throwsStateError,
        );
        await repository.openOpportunity(
          opportunityId: 'opp2',
          expectedRevision: 1,
        );
        expect(
          (await repository.opportunity('opp2'))!.status,
          OpportunityStatus.open,
        );
        expect(await repository.venueConsentForOpportunity('opp2'), isNull);
        expect(
          (await DemoRepository(
            auth: FakeAuthService(),
          ).venueConsentForOpportunity('opp-promoter'))!.status,
          VenueConsentStatus.pending,
        );
      },
    );

    test(
      'revoking approval cancels an open event and declines applications',
      () async {
        final repository = DemoRepository(auth: FakeAuthService());
        await expectLater(
          repository.revokeVenueConsent('consent-1'),
          throwsStateError,
        );
        await repository.decideVenueConsent(
          consentId: 'consent-1',
          granted: true,
          note: 'Approved',
        );
        await repository.openOpportunity(
          opportunityId: 'opp-promoter',
          expectedRevision: 1,
        );
        await repository.applyToOpportunity(
          opportunityId: 'opp-promoter',
          slotId: 'opp-promoter-headliner',
          bandId: 'b1',
          message: 'Ready to play.',
        );
        final before = (await repository.opportunity('opp-promoter'))!;
        await expectLater(
          repository.revokeVenueConsent('consent-1', note: 'x' * 1001),
          throwsStateError,
        );
        await repository.revokeVenueConsent('consent-1', note: '  ');
        final revoked = (await repository.venueConsentForOpportunity(
          'opp-promoter',
        ))!;
        expect(revoked.status, VenueConsentStatus.revoked);
        expect(revoked.note, isNull);
        expect(revoked.decidedAt, isNotNull);
        final cancelled = (await repository.opportunity('opp-promoter'))!;
        expect(cancelled.status, OpportunityStatus.cancelled);
        expect(cancelled.applicationCount, 0);
        expect(cancelled.revision, before.revision + 1);
        expect(cancelled.updatedAt.isBefore(before.updatedAt), isFalse);
        final application = (await repository.applicantsFor(
          'opp-promoter',
        )).single.application;
        expect(application.status, ArtistApplicationStatus.declined);
        expect(application.decidedAt, isNotNull);
        expect(await repository.venueConsentsForOrganization('org1'), isEmpty);
        expect(
          (await repository.venueConsentsForOrganization(
            'org1',
            status: VenueConsentStatus.revoked,
          )).single.id,
          revoked.id,
        );
        await expectLater(
          repository.revokeVenueConsent('consent-1'),
          throwsStateError,
        );
      },
    );

    test(
      'draft requests can be withdrawn and retried after a decline',
      () async {
        final repository = DemoRepository(auth: FakeAuthService());
        final created = await repository.createOpportunity(
          organizationId: 'org3',
          title: 'Another Night Shift',
          venueId: 'v1',
          startsAt: DateTime.now().add(const Duration(days: 50)),
        );
        await expectLater(
          repository.requestVenueConsent(
            opportunityId: created.opportunityId,
            message: 'x' * 1001,
          ),
          throwsStateError,
        );
        final id = await repository.requestVenueConsent(
          opportunityId: created.opportunityId,
          message: '  A second showcase.  ',
        );
        final pending = (await repository.venueConsentForOpportunity(
          created.opportunityId,
        ))!;
        expect(pending.id, id);
        expect(pending.status, VenueConsentStatus.pending);
        expect(pending.message, 'A second showcase.');
        expect(pending.note, isNull);
        expect(pending.decidedAt, isNull);
        final inbox = await repository.venueConsentsForOrganization('org1');
        expect(inbox.map((row) => row.id), [id, 'consent-1']);
        expect(inbox.first.venueName, 'The Foghorn Club');
        expect(
          inbox.first.requestingOrganizationName,
          'Night Shift Collective',
        );
        expect(inbox.first.opportunityTitle, 'Another Night Shift');
        expect(inbox.first.opportunityStatus, OpportunityStatus.draft);
        expect(await repository.venueConsentsForOrganization('org3'), isEmpty);
        await repository.withdrawVenueConsent(id);
        final withdrawn = (await repository.venueConsentsForOrganization(
          'org1',
          status: VenueConsentStatus.withdrawn,
        )).single;
        expect(withdrawn.status, VenueConsentStatus.withdrawn);
        expect(withdrawn.message, pending.message);
        expect(withdrawn.createdAt, pending.createdAt);
        expect(withdrawn.decidedAt, isNull);
        expect(
          await repository.venueConsentForOpportunity(created.opportunityId),
          isNull,
        );
        await expectLater(
          repository.withdrawVenueConsent(id),
          throwsStateError,
        );
        final retryId = await repository.requestVenueConsent(
          opportunityId: created.opportunityId,
          message: '  ',
        );
        expect(retryId, isNot(id));
        await expectLater(
          repository.decideVenueConsent(
            consentId: retryId,
            granted: false,
            note: 'x' * 1001,
          ),
          throwsStateError,
        );
        await repository.decideVenueConsent(
          consentId: retryId,
          granted: false,
          note: '  Unavailable  ',
        );
        final declined = (await repository.venueConsentForOpportunity(
          created.opportunityId,
        ))!;
        expect(declined.id, retryId);
        expect(declined.status, VenueConsentStatus.declined);
        expect(declined.message, isNull);
        expect(declined.note, 'Unavailable');
        final lastId = await repository.requestVenueConsent(
          opportunityId: created.opportunityId,
        );
        expect(
          (await repository.venueConsentForOpportunity(
            created.opportunityId,
          ))!.id,
          lastId,
        );
        await repository.withdrawVenueConsent(lastId);
        expect(
          (await repository.venueConsentForOpportunity(
            created.opportunityId,
          ))!.id,
          retryId,
        );
      },
    );

    test(
      'confirmed and disputed bookings prevent revoking venue approval',
      () async {
        final repository = DemoRepository(auth: FakeAuthService())
          ..demoPaymentsEnabled = true;
        final created = await repository.createOpportunity(
          organizationId: 'org3',
          title: 'Started showcase',
          venueId: 'v1',
          startsAt: DateTime.now().subtract(const Duration(hours: 1)),
        );
        final consentId = await repository.requestVenueConsent(
          opportunityId: created.opportunityId,
        );
        await repository.decideVenueConsent(
          consentId: consentId,
          granted: true,
        );
        await repository.openOpportunity(
          opportunityId: created.opportunityId,
          expectedRevision: 1,
        );
        final opportunity = (await repository.opportunity(
          created.opportunityId,
        ))!;
        final applicationId = await repository.applyToOpportunity(
          opportunityId: opportunity.id,
          slotId: opportunity.slots.single.id,
          bandId: 'b1',
          message: 'Ready to play.',
        );
        await repository.reviewApplication(
          applicationId: applicationId,
          action: ArtistApplicationReviewAction.shortlisted,
        );
        final offer = await repository.sendOffer(
          applicationId: applicationId,
          grossMinor: 10000,
          cancellationTemplate: CancellationTemplate.standard,
        );
        await repository.respondToOffer(
          bookingId: offer.bookingId,
          accept: true,
          expectedRevision: offer.revision,
        );
        final payment = (await repository.paymentsForBooking(
          offer.bookingId,
        )).single;
        final checkout = await repository.startInstallmentCheckout(payment.id);
        await repository.simulateCheckoutCompleted(checkout.sessionId);
        for (final status in [
          BookingStatus.confirmed,
          BookingStatus.disputed,
        ]) {
          if (status == BookingStatus.disputed) {
            await repository.openDispute(
              bookingId: offer.bookingId,
              side: DisputeSide.artist,
              category: DisputeCategory.payment,
              text: 'Please investigate the payment.',
            );
          }
          expect((await repository.booking(offer.bookingId))!.status, status);
          await expectLater(
            repository.revokeVenueConsent(consentId),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'This event already has a confirmed booking. Contact EarPlug support.',
              ),
            ),
          );
          expect(
            (await repository.venueConsentForOpportunity(
              opportunity.id,
            ))!.status,
            VenueConsentStatus.granted,
          );
          expect(
            (await repository.opportunity(opportunity.id))!.status,
            OpportunityStatus.confirmed,
          );
        }
      },
    );
  });
}
