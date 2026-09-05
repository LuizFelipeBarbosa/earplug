import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('Venue.fromJson', () {
    test('treats legacy payloads as exact and capability-unaware', () {
      final venue = Venue.fromJson({
        '_id': 'legacy-venue',
        'name': 'Legacy Hall',
        'area': 'Oakland',
        'addr': '100 Broadway, Oakland',
        'lat': 37.8044,
        'lng': -122.2712,
      });

      expect(venue.precision, LocationPrecision.exact);
      expect(venue.supportsApproxLocation, isFalse);
      expect(venue.exactAddress, venue.addr);
      expect(venue.exactPoint, venue.point);
      expect(venue.approx.centroid, venue.point);
      expect(venue.approx.label, venue.area);
      expect(venue.description, isNull);
      expect(venue.venueType, isNull);
      expect(venue.capacityPublic, isNull);
    });

    test('uses the approximate centroid when exact address is withheld', () {
      final venue = Venue.fromJson({
        '_id': 'private-venue',
        'name': 'Private Room',
        'area': 'Mission, San Francisco',
        'addr': 'Mission, San Francisco',
        'lat': 37.75,
        'lng': -122.42,
        'slug': 'private-room',
        'description': 'Cozy backroom bar with a small stage.',
        'venueType': 'bar',
        'capacityPublic': 180,
        'approxLocation': {
          'lat': 37.7599,
          'lng': -122.4148,
          'label': 'Mission, San Francisco',
        },
        'addressDisclosure': 'onTicket',
        'exactAddr': null,
        'verified': true,
      });

      expect(venue.precision, LocationPrecision.approximate);
      expect(venue.supportsApproxLocation, isTrue);
      expect(venue.point, const LatLng(37.7599, -122.4148));
      expect(venue.exactPoint, isNull);
      expect(venue.exactAddress, isNull);
      expect(venue.description, 'Cozy backroom bar with a small stage.');
      expect(venue.venueType, VenueType.bar);
      expect(venue.capacityPublic, 180);
    });
  });

  group('marketplace enum wire values', () {
    test('AddressDisclosure round-trips and defaults to public', () {
      for (final value in AddressDisclosure.values) {
        expect(AddressDisclosure.fromWire(value.wireValue), value);
      }
      expect(AddressDisclosure.fromWire('unknown'), AddressDisclosure.public);
      expect(AddressDisclosure.fromWire(null), AddressDisclosure.public);
    });

    test('VenueType round-trips and defaults to other', () {
      for (final value in VenueType.values) {
        expect(VenueType.fromWire(value.wireValue), value);
      }
      expect(VenueType.fromWire('unknown'), VenueType.other);
      expect(VenueType.fromWire(null), VenueType.other);
    });

    test(
      'OrganizationRole round-trips and uses least privilege by default',
      () {
        for (final value in OrganizationRole.values) {
          expect(OrganizationRole.fromWire(value.wireValue), value);
        }
        expect(OrganizationRole.fromWire('unknown'), OrganizationRole.door);
        expect(OrganizationRole.fromWire(null), OrganizationRole.door);
      },
    );

    test('OrganizationType round-trips and defaults to other', () {
      for (final value in OrganizationType.values) {
        expect(OrganizationType.fromWire(value.wireValue), value);
      }
      expect(OrganizationType.fromWire('unknown'), OrganizationType.other);
      expect(OrganizationType.fromWire(null), OrganizationType.other);
    });

    test('OrganizationStatus round-trips and defaults to pending', () {
      for (final value in OrganizationStatus.values) {
        expect(OrganizationStatus.fromWire(value.wireValue), value);
      }
      expect(
        OrganizationStatus.fromWire('unknown'),
        OrganizationStatus.pending,
      );
      expect(OrganizationStatus.fromWire(null), OrganizationStatus.pending);
    });

    test('OrganizationApplicationStatus round-trips and defaults to draft', () {
      for (final value in OrganizationApplicationStatus.values) {
        expect(OrganizationApplicationStatus.fromWire(value.wireValue), value);
      }
      expect(
        OrganizationApplicationStatus.fromWire('unknown'),
        OrganizationApplicationStatus.draft,
      );
      expect(
        OrganizationApplicationStatus.fromWire(null),
        OrganizationApplicationStatus.draft,
      );
    });

    test('ApplicationDecision round-trips and defaults to review', () {
      for (final value in ApplicationDecision.values) {
        expect(ApplicationDecision.fromWire(value.wireValue), value);
      }
      expect(
        ApplicationDecision.fromWire('unknown'),
        ApplicationDecision.underReview,
      );
      expect(
        ApplicationDecision.fromWire(null),
        ApplicationDecision.underReview,
      );
    });
  });

  test('OrganizationApplication tolerates missing optional fields', () {
    final application = OrganizationApplication.fromJson({
      '_id': 'application-1',
      'status': 'draft',
      'orgName': 'New Room',
      'orgType': 'venueOperator',
      'contactName': 'Alex Doe',
      'businessEmail': 'alex@example.com',
      'revision': 1,
      'createdAt': 1000,
      'updatedAt': 2000,
    });

    expect(application.website, isNull);
    expect(application.phone, isNull);
    expect(application.venue, isNull);
    expect(application.documents, isEmpty);
    expect(application.reviewNote, isNull);
    expect(application.decidedAt, isNull);
    expect(application.resultingOrganizationId, isNull);
    expect(application.resultingVenueId, isNull);
    expect(application.editable, isTrue);

    expect(() => OrganizationApplication.fromJson(const {}), returnsNormally);
    final empty = OrganizationApplication.fromJson(const {});
    expect(empty.status, OrganizationApplicationStatus.draft);
    expect(empty.orgType, OrganizationType.other);
    expect(empty.documents, isEmpty);
    expect(empty.revision, 0);
  });

  test('AdminOverview parses nested counts', () {
    final overview = AdminOverview.fromJson({
      'counts': {
        'submittedApplications': 3,
        'underReviewApplications': 2,
        'needsInfoApplications': 1,
        'verifiedOrganizations': 8,
        'suspendedOrganizations': 4,
      },
      'capped': true,
    });

    expect(overview.submitted, 3);
    expect(overview.underReview, 2);
    expect(overview.needsInfo, 1);
    expect(overview.verifiedOrganizations, 8);
    expect(overview.suspendedOrganizations, 4);
    expect(overview.capped, isTrue);
  });

  test(
    'DemoRepository saves, submits, rejects stale writes, and approves',
    () async {
      final repository = DemoRepository(auth: FakeAuthService());
      expect(await repository.myOrganizationApplication(), isNull);

      final saved = await repository.saveOrganizationApplicationDraft(
        orgName: 'Signal Room',
        orgType: OrganizationType.venueOperator,
        contactName: 'Earplug Fan',
        businessEmail: 'fan@example.com',
        venue: const ApplicationVenueDraft(
          name: 'Signal Room',
          addr: '100 Market St, San Francisco',
          point: LatLng(37.7937, -122.3965),
          area: 'SoMa, San Francisco',
          neighborhood: 'SoMa',
          city: 'San Francisco',
          capacity: 120,
          venueType: VenueType.club,
        ),
      );
      final draft = await repository.myOrganizationApplication();
      expect(draft, isNotNull);
      expect(draft!.id, saved.applicationId);
      expect(draft.revision, saved.revision);
      expect(draft.status, OrganizationApplicationStatus.draft);

      final submittedRevision = await repository.submitOrganizationApplication(
        applicationId: saved.applicationId,
        expectedRevision: saved.revision,
      );
      expect(submittedRevision, saved.revision + 1);
      expect(
        (await repository.myOrganizationApplication())!.status,
        OrganizationApplicationStatus.submitted,
      );

      await expectLater(
        repository.saveOrganizationApplicationDraft(
          applicationId: saved.applicationId,
          expectedRevision: saved.revision,
          orgName: 'Stale Signal Room',
          orgType: OrganizationType.venueOperator,
          contactName: 'Earplug Fan',
          businessEmail: 'fan@example.com',
        ),
        throwsA(isA<StateError>()),
      );

      repository.platformAdmin = true;
      final approval = await repository.decideOrganizationApplication(
        applicationId: saved.applicationId,
        decision: ApplicationDecision.approved,
      );
      expect(approval.status, OrganizationApplicationStatus.approved);
      expect(approval.organizationId, isNotNull);
      expect(approval.venueId, isNotNull);

      final memberships = await repository.myOrganizations().first;
      expect(
        memberships.map((membership) => membership.organization.id),
        contains(approval.organizationId),
      );
    },
  );

  group('DemoRepository opportunities', () {
    late DemoRepository repository;

    setUp(() {
      repository = DemoRepository(auth: FakeAuthService());
    });

    test(
      'public browsing includes opp1 and hides drafts and invitations',
      () async {
        final page = await repository.browseOpportunities();

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
      'missing mutation targets fail and gig writes can be disabled',
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
        expect((await repository.gigWritePolicy()).bandGigWrites, isTrue);
        repository.demoBandGigWrites = false;
        expect((await repository.gigWritePolicy()).bandGigWrites, isFalse);
      },
    );
  });

  group('marketplace Phase 2 models', () {
    const slotJson = {
      '_id': 'slot-1',
      'order': 1,
      'role': 'headliner',
      'setLengthMin': 60,
      'guaranteeMinor': 25000,
      'required': true,
      'status': 'booked',
      'bandId': 'band-1',
    };
    const opportunityJson = {
      '_id': 'opportunity-1',
      'organizationId': 'organization-1',
      'mode': 'publicEvent',
      'venueId': 'venue-1',
      'venue': {
        '_id': 'venue-1',
        'name': 'Signal Room',
        'area': 'Oakland',
        'addr': '100 Broadway, Oakland',
        'lat': 37.8044,
        'lng': -122.2712,
        'venueType': 'club',
      },
      'title': 'Friday Showcase',
      'desc': 'An evening of local bands.',
      'eventType': 'showcase',
      'expectedAttendance': 120,
      'genres': ['indie', 'rock'],
      'startsAt': 1800000000000,
      'doorsAt': 1799996400000,
      'endsAt': 1800007200000,
      'ageRequirement': '21Plus',
      'equipment': 'House PA and drum kit',
      'requirements': 'Bring your own cymbals',
      'flyKey': 'showcase',
      'flyerUrl': 'https://example.com/flyer.jpg',
      'applicationsCloseAt': 1799900000000,
      'visibility': 'inviteOnly',
      'ticketing': 'external',
      'externalUrl': 'https://example.com/tickets',
      'status': 'applications_closed',
      'slug': 'friday-showcase',
      'revision': 3,
      'applicationCount': 4,
      'slots': [slotJson],
      'invitedBandIds': ['band-1', 'band-2'],
      'createdAt': 1799800000000,
      'updatedAt': 1799850000000,
      'area': 'Oakland',
      'venueType': 'club',
      'currency': 'USD',
    };
    const applicationJson = {
      '_id': 'application-1',
      'opportunityId': 'opportunity-1',
      'slotId': 'slot-1',
      'bandId': 'band-1',
      'status': 'under_review',
      'message': 'We would love to play.',
      'askMinor': 30000,
      'availabilityNote': 'Available all evening',
      'lineupNote': 'Four-piece band',
      'decidedAt': 1799850000000,
      'createdAt': 1799800000000,
      'updatedAt': 1799860000000,
    };

    test('Opportunity parses every field and its venue and slots', () {
      final opportunity = Opportunity.fromJson(opportunityJson);

      expect(opportunity.id, 'opportunity-1');
      expect(opportunity.organizationId, 'organization-1');
      expect(opportunity.mode, OpportunityMode.publicEvent);
      expect(opportunity.venueId, 'venue-1');
      expect(opportunity.venue!.id, 'venue-1');
      expect(opportunity.venue!.name, 'Signal Room');
      expect(opportunity.venue!.point, const LatLng(37.8044, -122.2712));
      expect(opportunity.title, 'Friday Showcase');
      expect(opportunity.desc, 'An evening of local bands.');
      expect(opportunity.eventType, 'showcase');
      expect(opportunity.expectedAttendance, 120);
      expect(opportunity.genres, ['indie', 'rock']);
      expect(
        opportunity.startsAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      expect(
        opportunity.doorsAt,
        DateTime.fromMillisecondsSinceEpoch(1799996400000),
      );
      expect(
        opportunity.endsAt,
        DateTime.fromMillisecondsSinceEpoch(1800007200000),
      );
      expect(opportunity.ageRequirement, AgeRequirement.twentyOnePlus);
      expect(opportunity.equipment, 'House PA and drum kit');
      expect(opportunity.requirements, 'Bring your own cymbals');
      expect(opportunity.flyKey, 'showcase');
      expect(opportunity.flyerUrl, 'https://example.com/flyer.jpg');
      expect(
        opportunity.applicationsCloseAt,
        DateTime.fromMillisecondsSinceEpoch(1799900000000),
      );
      expect(opportunity.visibility, OpportunityVisibility.inviteOnly);
      expect(opportunity.ticketing, OpportunityTicketing.external);
      expect(opportunity.externalUrl, 'https://example.com/tickets');
      expect(opportunity.status, OpportunityStatus.applicationsClosed);
      expect(opportunity.slug, 'friday-showcase');
      expect(opportunity.revision, 3);
      expect(opportunity.applicationCount, 4);
      expect(opportunity.invitedBandIds, ['band-1', 'band-2']);
      expect(
        opportunity.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1799800000000),
      );
      expect(
        opportunity.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1799850000000),
      );
      expect(opportunity.area, 'Oakland');
      expect(opportunity.venueType, VenueType.club);
      expect(opportunity.currency, 'USD');

      final slot = opportunity.slots.single;
      expect(slot.id, 'slot-1');
      expect(slot.order, 1);
      expect(slot.role, SlotRole.headliner);
      expect(slot.setLengthMin, 60);
      expect(slot.guaranteeMinor, 25000);
      expect(slot.required, isTrue);
      expect(slot.status, SlotStatus.booked);
      expect(slot.bandId, 'band-1');
    });

    test('Opportunity and OpportunitySlot accept null optional fields', () {
      final opportunity = Opportunity.fromJson({
        ...opportunityJson,
        'mode': 'privateBooking',
        'venueId': null,
        'venue': null,
        'eventType': null,
        'expectedAttendance': null,
        'genres': <String>[],
        'doorsAt': null,
        'endsAt': null,
        'equipment': null,
        'requirements': null,
        'flyerUrl': null,
        'externalUrl': null,
        'slots': <Map<String, dynamic>>[],
        'invitedBandIds': <String>[],
        'venueType': null,
      });

      expect(opportunity.mode, OpportunityMode.privateBooking);
      expect(opportunity.venueId, isNull);
      expect(opportunity.venue, isNull);
      expect(opportunity.eventType, isNull);
      expect(opportunity.expectedAttendance, isNull);
      expect(opportunity.genres, isEmpty);
      expect(opportunity.doorsAt, isNull);
      expect(opportunity.endsAt, isNull);
      expect(opportunity.equipment, isNull);
      expect(opportunity.requirements, isNull);
      expect(opportunity.flyerUrl, isNull);
      expect(opportunity.externalUrl, isNull);
      expect(opportunity.slots, isEmpty);
      expect(opportunity.invitedBandIds, isEmpty);
      expect(opportunity.venueType, isNull);

      final slot = OpportunitySlot.fromJson({
        ...slotJson,
        'setLengthMin': null,
        'bandId': null,
        'required': false,
      });
      expect(slot.setLengthMin, isNull);
      expect(slot.bandId, isNull);
      expect(slot.required, isFalse);
    });

    test('unknown wire enums use their documented defaults', () {
      final opportunity = Opportunity.fromJson({
        ...opportunityJson,
        'mode': 'made-up',
        'visibility': 'made-up',
        'ticketing': 'surprise-future-value',
        'status': 'made-up',
        'ageRequirement': 'made-up',
        'venueType': 'made-up',
        'slots': [
          {...slotJson, 'role': 'made-up', 'status': 'made-up'},
        ],
      });
      final application = ArtistApplication.fromJson({
        ...applicationJson,
        'status': 'made-up',
      });

      expect(opportunity.mode, OpportunityMode.publicEvent);
      expect(opportunity.visibility, OpportunityVisibility.publicListing);
      expect(opportunity.ticketing, OpportunityTicketing.none);
      expect(opportunity.status, OpportunityStatus.draft);
      expect(opportunity.ageRequirement, AgeRequirement.allAges);
      expect(opportunity.venueType, VenueType.other);
      expect(opportunity.slots.single.role, SlotRole.support);
      expect(opportunity.slots.single.status, SlotStatus.open);
      expect(application.status, ArtistApplicationStatus.submitted);
    });

    test('Phase 2 enums round-trip their wire values, including paid', () {
      for (final value in OpportunityMode.values) {
        expect(OpportunityMode.fromWire(value.wireValue), value);
      }
      for (final value in OpportunityVisibility.values) {
        expect(OpportunityVisibility.fromWire(value.wireValue), value);
      }
      for (final value in OpportunityTicketing.values) {
        expect(OpportunityTicketing.fromWire(value.wireValue), value);
      }
      for (final value in OpportunityStatus.values) {
        expect(OpportunityStatus.fromWire(value.wireValue), value);
      }
      for (final value in SlotRole.values) {
        expect(SlotRole.fromWire(value.wireValue), value);
      }
      for (final value in SlotStatus.values) {
        expect(SlotStatus.fromWire(value.wireValue), value);
      }
      for (final value in ArtistApplicationStatus.values) {
        expect(ArtistApplicationStatus.fromWire(value.wireValue), value);
      }
      for (final value in ArtistApplicationReviewAction.values) {
        expect(ArtistApplicationReviewAction.fromWire(value.wireValue), value);
      }
      expect(
        ArtistApplicationReviewAction.fromWire('made-up'),
        ArtistApplicationReviewAction.underReview,
      );
    });

    test('OpportunityFilters omits nulls and uses the correct wire keys', () {
      expect(const OpportunityFilters().toJson(), <String, dynamic>{});
      expect(
        const OpportunityFilters(
          area: 'Oakland',
          genre: 'indie',
          venueType: VenueType.club,
          minGuaranteeMinor: 25000,
        ).toJson(),
        {
          'area': 'Oakland',
          'genre': 'indie',
          'venueType': 'club',
          'minGuaranteeMinor': 25000,
        },
      );
    });

    test('SlotInput only includes setLengthMin when provided', () {
      expect(
        const SlotInput(
          role: SlotRole.opener,
          guaranteeMinor: 0,
          required: false,
        ).toJson(),
        {'role': 'opener', 'guaranteeMinor': 0, 'required': false},
      );
      expect(
        const SlotInput(
          role: SlotRole.headliner,
          setLengthMin: 60,
          guaranteeMinor: 25000,
          required: true,
        ).toJson(),
        {
          'role': 'headliner',
          'setLengthMin': 60,
          'guaranteeMinor': 25000,
          'required': true,
        },
      );
    });

    test('BrowseItem preserves a present application status', () {
      final item = BrowseItem.fromJson({
        'opportunity': opportunityJson,
        'invited': true,
        'myApplicationStatus': 'under_review',
      });

      expect(item.opportunity.id, 'opportunity-1');
      expect(item.invited, isTrue);
      expect(item.myApplicationStatus, ArtistApplicationStatus.underReview);
    });

    test('BrowseItem leaves missing and null application statuses null', () {
      final absent = BrowseItem.fromJson({
        'opportunity': opportunityJson,
        'invited': false,
      });
      final explicitNull = BrowseItem.fromJson({
        'opportunity': opportunityJson,
        'invited': false,
        'myApplicationStatus': null,
      });

      expect(absent.invited, isFalse);
      expect(absent.myApplicationStatus, isNull);
      expect(explicitNull.myApplicationStatus, isNull);
    });

    test('ArtistApplicationStatus identifies active and terminal states', () {
      for (final status in [
        ArtistApplicationStatus.submitted,
        ArtistApplicationStatus.underReview,
        ArtistApplicationStatus.shortlisted,
        ArtistApplicationStatus.offered,
      ]) {
        expect(status.isActive, isTrue);
      }
      for (final status in [
        ArtistApplicationStatus.booked,
        ArtistApplicationStatus.declined,
        ArtistApplicationStatus.withdrawn,
        ArtistApplicationStatus.expired,
      ]) {
        expect(status.isActive, isFalse);
      }
    });

    test('OpportunityPage accepts page and items and parses pagination', () {
      for (final key in ['page', 'items']) {
        final page = OpportunityPage.fromJson({
          key: [
            {
              'opportunity': opportunityJson,
              'invited': true,
              'myApplicationStatus': 'shortlisted',
            },
          ],
          'continueCursor': 'next-page',
          'isDone': false,
        });

        expect(page.items.single.opportunity.id, 'opportunity-1');
        expect(page.items.single.invited, isTrue);
        expect(
          page.items.single.myApplicationStatus,
          ArtistApplicationStatus.shortlisted,
        );
        expect(page.continueCursor, 'next-page');
        expect(page.isDone, isFalse);
      }

      final lastPage = OpportunityPage.fromJson({
        'page': <Map<String, dynamic>>[],
        'continueCursor': null,
        'isDone': true,
      });
      expect(lastPage.items, isEmpty);
      expect(lastPage.continueCursor, isNull);
      expect(lastPage.isDone, isTrue);
    });

    test('ArtistApplication parses all fields and nullable details', () {
      final application = ArtistApplication.fromJson(applicationJson);

      expect(application.id, 'application-1');
      expect(application.opportunityId, 'opportunity-1');
      expect(application.slotId, 'slot-1');
      expect(application.bandId, 'band-1');
      expect(application.status, ArtistApplicationStatus.underReview);
      expect(application.message, 'We would love to play.');
      expect(application.askMinor, 30000);
      expect(application.availabilityNote, 'Available all evening');
      expect(application.lineupNote, 'Four-piece band');
      expect(
        application.decidedAt,
        DateTime.fromMillisecondsSinceEpoch(1799850000000),
      );
      expect(
        application.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1799800000000),
      );
      expect(
        application.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1799860000000),
      );

      final nullable = ArtistApplication.fromJson({
        ...applicationJson,
        'askMinor': null,
        'availabilityNote': null,
        'lineupNote': null,
        'decidedAt': null,
      });
      expect(nullable.askMinor, isNull);
      expect(nullable.availabilityNote, isNull);
      expect(nullable.lineupNote, isNull);
      expect(nullable.decidedAt, isNull);
    });

    test('ApplicantRow and BandApplication parse nested models', () {
      final applicant = ApplicantRow.fromJson({
        'application': applicationJson,
        'band': {
          '_id': 'band-1',
          'name': 'Signal Band',
          'genres': ['indie'],
          'area': 'Oakland',
          'colorHex': '#123456',
          'initials': 'SB',
          'followerCount': 123,
          'heroUrl': 'https://example.com/band.jpg',
        },
        'contactEmail': 'band@example.com',
      });
      final bandApplication = BandApplication.fromJson({
        'application': applicationJson,
        'opportunity': opportunityJson,
      });

      expect(applicant.application.id, 'application-1');
      expect(applicant.band.id, 'band-1');
      expect(applicant.band.name, 'Signal Band');
      expect(applicant.band.genres, ['indie']);
      expect(applicant.band.color.toARGB32(), 0xFF123456);
      expect(applicant.band.followers, 123);
      expect(applicant.band.isSummary, isTrue);
      expect(applicant.band.profileImageUrl, 'https://example.com/band.jpg');
      expect(applicant.contactEmail, 'band@example.com');
      expect(bandApplication.application.id, 'application-1');
      expect(bandApplication.opportunity.id, 'opportunity-1');
    });

    test('marketplace models tolerate incomplete and malformed fields', () {
      final opportunity = Opportunity.fromJson({
        'revision': 2.0,
        'startsAt': 'invalid',
        'venue': false,
        'genres': ['indie', null, 12],
        'invitedBandIds': [null, 'band-1'],
        'slots': [
          false,
          {'guaranteeMinor': 123.0},
        ],
      });
      expect(opportunity.id, '');
      expect(opportunity.mode, OpportunityMode.publicEvent);
      expect(opportunity.status, OpportunityStatus.draft);
      expect(opportunity.revision, 2);
      expect(opportunity.startsAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(opportunity.venue, isNull);
      expect(opportunity.genres, ['indie']);
      expect(opportunity.invitedBandIds, ['band-1']);
      expect(opportunity.slots.single.guaranteeMinor, 123);
      expect(opportunity.slots.single.role, SlotRole.support);
      expect(opportunity.slots.single.status, SlotStatus.open);

      final application = ArtistApplication.fromJson(const {});
      expect(application.status, ArtistApplicationStatus.submitted);
      expect(application.askMinor, isNull);
      expect(application.decidedAt, isNull);
      expect(application.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      final applicant = ApplicantRow.fromJson(const {});
      expect(applicant.application.id, '');
      expect(applicant.band.id, '');
      expect(applicant.contactEmail, isNull);
      expect(BandApplication.fromJson(const {}).opportunity.id, '');
      expect(BrowseItem.fromJson(const {}).myApplicationStatus, isNull);
      expect(OpportunityPage.fromJson(const {}).items, isEmpty);
    });

    test('GigWritePolicy only enables writes for an explicit true', () {
      expect(
        GigWritePolicy.fromJson({'bandGigWrites': true}).bandGigWrites,
        isTrue,
      );
      expect(
        GigWritePolicy.fromJson({'bandGigWrites': false}).bandGigWrites,
        isFalse,
      );
      expect(GigWritePolicy.fromJson(const {}).bandGigWrites, isFalse);
      expect(
        GigWritePolicy.fromJson({'bandGigWrites': 'true'}).bandGigWrites,
        isFalse,
      );
    });
  });
}
