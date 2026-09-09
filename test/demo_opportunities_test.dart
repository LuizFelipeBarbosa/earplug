import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoRepository opportunities', () {
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
      'browsing applies every filter and sorts upcoming public events',
      () async {
        final filtered = await repository.browseOpportunities(
          bandId: 'b1',
          filters: const OpportunityFilters(
            area: 'Mission, San Francisco',
            genre: 'garage',
            venueType: VenueType.bar,
            minGuaranteeMinor: 30000,
          ),
        );
        expect(filtered.items.single.opportunity.id, 'opp1');
        expect(
          filtered.items.single.myApplicationStatus,
          ArtistApplicationStatus.submitted,
        );
        for (final filters in const [
          OpportunityFilters(area: 'Oakland'),
          OpportunityFilters(genre: 'jazz'),
          OpportunityFilters(venueType: VenueType.club),
          OpportunityFilters(minGuaranteeMinor: 30001),
        ]) {
          expect(
            (await repository.browseOpportunities(filters: filters)).items,
            isEmpty,
          );
        }

        final earlier = await repository.createOpportunity(
          organizationId: 'org1',
          title: 'Early Show',
          venueId: 'v1',
          startsAt: DateTime.now().add(const Duration(days: 9)),
        );
        final past = await repository.createOpportunity(
          organizationId: 'org1',
          title: 'Past Show',
          venueId: 'v1',
          startsAt: DateTime.now().subtract(const Duration(days: 1)),
        );
        for (final created in [earlier, past]) {
          await repository.openOpportunity(
            opportunityId: created.opportunityId,
            expectedRevision: 1,
          );
        }
        final page = await repository.browseOpportunities(
          mode: OpportunityMode.publicEvent,
          cursor: 'ignored',
          numItems: 1,
        );
        expect(page.items.map((item) => item.opportunity.id), [
          earlier.opportunityId,
          'opp1',
        ]);
        expect(page.isDone, isTrue);
      },
    );

    test(
      'invitations are idempotent and leave the OCC revision unchanged',
      () async {
        final invited = await repository.invitedOpportunities('b1');
        expect(invited.single.opportunity.id, 'opp3');
        expect(invited.single.invited, isTrue);
        expect(invited.single.myApplicationStatus, isNull);
        expect(await repository.invitedOpportunities('b2'), isEmpty);
        final original = (await repository.opportunity('opp3'))!;

        for (var attempt = 0; attempt < 2; attempt++) {
          expect(
            await repository.inviteBandToOpportunity(
              opportunityId: 'opp3',
              bandId: 'b2',
            ),
            isTrue,
          );
        }
        final updated = (await repository.opportunity('opp3'))!;
        expect(updated.invitedBandIds, ['b1', 'b2']);
        expect(updated.revision, original.revision);
        expect(updated.updatedAt, original.updatedAt);
        expect(original.invitedBandIds, ['b1']);
        expect(
          (await repository.invitedOpportunities('b2')).single.opportunity.id,
          'opp3',
        );

        for (var attempt = 0; attempt < 2; attempt++) {
          await repository.uninviteBandFromOpportunity(
            opportunityId: 'opp3',
            bandId: 'b2',
          );
        }
        expect(await repository.invitedOpportunities('b2'), isEmpty);
        expect(
          (await repository.opportunity('opp3'))!.revision,
          original.revision,
        );

        await repository.inviteBandToOpportunity(
          opportunityId: 'opp1',
          bandId: 'b1',
        );
        expect(
          (await repository.browseOpportunities(
            mode: OpportunityMode.publicEvent,
            bandId: 'b1',
          )).items.single.invited,
          isTrue,
        );
        expect(
          (await repository.invitedOpportunities(
            'b1',
          )).map((item) => item.opportunity.id),
          ['opp1', 'opp3'],
        );
      },
    );

    test(
      'applying and withdrawing restores the active application count',
      () async {
        final original = (await repository.opportunity('opp1'))!;
        final applicationId = await repository.applyToOpportunity(
          opportunityId: 'opp1',
          slotId: 'opp1-support',
          bandId: 'b3',
          message: 'Ready for a short, loud set.',
          askMinor: 15000,
          availabilityNote: 'After 6pm',
          lineupNote: 'Three-piece',
        );
        expect(applicationId, startsWith('demo-artist-application-'));
        expect(
          (await repository.opportunity('opp1'))!.applicationCount,
          original.applicationCount + 1,
        );
        final application = (await repository.myApplicationFor(
          opportunityId: 'opp1',
          bandId: 'b3',
        ))!;
        expect(application.id, applicationId);
        expect(application.status, ArtistApplicationStatus.submitted);
        expect(application.message, 'Ready for a short, loud set.');
        expect(application.askMinor, 15000);
        expect(application.availabilityNote, 'After 6pm');
        expect(application.lineupNote, 'Three-piece');
        expect(application.decidedAt, isNull);

        await expectLater(
          repository.applyToOpportunity(
            opportunityId: 'opp1',
            slotId: 'opp1-headliner',
            bandId: 'b3',
            message: 'Again',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'You already applied to this opportunity',
            ),
          ),
        );
        await repository.withdrawApplication(applicationId);
        final withdrawn = (await repository.myApplicationFor(
          opportunityId: 'opp1',
          bandId: 'b3',
        ))!;
        expect(withdrawn.status, ArtistApplicationStatus.withdrawn);
        expect(withdrawn.decidedAt, isNull);
        expect(withdrawn.createdAt, application.createdAt);
        expect(
          (await repository.opportunity('opp1'))!.applicationCount,
          original.applicationCount,
        );
        expect(application.status, ArtistApplicationStatus.submitted);
        await expectLater(
          repository.withdrawApplication(applicationId),
          throwsA(isA<StateError>()),
        );
        expect(
          (await repository.opportunity('opp1'))!.applicationCount,
          original.applicationCount,
        );
      },
    );

    test(
      'an organizer creates a draft, opens it, and receives applicants',
      () async {
        final startsAt = DateTime.now().add(const Duration(days: 30));
        final created = await repository.createOpportunity(
          organizationId: 'org1',
          title: 'Local Showcase',
          venueId: 'v1',
          startsAt: startsAt,
        );
        final draft = (await repository.opportunity(created.opportunityId))!;
        expect(created.opportunityId, startsWith('demo-opportunity-'));
        expect(created.slug, 'local-showcase');
        expect(draft.status, OpportunityStatus.draft);
        expect(draft.revision, 1);
        expect(draft.applicationCount, 0);
        expect(draft.mode, OpportunityMode.publicEvent);
        expect(
          draft.applicationsCloseAt,
          startsAt.subtract(const Duration(days: 7)),
        );
        expect(draft.visibility, OpportunityVisibility.publicListing);
        expect(draft.ticketing, OpportunityTicketing.rsvp);
        expect(draft.ageRequirement, AgeRequirement.allAges);
        expect(draft.flyKey, 'xerox');
        expect(draft.currency, 'usd');
        expect(draft.genres, isEmpty);
        expect(draft.invitedBandIds, isEmpty);
        expect(draft.venue, DemoData.venues['v1']);
        expect(draft.area, draft.venue!.approx.label);
        expect(draft.venueType, VenueType.bar);
        expect(draft.slots.single.id, startsWith('demo-slot-'));
        expect(draft.slots.single.role, SlotRole.headliner);
        expect(draft.slots.single.guaranteeMinor, 0);
        expect(draft.slots.single.required, isTrue);
        expect(draft.slots.single.status, SlotStatus.open);
        expect(draft.slots.single.bandId, isNull);
        expect(await repository.applicantsFor(draft.id), isEmpty);

        final opened = await repository.openOpportunity(
          opportunityId: draft.id,
          expectedRevision: draft.revision,
        );
        expect(opened.revision, 2);
        expect(opened.applicationsCloseAt, draft.applicationsCloseAt);
        expect(
          (await repository.opportunity(draft.id))!.status,
          OpportunityStatus.open,
        );
        final applicationId = await repository.applyToOpportunity(
          opportunityId: draft.id,
          slotId: draft.slots.single.id,
          bandId: 'b1',
          message: 'We would love to play.',
        );
        final applicant = (await repository.applicantsFor(draft.id)).single;
        expect(applicant.application.id, applicationId);
        expect(applicant.band.name, 'Foghorn Diet');
        expect(applicant.contactEmail, 'fan@example.com');
        expect(draft.status, OpportunityStatus.draft);
      },
    );

    test(
      'updates replace supplied fields, preserve others, and reject stale writes',
      () async {
        final original = (await repository.opportunity('opp2'))!;
        final startsAt = original.startsAt.add(const Duration(days: 1));
        final doorsAt = startsAt.subtract(const Duration(hours: 1));
        final endsAt = startsAt.add(const Duration(hours: 3));
        final closesAt = startsAt.subtract(const Duration(days: 2));
        final revision = await repository.updateOpportunity(
          opportunityId: 'opp2',
          expectedRevision: 1,
          title: 'Record Store Sessions',
          desc: 'Live among the vinyl bins.',
          venueId: 'v2',
          eventType: 'showcase',
          expectedAttendance: 100,
          genres: ['garage'],
          startsAt: startsAt,
          doorsAt: doorsAt,
          endsAt: endsAt,
          ageRequirement: AgeRequirement.eighteenPlus,
          equipment: 'PA provided',
          requirements: 'Bring cymbals',
          flyKey: 'custom',
          flyStorageId: 'record-store-flyer',
          applicationsCloseAt: closesAt,
          visibility: OpportunityVisibility.inviteOnly,
          ticketing: OpportunityTicketing.external,
          externalUrl: 'https://example.com/tickets',
          slots: const [
            SlotInput(
              role: SlotRole.headliner,
              guaranteeMinor: 20000,
              required: true,
              setLengthMin: 45,
            ),
            SlotInput(
              role: SlotRole.support,
              guaranteeMinor: 10000,
              required: false,
            ),
          ],
        );
        final updated = (await repository.opportunity('opp2'))!;
        expect(revision, 2);
        expect(updated.title, 'Record Store Sessions');
        expect(updated.desc, 'Live among the vinyl bins.');
        expect(updated.venueId, 'v2');
        expect(updated.venue, DemoData.venues['v2']);
        expect(updated.area, DemoData.venues['v2']!.area);
        expect(updated.venueType, isNull);
        expect(updated.eventType, 'showcase');
        expect(updated.expectedAttendance, 100);
        expect(updated.genres, ['garage']);
        expect(updated.startsAt, startsAt);
        expect(updated.doorsAt, doorsAt);
        expect(updated.endsAt, endsAt);
        expect(updated.ageRequirement, AgeRequirement.eighteenPlus);
        expect(updated.equipment, 'PA provided');
        expect(updated.requirements, 'Bring cymbals');
        expect(updated.flyKey, 'custom');
        expect(updated.flyerUrl, 'demo://flyer/record-store-flyer');
        expect(updated.applicationsCloseAt, closesAt);
        expect(updated.visibility, OpportunityVisibility.inviteOnly);
        expect(updated.ticketing, OpportunityTicketing.external);
        expect(updated.externalUrl, 'https://example.com/tickets');
        expect(updated.slots.map((slot) => slot.order), [0, 1]);
        expect(updated.slots.map((slot) => slot.guaranteeMinor), [
          20000,
          10000,
        ]);
        expect(updated.slots.first.setLengthMin, 45);
        expect(updated.slots.last.required, isFalse);
        expect(
          updated.slots.every(
            (slot) => slot.status == SlotStatus.open && slot.bandId == null,
          ),
          isTrue,
        );
        expect(
          updated.slots.map((slot) => slot.id),
          isNot(contains(original.slots.single.id)),
        );
        expect(updated.slug, original.slug);
        expect(updated.createdAt, original.createdAt);
        expect(original.title, 'Patio Sessions');

        await expectLater(
          repository.updateOpportunity(
            opportunityId: 'opp2',
            expectedRevision: 1,
            title: 'Stale',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Opportunity changed elsewhere',
            ),
          ),
        );
        await expectLater(
          repository.openOpportunity(
            opportunityId: 'opp2',
            expectedRevision: 1,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Opportunity changed elsewhere',
            ),
          ),
        );
        await repository.updateOpportunity(
          opportunityId: 'opp2',
          expectedRevision: 2,
          desc: 'Updated description',
        );
        final preserved = (await repository.opportunity('opp2'))!;
        expect(preserved.title, updated.title);
        expect(preserved.slots, updated.slots);
        expect(preserved.flyerUrl, updated.flyerUrl);
        expect(preserved.startsAt, updated.startsAt);
      },
    );

    test(
      'opening validates drafts, slots and deadlines before changing state',
      () async {
        await expectLater(
          repository.openOpportunity(
            opportunityId: 'opp1',
            expectedRevision: 1,
          ),
          throwsA(isA<StateError>()),
        );
        await repository.updateOpportunity(
          opportunityId: 'opp2',
          expectedRevision: 1,
          slots: [],
        );
        await expectLater(
          repository.openOpportunity(
            opportunityId: 'opp2',
            expectedRevision: 2,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Add at least one slot before opening',
            ),
          ),
        );
        final draft = (await repository.opportunity('opp2'))!;
        await repository.updateOpportunity(
          opportunityId: 'opp2',
          expectedRevision: 2,
          applicationsCloseAt: draft.startsAt,
          slots: const [
            SlotInput(role: SlotRole.opener, guaranteeMinor: 0, required: true),
          ],
        );
        await expectLater(
          repository.openOpportunity(
            opportunityId: 'opp2',
            expectedRevision: 3,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Applications must close before the event starts',
            ),
          ),
        );
        expect(
          (await repository.opportunity('opp2'))!.status,
          OpportunityStatus.draft,
        );
        await expectLater(
          repository.updateOpportunity(
            opportunityId: 'opp1',
            expectedRevision: 1,
            slots: [],
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Slots are locked once applications are open',
            ),
          ),
        );
        await expectLater(
          repository.deleteOpportunityDraft('opp1'),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repository.applyToOpportunity(
            opportunityId: 'opp2',
            slotId: draft.slots.firstOrNull?.id ?? 'missing',
            bandId: 'b3',
            message: 'Hello',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'This opportunity is not accepting applications',
            ),
          ),
        );
        await expectLater(
          repository.applyToOpportunity(
            opportunityId: 'opp1',
            slotId: 'missing',
            bandId: 'b3',
            message: 'Hello',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'This slot is no longer available',
            ),
          ),
        );
        expect((await repository.opportunity('opp1'))!.applicationCount, 2);
      },
    );

    test(
      'duplication resets booking state and reserves unique slugs after deletion',
      () async {
        await repository.inviteBandToOpportunity(
          opportunityId: 'opp1',
          bandId: 'b1',
        );
        final source = (await repository.opportunity('opp1'))!;
        final created = await repository.duplicateOpportunity('opp1');
        final duplicate = (await repository.opportunity(
          created.opportunityId,
        ))!;
        expect(created.slug, 'friday-night-live-2');
        expect(duplicate.id, isNot(source.id));
        expect(duplicate.title, source.title);
        expect(duplicate.desc, source.desc);
        expect(duplicate.organizationId, source.organizationId);
        expect(duplicate.venue, source.venue);
        expect(duplicate.genres, source.genres);
        expect(duplicate.startsAt, source.startsAt);
        expect(duplicate.applicationsCloseAt, source.applicationsCloseAt);
        expect(duplicate.status, OpportunityStatus.draft);
        expect(duplicate.revision, 1);
        expect(duplicate.applicationCount, 0);
        expect(duplicate.invitedBandIds, isEmpty);
        expect(await repository.applicantsFor(duplicate.id), isEmpty);
        expect(
          duplicate.slots.map((slot) => slot.role),
          source.slots.map((slot) => slot.role),
        );
        expect(duplicate.slots.map((slot) => slot.guaranteeMinor), [
          30000,
          15000,
        ]);
        expect(
          duplicate.slots.every(
            (slot) => slot.status == SlotStatus.open && slot.bandId == null,
          ),
          isTrue,
        );
        expect(
          duplicate.slots
              .map((slot) => slot.id)
              .toSet()
              .intersection(source.slots.map((slot) => slot.id).toSet()),
          isEmpty,
        );
        expect(duplicate.createdAt.isAfter(source.createdAt), isTrue);
        await repository.deleteOpportunityDraft(duplicate.id);
        expect(await repository.opportunity(duplicate.id), isNull);
        expect(await repository.resolveOpportunity(created.slug), isNull);
        final next = await repository.createOpportunity(
          organizationId: 'org1',
          title: source.title,
          venueId: 'v1',
          startsAt: source.startsAt,
          slots: [],
        );
        expect(next.slug, 'friday-night-live-3');
        expect(
          (await repository.opportunity(next.opportunityId))!.slots.single.role,
          SlotRole.headliner,
        );
        expect(source.invitedBandIds, ['b1']);
        expect(source.applicationCount, 2);
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

    test(
      'resolution checks membership and invite-only access for ids and slugs',
      () async {
        expect(
          (await repository.resolveOpportunity(
            'friday-night-live',
          ))!.opportunity.id,
          'opp1',
        );
        expect(
          (await repository.resolveOpportunity('opp2'))!.opportunity.status,
          OpportunityStatus.draft,
        );
        expect(await repository.resolveOpportunity('unknown'), isNull);
        expect(await repository.resolveOpportunity('opp3'), isNull);
        expect(
          await repository.resolveOpportunity('opp3', bandId: 'b2'),
          isNull,
        );
        expect(
          (await repository.resolveOpportunity(
            'private-preview',
            bandId: 'b1',
          ))!.invited,
          isTrue,
        );
        await repository.cancelOpportunity('opp1');
        expect(
          (await repository.resolveOpportunity('opp1'))!.opportunity.status,
          OpportunityStatus.cancelled,
        );
        await repository.removeOrganizationMember(
          organizationId: 'org1',
          userId: DemoData.demoUserId,
        );
        expect(await repository.resolveOpportunity('opp1'), isNull);
        expect(await repository.resolveOpportunity('opp2'), isNull);
        expect(
          (await repository.resolveOpportunity(
            'opp3',
            bandId: 'b1',
          ))!.opportunity.id,
          'opp3',
        );
      },
    );

    test(
      'review transitions maintain counts without double-decrementing',
      () async {
        for (final action in [
          ArtistApplicationReviewAction.underReview,
          ArtistApplicationReviewAction.shortlisted,
        ]) {
          await repository.reviewApplication(
            applicationId: 'app1',
            action: action,
          );
          final application = (await repository.myApplicationFor(
            opportunityId: 'opp1',
            bandId: 'b1',
          ))!;
          expect(
            application.status,
            action == ArtistApplicationReviewAction.underReview
                ? ArtistApplicationStatus.underReview
                : ArtistApplicationStatus.shortlisted,
          );
          expect(application.decidedAt, isNull);
          expect((await repository.opportunity('opp1'))!.applicationCount, 2);
        }
        for (var attempt = 0; attempt < 2; attempt++) {
          await repository.reviewApplication(
            applicationId: 'app1',
            action: ArtistApplicationReviewAction.declined,
          );
          expect((await repository.opportunity('opp1'))!.applicationCount, 1);
        }
        final declined = (await repository.myApplicationFor(
          opportunityId: 'opp1',
          bandId: 'b1',
        ))!;
        expect(declined.status, ArtistApplicationStatus.declined);
        expect(declined.decidedAt, isNotNull);
        await repository.reviewApplication(
          applicationId: 'app1',
          action: ArtistApplicationReviewAction.underReview,
        );
        final reviewed = (await repository.myApplicationFor(
          opportunityId: 'opp1',
          bandId: 'b1',
        ))!;
        expect(reviewed.decidedAt, declined.decidedAt);
        expect((await repository.opportunity('opp1'))!.applicationCount, 2);
      },
    );

    test(
      'closing expires pending applications and cancellation declines active ones',
      () async {
        final underReviewId = await repository.applyToOpportunity(
          opportunityId: 'opp1',
          slotId: 'opp1-support',
          bandId: 'b3',
          message: 'Ready to play',
        );
        await repository.reviewApplication(
          applicationId: underReviewId,
          action: ArtistApplicationReviewAction.underReview,
        );
        await repository.closeOpportunityApplications('opp1');
        final closed = (await repository.opportunity('opp1'))!;
        expect(closed.status, OpportunityStatus.applicationsClosed);
        expect(closed.revision, 2);
        expect(closed.applicationCount, 1);
        final rows = await repository.applicantsFor('opp1');
        expect(rows.map((row) => row.application.id), [
          underReviewId,
          'app1',
          'app2',
        ]);
        expect(rows.map((row) => row.application.status), [
          ArtistApplicationStatus.expired,
          ArtistApplicationStatus.expired,
          ArtistApplicationStatus.shortlisted,
        ]);
        expect(rows.every((row) => row.application.decidedAt == null), isTrue);
        expect(rows.last.contactEmail, isNull);
        await repository.closeOpportunityApplications('opp1');
        expect((await repository.opportunity('opp1'))!.applicationCount, 1);

        final closesAt = closed.startsAt.subtract(const Duration(days: 1));
        await repository.reopenOpportunity(
          opportunityId: 'opp1',
          applicationsCloseAt: closesAt,
        );
        final reopened = (await repository.opportunity('opp1'))!;
        expect(reopened.status, OpportunityStatus.open);
        expect(reopened.revision, 4);
        expect(reopened.applicationsCloseAt, closesAt);
        final newApplicationId = await repository.applyToOpportunity(
          opportunityId: 'opp1',
          slotId: 'opp1-support',
          bandId: 'b1',
          message: 'Available again',
        );
        expect((await repository.opportunity('opp1'))!.applicationCount, 2);
        await repository.cancelOpportunity('opp1', reason: 'Venue maintenance');
        final cancelled = (await repository.opportunity('opp1'))!;
        expect(cancelled.status, OpportunityStatus.cancelled);
        expect(cancelled.revision, 5);
        expect(cancelled.applicationCount, 0);
        final applications = (await repository.applicantsFor(
          'opp1',
        )).map((row) => row.application).toList();
        expect(
          applications.where((application) => application.status.isActive),
          isEmpty,
        );
        for (final application in applications) {
          if (application.id == newApplicationId || application.id == 'app2') {
            expect(application.status, ArtistApplicationStatus.declined);
            expect(application.decidedAt, isNotNull);
          } else {
            expect(application.status, ArtistApplicationStatus.expired);
            expect(application.decidedAt, isNull);
          }
        }
        await repository.cancelOpportunity('opp1');
        expect((await repository.opportunity('opp1'))!.applicationCount, 0);
      },
    );

    test(
      'band reads use the newest application and repositories isolate fixture state',
      () async {
        await repository.withdrawApplication('app1');
        final latestId = await repository.applyToOpportunity(
          opportunityId: 'opp1',
          slotId: 'opp1-headliner',
          bandId: 'b1',
          message: 'A fresh application',
        );
        await repository.reviewApplication(
          applicationId: 'app1',
          action: ArtistApplicationReviewAction.declined,
        );
        expect(
          (await repository.myApplicationFor(
            opportunityId: 'opp1',
            bandId: 'b1',
          ))!.id,
          latestId,
        );
        final applications = await repository.myApplications('b1');
        expect(applications.map((item) => item.application.id), [
          latestId,
          'app1',
        ]);
        expect(
          applications.every((item) => item.opportunity.id == 'opp1'),
          isTrue,
        );
        expect(applications.first.opportunity.applicationCount, 2);
        expect(
          (await repository.browseOpportunities(
            mode: OpportunityMode.publicEvent,
            bandId: 'b1',
          )).items.single.myApplicationStatus,
          ArtistApplicationStatus.submitted,
        );
        expect(
          (await repository.resolveOpportunity(
            'opp1',
            bandId: 'b1',
          ))!.myApplicationStatus,
          ArtistApplicationStatus.submitted,
        );
        expect(await repository.myApplications('missing'), isEmpty);
        expect(
          await repository.myApplicationFor(
            opportunityId: 'opp3',
            bandId: 'b1',
          ),
          isNull,
        );

        await repository.applyToOpportunity(
          opportunityId: 'opp3',
          slotId: 'opp3-headliner',
          bandId: 'b1',
          message: 'See you there',
        );
        expect(
          (await repository.invitedOpportunities(
            'b1',
          )).single.myApplicationStatus,
          ArtistApplicationStatus.submitted,
        );
        final fresh = DemoRepository(auth: FakeAuthService());
        expect(
          (await fresh.myApplicationFor(
            opportunityId: 'opp1',
            bandId: 'b1',
          ))!.status,
          ArtistApplicationStatus.submitted,
        );
        expect((await fresh.opportunity('opp1'))!.applicationCount, 2);
        expect((await fresh.opportunity('opp3'))!.applicationCount, 0);
        expect(
          DemoData.artistApplications['app1']!.status,
          ArtistApplicationStatus.submitted,
        );
      },
    );

    test(
      'missing mutation targets fail',
      () async {
        await expectLater(
          repository.cancelOpportunity('missing'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Opportunity not found.',
            ),
          ),
        );
        await expectLater(
          repository.withdrawApplication('missing'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Artist application not found.',
            ),
          ),
        );
        await expectLater(
          repository.createOpportunity(
            organizationId: 'org1',
            title: 'Missing venue',
            venueId: 'missing',
            startsAt: DateTime.now(),
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
