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

  group('Booking.fromJson', () {
    const feeJson = {
      'grossMinor': 15000,
      'commissionBps': 1000,
      'commissionMinor': 1500,
      'artistNetMinor': 13500,
      'currency': 'usd',
    };
    const offerJson = {
      'revision': 2,
      'message': 'Looking forward to the show.',
      'sentAt': 1799800000000,
      'expiresAt': 1799900000000,
      'response': 'accepted',
      'installments': [
        {'label': 'Full payment', 'amountMinor': 15000, 'dueAt': 1799990000000},
      ],
    };
    const venueJson = {
      '_id': 'venue-1',
      'name': 'Signal Room',
      'slug': 'signal-room',
      'approxLabel': 'Oakland',
      'exactAddress': '100 Broadway, Oakland',
    };
    const bookingJson = {
      '_id': 'booking-1',
      'opportunityId': 'opportunity-1',
      'opportunityTitle': 'Friday Showcase',
      'opportunitySlug': 'friday-showcase',
      'slotId': 'slot-1',
      'slotRole': 'headliner',
      'slotRequired': true,
      'organizationId': 'organization-1',
      'organizationName': 'Signal Collective',
      'bandId': 'band-1',
      'bandName': 'The Night Shifts',
      'bandSlug': 'the-night-shifts',
      'applicationId': 'application-1',
      'status': 'cancelled_by_organizer',
      'revision': 3,
      'startsAt': 1800000000000,
      'doorsAt': 1799996400000,
      'fee': feeJson,
      'cancellationTemplate': 'standard',
      'termsNotes': 'House PA provided.',
      'organizerAcceptedTermsAt': 1799800000000,
      'artistAcceptedTermsAt': 1799810000000,
      'confirmedAt': 1799820000000,
      'completedAt': 1800010000000,
      'cancelledAt': 1800020000000,
      'cancelledBy': 'organizer',
      'cancelReason': 'Venue unavailable.',
      'expiresAt': 1799900000000,
      'currentOffer': offerJson,
      'venue': venueJson,
      'publicGigId': 'gig-1',
      'publicGigSlug': 'night-shifts-at-signal-room',
      'counterpartyEmail': 'band@example.com',
      'viewerSide': 'organizer',
    };

    test('parses every field in a full booking payload', () {
      final booking = Booking.fromJson(bookingJson);

      expect(booking.id, 'booking-1');
      expect(booking.opportunityId, 'opportunity-1');
      expect(booking.opportunityTitle, 'Friday Showcase');
      expect(booking.opportunitySlug, 'friday-showcase');
      expect(booking.slotId, 'slot-1');
      expect(booking.slotRole, SlotRole.headliner);
      expect(booking.slotRequired, isTrue);
      expect(booking.organizationId, 'organization-1');
      expect(booking.organizationName, 'Signal Collective');
      expect(booking.bandId, 'band-1');
      expect(booking.bandName, 'The Night Shifts');
      expect(booking.bandSlug, 'the-night-shifts');
      expect(booking.applicationId, 'application-1');
      expect(booking.status, BookingStatus.cancelledByOrganizer);
      expect(booking.revision, 3);
      expect(
        booking.startsAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      expect(
        booking.doorsAt,
        DateTime.fromMillisecondsSinceEpoch(1799996400000),
      );
      expect(booking.fee.grossMinor, 15000);
      expect(booking.fee.commissionBps, 1000);
      expect(booking.fee.commissionMinor, 1500);
      expect(booking.fee.artistNetMinor, 13500);
      expect(booking.fee.currency, 'usd');
      expect(booking.cancellationTemplate, CancellationTemplate.standard);
      expect(booking.termsNotes, 'House PA provided.');
      expect(
        booking.organizerAcceptedTermsAt,
        DateTime.fromMillisecondsSinceEpoch(1799800000000),
      );
      expect(
        booking.artistAcceptedTermsAt,
        DateTime.fromMillisecondsSinceEpoch(1799810000000),
      );
      expect(
        booking.confirmedAt,
        DateTime.fromMillisecondsSinceEpoch(1799820000000),
      );
      expect(
        booking.completedAt,
        DateTime.fromMillisecondsSinceEpoch(1800010000000),
      );
      expect(
        booking.cancelledAt,
        DateTime.fromMillisecondsSinceEpoch(1800020000000),
      );
      expect(booking.cancelledBy, BookingCancelledBy.organizer);
      expect(booking.cancelReason, 'Venue unavailable.');
      expect(
        booking.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1799900000000),
      );
      final offer = booking.currentOffer!;
      expect(offer.revision, 2);
      expect(offer.message, 'Looking forward to the show.');
      expect(offer.sentAt, DateTime.fromMillisecondsSinceEpoch(1799800000000));
      expect(
        offer.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1799900000000),
      );
      expect(offer.response, OfferResponse.accepted);
      final installment = offer.installments.single;
      expect(installment.label, 'Full payment');
      expect(installment.amountMinor, 15000);
      expect(
        installment.dueAt,
        DateTime.fromMillisecondsSinceEpoch(1799990000000),
      );
      expect(booking.venue.id, 'venue-1');
      expect(booking.venue.name, 'Signal Room');
      expect(booking.venue.slug, 'signal-room');
      expect(booking.venue.approxLabel, 'Oakland');
      expect(booking.venue.exactAddress, '100 Broadway, Oakland');
      expect(booking.publicGigId, 'gig-1');
      expect(booking.publicGigSlug, 'night-shifts-at-signal-room');
      expect(booking.counterpartyEmail, 'band@example.com');
      expect(booking.viewerSide, BookingSide.organizer);
    });

    test('preserves nulls for every nullable booking and venue field', () {
      final booking = Booking.fromJson({
        ...bookingJson,
        'doorsAt': null,
        'termsNotes': null,
        'artistAcceptedTermsAt': null,
        'confirmedAt': null,
        'completedAt': null,
        'cancelledAt': null,
        'cancelledBy': null,
        'cancelReason': null,
        'expiresAt': null,
        'currentOffer': null,
        'publicGigId': null,
        'publicGigSlug': null,
        'counterpartyEmail': null,
        'venue': {
          ...venueJson,
          'slug': null,
          'approxLabel': null,
          'exactAddress': null,
        },
      });

      expect(booking.doorsAt, isNull);
      expect(booking.termsNotes, isNull);
      expect(booking.artistAcceptedTermsAt, isNull);
      expect(booking.confirmedAt, isNull);
      expect(booking.completedAt, isNull);
      expect(booking.cancelledAt, isNull);
      expect(booking.cancelledBy, isNull);
      expect(booking.cancelReason, isNull);
      expect(booking.expiresAt, isNull);
      expect(booking.currentOffer, isNull);
      expect(booking.publicGigId, isNull);
      expect(booking.publicGigSlug, isNull);
      expect(booking.counterpartyEmail, isNull);
      expect(booking.venue.slug, isNull);
      expect(booking.venue.approxLabel, isNull);
      expect(booking.venue.exactAddress, isNull);
    });

    test('defaults missing and malformed fields without throwing', () {
      for (final json in <Map<String, dynamic>>[
        const {},
        {
          '_id': 7,
          'status': 'something_new',
          'slotRole': false,
          'slotRequired': 'true',
          'startsAt': 'tomorrow',
          'doorsAt': 'tonight',
          'revision': 'three',
          'fee': 'not a map',
          'venue': ['not a map'],
          'currentOffer': 42,
          'termsNotes': false,
          'counterpartyEmail': 7,
        },
      ]) {
        final booking = Booking.fromJson(json);
        expect(booking.id, '');
        expect(booking.status, BookingStatus.unknown);
        expect(booking.slotRole, SlotRole.support);
        expect(booking.slotRequired, isFalse);
        expect(booking.startsAt, DateTime.fromMillisecondsSinceEpoch(0));
        expect(booking.doorsAt, isNull);
        expect(booking.revision, 0);
        expect(booking.fee.grossMinor, 0);
        expect(booking.fee.currency, '');
        expect(booking.venue.id, '');
        expect(booking.currentOffer, isNull);
        expect(booking.termsNotes, isNull);
        expect(booking.counterpartyEmail, isNull);
      }
    });

    test(
      'BookingOffer preserves unanswered responses and optional messages',
      () {
        final offer = BookingOffer.fromJson({
          ...offerJson,
          'message': null,
          'response': null,
        });
        expect(offer.message, isNull);
        expect(offer.response, isNull);
        expect(BookingOffer.fromJson(const {}).installments, isEmpty);
        final malformed = BookingOffer.fromJson({
          'response': 'something_new',
          'installments': [
            null,
            'invalid',
            {'label': 5, 'amountMinor': 'free'},
          ],
        });
        expect(malformed.response, OfferResponse.withdrawn);
        expect(malformed.installments.single.label, '');
        expect(malformed.installments.single.amountMinor, 0);
        expect(
          malformed.installments.single.dueAt,
          DateTime.fromMillisecondsSinceEpoch(0),
        );
      },
    );

    test('FeeBreakdown exposes snapshot amounts as Money', () {
      final fee = FeeBreakdown.fromJson(feeJson);
      expect(fee.grossMinor, 15000);
      expect(fee.commissionBps, 1000);
      expect(fee.commissionMinor, 1500);
      expect(fee.artistNetMinor, 13500);
      expect(fee.currency, 'usd');
      expect(fee.gross.label, '\$150.00');
      expect(fee.commission.label, '\$15.00');
      expect(fee.artistNet.label, '\$135.00');
    });
  });

  group('Phase 3b payment models', () {
    test(
      'StripeAccountStatus parses every field, including the account flag',
      () {
        final status = StripeAccountStatus.fromJson({
          'state': 'restricted',
          'stripeAccountId': true,
          'chargesEnabled': true,
          'payoutsEnabled': false,
          'detailsSubmitted': true,
          'requirementsDue': ['external_account', 'business_profile.url'],
        });
        expect(status.state, StripeAccountState.restricted);
        expect(status.hasAccount, isTrue);
        expect(status.chargesEnabled, isTrue);
        expect(status.payoutsEnabled, isFalse);
        expect(status.detailsSubmitted, isTrue);
        expect(status.requirementsDue, [
          'external_account',
          'business_profile.url',
        ]);
      },
    );

    test('PaymentRecord parses every field and exposes its Money amount', () {
      final payment = PaymentRecord.fromJson({
        '_id': 'payment-1',
        'installmentIndex': 2,
        'label': 'Final payment',
        'amountMinor': 12345,
        'currency': 'usd',
        'dueAt': 1800000000000,
        'status': 'paid',
        'paidAt': 1799900000000,
        'canPay': false,
      });
      expect(payment.id, 'payment-1');
      expect(payment.installmentIndex, 2);
      expect(payment.label, 'Final payment');
      expect(payment.amountMinor, 12345);
      expect(payment.currency, 'usd');
      expect(payment.dueAt, DateTime.fromMillisecondsSinceEpoch(1800000000000));
      expect(payment.status, PaymentRecordStatus.paid);
      expect(
        payment.paidAt,
        DateTime.fromMillisecondsSinceEpoch(1799900000000),
      );
      expect(payment.canPay, isFalse);
      expect(payment.amount.label, '\$123.45');
      expect(PaymentRecord.fromJson({'canPay': true}).canPay, isTrue);
    });

    test('Payout parses every field and exposes its Money amount', () {
      final payout = Payout.fromJson({
        '_id': 'payout-1',
        'kind': 'forfeit',
        'amountMinor': 8500,
        'currency': 'usd',
        'status': 'held',
        'scheduledFor': 1800000000000,
        'paidAt': 1800000100000,
        'holdReason': 'dispute',
      });
      expect(payout.id, 'payout-1');
      expect(payout.kind, PayoutKind.forfeit);
      expect(payout.amountMinor, 8500);
      expect(payout.currency, 'usd');
      expect(payout.status, PayoutStatus.held);
      expect(
        payout.scheduledFor,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      expect(payout.paidAt, DateTime.fromMillisecondsSinceEpoch(1800000100000));
      expect(payout.holdReason, 'dispute');
      expect(payout.amount.label, '\$85.00');
    });

    test('RefundRecord parses every field and exposes its Money amount', () {
      final refund = RefundRecord.fromJson({
        '_id': 'refund-1',
        'paymentRecordId': 'payment-1',
        'amountMinor': 5000,
        'currency': 'usd',
        'status': 'succeeded',
        'reason': 'organizer_cancel',
        'stripeRefundId': 're_demo',
        'createdAt': 1800000000000,
      });
      expect(refund.id, 'refund-1');
      expect(refund.amountMinor, 5000);
      expect(refund.currency, 'usd');
      expect(refund.status, RefundStatus.succeeded);
      expect(refund.reason, RefundReason.organizerCancel);
      expect(
        refund.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      expect(refund.amount.label, '\$50.00');
    });

    test('RefundPreview parses every settlement field', () {
      final preview = RefundPreview.fromJson({
        'refundMinor': 5000,
        'forfeitedMinor': 5000,
        'artistPayoutMinor': 4500,
        'paidMinor': 10000,
        'shareBps': 5000,
        'template': 'standard',
        'cancelledBy': 'organizer',
      });
      expect(preview.refundMinor, 5000);
      expect(preview.forfeitedMinor, 5000);
      expect(preview.artistPayoutMinor, 4500);
      expect(preview.paidMinor, 10000);
      expect(preview.shareBps, 5000);
      expect(preview.template, CancellationTemplate.standard);
      expect(preview.cancelledBy, BookingSide.organizer);
    });

    test('CheckoutStatus parses both statuses and its booking id', () {
      final status = CheckoutStatus.fromJson({
        'bookingId': 'booking-1',
        'paymentStatus': 'checkout_open',
        'bookingStatus': 'awaiting_payment',
      });
      expect(status.bookingId, 'booking-1');
      expect(status.paymentStatus, PaymentRecordStatus.checkoutOpen);
      expect(status.bookingStatus, BookingStatus.awaitingPayment);
    });

    test(
      'Booking payment fields default leniently and drop non-string holds',
      () {
        for (final json in <Map<String, dynamic>>[
          const {},
          {
            'paidMinor': '500',
            'refundedMinor': false,
            'paymentDueAt': 'tomorrow',
            'payoutHoldReasons': 'dispute',
          },
        ]) {
          final booking = Booking.fromJson(json);
          expect(booking.paidMinor, 0);
          expect(booking.refundedMinor, 0);
          expect(booking.paymentDueAt, isNull);
          expect(booking.payoutHoldReasons, isEmpty);
        }
        final booking = Booking.fromJson({
          'paidMinor': 500,
          'refundedMinor': 100,
          'paymentDueAt': 1800000000000,
          'payoutHoldReasons': ['dispute', 7, null],
        });
        expect(booking.paidMinor, 500);
        expect(booking.refundedMinor, 100);
        expect(
          booking.paymentDueAt,
          DateTime.fromMillisecondsSinceEpoch(1800000000000),
        );
        expect(booking.payoutHoldReasons, ['dispute']);
      },
    );

    test('payment models tolerate missing and malformed fields', () {
      for (final json in <Map<String, dynamic>>[
        const {},
        {
          '_id': 7,
          'bookingId': false,
          'installmentIndex': 'first',
          'label': false,
          'amountMinor': 'free',
          'currency': 7,
          'dueAt': 'tomorrow',
          'paidAt': false,
          'scheduledFor': 'tomorrow',
          'createdAt': 'today',
          'holdReason': 7,
          'stripeAccountId': 'acct_demo',
          'chargesEnabled': 'true',
          'payoutsEnabled': 1,
          'detailsSubmitted': 'true',
          'requirementsDue': 'external_account',
          'canPay': 'true',
          'refundMinor': false,
          'forfeitedMinor': 'none',
          'artistPayoutMinor': 'none',
          'paidMinor': 'none',
          'shareBps': 'half',
        },
      ]) {
        final stripe = StripeAccountStatus.fromJson(json);
        expect(stripe.state, StripeAccountState.unknown);
        expect(stripe.hasAccount, isFalse);
        expect(stripe.chargesEnabled, isFalse);
        expect(stripe.payoutsEnabled, isFalse);
        expect(stripe.detailsSubmitted, isFalse);
        expect(stripe.requirementsDue, isEmpty);
        final payment = PaymentRecord.fromJson(json);
        expect(payment.id, '');
        expect(payment.installmentIndex, 0);
        expect(payment.label, '');
        expect(payment.amountMinor, 0);
        expect(payment.currency, '');
        expect(payment.dueAt, DateTime.fromMillisecondsSinceEpoch(0));
        expect(payment.status, PaymentRecordStatus.unknown);
        expect(payment.paidAt, isNull);
        expect(payment.canPay, isFalse);
        final payout = Payout.fromJson(json);
        expect(payout.id, '');
        expect(payout.kind, PayoutKind.completion);
        expect(payout.amountMinor, 0);
        expect(payout.currency, '');
        expect(payout.status, PayoutStatus.unknown);
        expect(payout.scheduledFor, DateTime.fromMillisecondsSinceEpoch(0));
        expect(payout.paidAt, isNull);
        expect(payout.holdReason, isNull);
        final refund = RefundRecord.fromJson(json);
        expect(refund.id, '');
        expect(refund.amountMinor, 0);
        expect(refund.currency, '');
        expect(refund.status, RefundStatus.unknown);
        expect(refund.reason, RefundReason.unknown);
        expect(refund.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
        final preview = RefundPreview.fromJson(json);
        expect(preview.refundMinor, 0);
        expect(preview.forfeitedMinor, 0);
        expect(preview.artistPayoutMinor, 0);
        expect(preview.paidMinor, 0);
        expect(preview.shareBps, 0);
        expect(preview.template, CancellationTemplate.standard);
        expect(preview.cancelledBy, BookingSide.artist);
        final checkout = CheckoutStatus.fromJson(json);
        expect(checkout.bookingId, '');
        expect(checkout.paymentStatus, PaymentRecordStatus.unknown);
        expect(checkout.bookingStatus, BookingStatus.unknown);
      }
      expect(
        StripeAccountStatus.fromJson({
          'requirementsDue': ['external_account', null, 7],
        }).requirementsDue,
        ['external_account'],
      );
      expect(PaymentRecord.fromJson({'paidAt': null}).paidAt, isNull);
    });
  });

  group('Phase 3b marketplace enum wire values', () {
    test('StripeAccountState round-trips and tolerates unknown values', () {
      expect(StripeAccountState.values.map((value) => value.wireValue), [
        'none',
        'onboarding',
        'restricted',
        'enabled',
        'unknown',
      ]);
      for (final value in StripeAccountState.values) {
        expect(StripeAccountState.fromWire(value.wireValue), value);
      }
      expect(StripeAccountState.fromWire(null), StripeAccountState.unknown);
      expect(StripeAccountState.fromWire('bogus'), StripeAccountState.unknown);
    });

    test('PaymentRecordStatus round-trips and tolerates unknown values', () {
      expect(PaymentRecordStatus.values.map((value) => value.wireValue), [
        'pending',
        'checkout_open',
        'paid',
        'failed',
        'expired',
        'refunded',
        'partially_refunded',
        'unknown',
      ]);
      for (final value in PaymentRecordStatus.values) {
        expect(PaymentRecordStatus.fromWire(value.wireValue), value);
      }
      expect(PaymentRecordStatus.fromWire(null), PaymentRecordStatus.unknown);
      expect(
        PaymentRecordStatus.fromWire('bogus'),
        PaymentRecordStatus.unknown,
      );
    });

    test(
      'PaymentRecordStatus.isOpen includes retryable failures and expiry',
      () {
        for (final status in [
          PaymentRecordStatus.pending,
          PaymentRecordStatus.checkoutOpen,
          PaymentRecordStatus.failed,
          PaymentRecordStatus.expired,
        ]) {
          expect(status.isOpen, isTrue);
        }
        for (final status in [
          PaymentRecordStatus.paid,
          PaymentRecordStatus.refunded,
          PaymentRecordStatus.partiallyRefunded,
          PaymentRecordStatus.unknown,
        ]) {
          expect(status.isOpen, isFalse);
        }
      },
    );

    test('PayoutStatus round-trips and tolerates unknown values', () {
      expect(PayoutStatus.values.map((value) => value.wireValue), [
        'scheduled',
        'held',
        'processing',
        'paid',
        'failed',
        'reversed',
        'unknown',
      ]);
      for (final value in PayoutStatus.values) {
        expect(PayoutStatus.fromWire(value.wireValue), value);
      }
      expect(PayoutStatus.fromWire(null), PayoutStatus.unknown);
      expect(PayoutStatus.fromWire('bogus'), PayoutStatus.unknown);
    });

    test(
      'PayoutKind round-trips and defaults unknown values to completion',
      () {
        expect(PayoutKind.values.map((value) => value.wireValue), [
          'completion',
          'forfeit',
        ]);
        for (final value in PayoutKind.values) {
          expect(PayoutKind.fromWire(value.wireValue), value);
        }
        expect(PayoutKind.fromWire(null), PayoutKind.completion);
        expect(PayoutKind.fromWire('bogus'), PayoutKind.completion);
      },
    );

    test('RefundStatus round-trips and tolerates unknown values', () {
      expect(RefundStatus.values.map((value) => value.wireValue), [
        'pending',
        'succeeded',
        'failed',
        'unknown',
      ]);
      for (final value in RefundStatus.values) {
        expect(RefundStatus.fromWire(value.wireValue), value);
      }
      expect(RefundStatus.fromWire(null), RefundStatus.unknown);
      expect(RefundStatus.fromWire('bogus'), RefundStatus.unknown);
    });

    test('RefundReason round-trips and tolerates unknown values', () {
      expect(RefundReason.values.map((value) => value.wireValue), [
        'organizer_cancel',
        'artist_cancel',
        'force_majeure',
        'admin',
        'dispute',
        'late_payment',
        'unknown',
      ]);
      for (final value in RefundReason.values) {
        expect(RefundReason.fromWire(value.wireValue), value);
      }
      expect(RefundReason.fromWire(null), RefundReason.unknown);
      expect(RefundReason.fromWire('bogus'), RefundReason.unknown);
    });
  });

  group('Phase 3 marketplace enum wire values', () {
    test('BookingStatus round-trips the exact wire values and labels', () {
      expect(BookingStatus.values.map((status) => status.wireValue), [
        'offer_sent',
        'artist_accepted',
        'awaiting_payment',
        'confirmed',
        'completed',
        'paid',
        'cancelled_by_organizer',
        'cancelled_by_artist',
        'force_majeure',
        'disputed',
        'refunded',
        'declined',
        'expired',
        'withdrawn',
        'unknown',
      ]);
      expect(BookingStatus.values.map((status) => status.label), [
        'Offer sent',
        'Artist accepted',
        'Awaiting payment',
        'Confirmed',
        'Completed',
        'Paid',
        'Cancelled by organizer',
        'Cancelled by artist',
        'Force majeure',
        'Disputed',
        'Refunded',
        'Declined',
        'Expired',
        'Withdrawn',
        'Unknown',
      ]);
      for (final status in BookingStatus.values) {
        expect(BookingStatus.fromWire(status.wireValue), status);
      }
      expect(BookingStatus.fromWire('something_new'), BookingStatus.unknown);
      expect(BookingStatus.fromWire(null), BookingStatus.unknown);
    });

    test('BookingStatus active and live sets match the backend', () {
      const active = {
        BookingStatus.offerSent,
        BookingStatus.artistAccepted,
        BookingStatus.awaitingPayment,
        BookingStatus.confirmed,
        BookingStatus.completed,
        BookingStatus.paid,
        BookingStatus.disputed,
      };
      const live = {
        BookingStatus.confirmed,
        BookingStatus.completed,
        BookingStatus.paid,
      };
      for (final status in BookingStatus.values) {
        expect(
          status.isActive,
          active.contains(status),
          reason: status.wireValue,
        );
        expect(status.isLive, live.contains(status), reason: status.wireValue);
      }
    });

    test('CancellationTemplate round-trips and defaults to standard', () {
      for (final template in CancellationTemplate.values) {
        expect(CancellationTemplate.fromWire(template.wireValue), template);
      }
      expect(
        CancellationTemplate.fromWire('something_new'),
        CancellationTemplate.standard,
      );
      expect(
        CancellationTemplate.fromWire(null),
        CancellationTemplate.standard,
      );
      expect(CancellationTemplate.values.map((value) => value.label), [
        'Flexible',
        'Standard',
        'Strict',
      ]);
      expect(CancellationTemplate.values.map((value) => value.description), [
        'Full refund up to 48 hours before the show.',
        'Full refund more than 14 days out, 50% refund 7-14 days out, no refund within 7 days.',
        'No refund within 14 days of the show.',
      ]);
    });

    test(
      'booking side, cancellation actor, and response use safe fallbacks',
      () {
        for (final value in BookingSide.values) {
          expect(BookingSide.fromWire(value.wireValue), value);
        }
        for (final value in BookingCancelledBy.values) {
          expect(BookingCancelledBy.fromWire(value.wireValue), value);
        }
        for (final value in OfferResponse.values) {
          expect(OfferResponse.fromWire(value.wireValue), value);
        }
        for (final value in [null, 'something_new', 42]) {
          expect(BookingSide.fromWire(value), BookingSide.artist);
          expect(BookingCancelledBy.fromWire(value), BookingCancelledBy.system);
          expect(OfferResponse.fromWire(value), OfferResponse.withdrawn);
        }
      },
    );
  });

  group('Gig marketplace ownership', () {
    const gigJson = {
      '_id': 'gig-1',
      'slug': 'friday-showcase',
      'title': 'Friday Showcase',
      'venueId': 'venue-1',
      'price': 0,
      'startsAt': 1800000000000,
      'doorsAt': 1799996400000,
      'doorsTime': '7PM / 8PM',
      'flyKey': 'paper',
      'lineup': ['band-1'],
      'genres': ['indie'],
      'desc': 'An evening of local bands.',
      'ticketing': 'rsvp',
      'cap': '150',
    };

    test('parses organization ownership and preserves it when copied', () {
      final gig = Gig.fromJson({
        ...gigJson,
        'ownerKind': 'organization',
        'opportunityId': 'opportunity-1',
      });
      expect(gig.ownerKind, GigOwnerKind.organization);
      expect(gig.opportunityId, 'opportunity-1');
      final copy = gig.copyWith(going: 12);
      expect(copy.ownerKind, GigOwnerKind.organization);
      expect(copy.opportunityId, 'opportunity-1');
      expect(gig.sameListing(copy), isTrue);
      expect(
        gig.sameListing(gig.copyWith(ownerKind: GigOwnerKind.band)),
        isFalse,
      );
      expect(
        gig.sameListing(gig.copyWith(opportunityId: 'opportunity-2')),
        isFalse,
      );
      final relabeled = gig.relabeled(now: gig.startsAt);
      expect(relabeled.ownerKind, GigOwnerKind.organization);
      expect(relabeled.opportunityId, 'opportunity-1');
    });

    test(
      'defaults legacy payloads to band ownership without an opportunity',
      () {
        final gig = Gig.fromJson(gigJson);
        expect(gig.ownerKind, GigOwnerKind.band);
        expect(gig.opportunityId, isNull);
        expect(gig.tix, Ticketing.rsvp);
        for (final value in GigOwnerKind.values) {
          expect(GigOwnerKind.fromWire(value.wireValue), value);
        }
        for (final value in [null, 'something_new', 42]) {
          final malformed = Gig.fromJson({
            ...gigJson,
            'ownerKind': value,
            'opportunityId': 42,
          });
          expect(malformed.ownerKind, GigOwnerKind.band);
          expect(malformed.opportunityId, isNull);
        }
      },
    );

    test('unknown, missing, and null ticketing fall back to RSVP', () {
      for (final value in [null, 'something_else', 42]) {
        expect(
          Gig.fromJson({...gigJson, 'ticketing': value}).tix,
          Ticketing.rsvp,
        );
      }
      final withoutTicketing = {...gigJson}..remove('ticketing');
      expect(Gig.fromJson(withoutTicketing).tix, Ticketing.rsvp);
      expect(
        Gig.fromJson({...gigJson, 'ticketing': 'external'}).tix,
        Ticketing.external,
      );
    });
  });

  group('marketplace reviews', () {
    const publicReviewJson = {
      'reviewId': 'review-1',
      'rating': 5,
      'categories': ['communication', 'sound'],
      'text': 'Great show and clear communication.',
      'submittedAt': 1800010000000,
      'monthLabel': 'January 2027',
      'opportunityTitle': 'Friday Showcase',
    };

    test('PublicReview parses both counterparty listing shapes', () {
      for (final counterparty in [
        {'organizationName': 'Signal Collective'},
        {'bandName': 'The Night Shifts'},
      ]) {
        final review = PublicReview.fromJson({
          ...publicReviewJson,
          ...counterparty,
        });
        expect(review.reviewId, 'review-1');
        expect(review.rating, 5);
        expect(review.categories, ['communication', 'sound']);
        expect(review.text, 'Great show and clear communication.');
        expect(
          review.submittedAt,
          DateTime.fromMillisecondsSinceEpoch(1800010000000),
        );
        expect(review.monthLabel, 'January 2027');
        expect(review.opportunityTitle, 'Friday Showcase');
        expect(review.counterpartyName, counterparty.values.single);
      }
      expect(
        PublicReview.fromJson({
          ...publicReviewJson,
          'organizationName': 'Signal Collective',
          'bandName': 'The Night Shifts',
        }).counterpartyName,
        'Signal Collective',
      );
      expect(
        PublicReview.fromJson({
          ...publicReviewJson,
          'organizationName': 42,
          'bandName': 'The Night Shifts',
        }).counterpartyName,
        'The Night Shifts',
      );
      expect(PublicReview.fromJson(publicReviewJson).counterpartyName, '');
    });

    test('BookingReviews parses both reviews with their distinct sides', () {
      final reviews = BookingReviews.fromJson({
        'mine': {
          'reviewId': 'review-1',
          'authorSide': 'organizer',
          'rating': 5,
          'categories': ['professionalism', 'punctuality'],
          'text': 'Ready on time and sounded great.',
          'submittedAt': 1800010000000,
          'visibleAt': 1800020000000,
        },
        'theirs': {
          'reviewId': 'review-2',
          'authorSide': 'artist',
          'rating': 4,
          'categories': ['hospitality', 'payment'],
          'text': 'Welcoming hosts and prompt payment.',
          'submittedAt': 1800020000000,
          'visibleAt': null,
        },
        'windowClosesAt': 1801000000000,
        'canSubmit': false,
      });
      final mine = reviews.mine!;
      expect(mine.reviewId, 'review-1');
      expect(mine.authorSide, BookingSide.organizer);
      expect(mine.rating, 5);
      expect(mine.categories, ['professionalism', 'punctuality']);
      expect(mine.text, 'Ready on time and sounded great.');
      expect(
        mine.submittedAt,
        DateTime.fromMillisecondsSinceEpoch(1800010000000),
      );
      expect(
        mine.visibleAt,
        DateTime.fromMillisecondsSinceEpoch(1800020000000),
      );
      final theirs = reviews.theirs!;
      expect(theirs.reviewId, 'review-2');
      expect(theirs.authorSide, BookingSide.artist);
      expect(theirs.rating, 4);
      expect(theirs.categories, ['hospitality', 'payment']);
      expect(theirs.text, 'Welcoming hosts and prompt payment.');
      expect(
        theirs.submittedAt,
        DateTime.fromMillisecondsSinceEpoch(1800020000000),
      );
      expect(theirs.visibleAt, isNull);
      expect(
        reviews.windowClosesAt,
        DateTime.fromMillisecondsSinceEpoch(1801000000000),
      );
      expect(reviews.canSubmit, isFalse);
    });

    test(
      'BookingReviews preserves null reviews before either side submits',
      () {
        final reviews = BookingReviews.fromJson({
          'mine': null,
          'theirs': null,
          'windowClosesAt': 1801000000000,
          'canSubmit': true,
        });
        expect(reviews.mine, isNull);
        expect(reviews.theirs, isNull);
        expect(
          reviews.windowClosesAt,
          DateTime.fromMillisecondsSinceEpoch(1801000000000),
        );
        expect(reviews.canSubmit, isTrue);
      },
    );

    test('review parsers tolerate missing and malformed fields', () {
      final review = Review.fromJson({
        'rating': 'five',
        'categories': ['sound', 42, null],
        'visibleAt': 'tomorrow',
      });
      expect(review.reviewId, '');
      expect(review.authorSide, BookingSide.artist);
      expect(review.rating, 0);
      expect(review.categories, ['sound']);
      expect(review.text, '');
      expect(review.submittedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(review.visibleAt, isNull);
      final reviews = BookingReviews.fromJson({
        'mine': 42,
        'theirs': <Object?>[],
        'canSubmit': 'true',
      });
      expect(reviews.mine, isNull);
      expect(reviews.theirs, isNull);
      expect(reviews.canSubmit, isFalse);
      expect(reviews.windowClosesAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(PublicReview.fromJson(const {}).categories, isEmpty);
    });

    test('review categories retain the backend order', () {
      expect(reviewCategories, [
        'professionalism',
        'punctuality',
        'communication',
        'sound',
        'hospitality',
        'payment',
      ]);
    });
  });

  group('ReviewSummary', () {
    const summaryJson = {
      'count': 4,
      'mean': 4.75,
      'completedBookings': 6,
      'cancellations': 1,
    };
    const bandJson = {
      '_id': 'band-1',
      'name': 'The Night Shifts',
      'genres': ['indie'],
      'area': 'Oakland',
      'colorHex': '#1435F0',
      'initials': 'NS',
      'followerCount': 218,
      'bio': 'A Bay Area band.',
    };

    test('parses counts and a fractional mean', () {
      final summary = ReviewSummary.fromJson(summaryJson);
      expect(summary.count, 4);
      expect(summary.mean, 4.75);
      expect(summary.completedBookings, 6);
      expect(summary.cancellations, 1);
    });

    test('null, empty, and malformed summaries default to zero', () {
      for (final json in <Map<String, dynamic>?>[
        null,
        const {},
        {
          'count': 'four',
          'mean': 'five',
          'completedBookings': false,
          'cancellations': <Object?>[],
        },
      ]) {
        final summary = ReviewSummary.fromJson(json);
        expect(summary.count, 0);
        expect(summary.mean, 0);
        expect(summary.completedBookings, 0);
        expect(summary.cancellations, 0);
      }
    });

    test('Band and Organization accept summaries when present', () {
      final band = Band.fromJson({...bandJson, 'reviewSummary': summaryJson});
      final organization = Organization.fromJson({
        'reviewSummary': summaryJson,
      });
      for (final summary in [
        band.reviewSummary!,
        organization.reviewSummary!,
      ]) {
        expect(summary.count, 4);
        expect(summary.mean, 4.75);
        expect(summary.completedBookings, 6);
        expect(summary.cancellations, 1);
      }
    });

    test(
      'Band and Organization tolerate payloads without review summaries',
      () {
        for (final json in <Map<String, dynamic>>[
          const {},
          {'reviewSummary': null},
          {'reviewSummary': 'not a map'},
        ]) {
          expect(Band.fromJson({...bandJson, ...json}).reviewSummary, isNull);
          expect(Organization.fromJson(json).reviewSummary, isNull);
        }
      },
    );

    test(
      'Band preserves profile review summaries across copies and feed merges',
      () {
        final band = Band.fromJson({...bandJson, 'reviewSummary': summaryJson});
        final replacement = ReviewSummary.fromJson({
          ...summaryJson,
          'count': 5,
        });
        expect(
          band.copyWith(name: 'Updated name').reviewSummary,
          same(band.reviewSummary),
        );
        expect(
          band.copyWith(reviewSummary: replacement).reviewSummary,
          same(replacement),
        );
        final feedBand = Band.fromJson({...bandJson, 'followerCount': 300});
        for (final summary in [
          feedBand,
          feedBand.copyWith(reviewSummary: replacement),
        ]) {
          final merged = band.mergeSummary(summary, upcoming: ['gig-1']);
          expect(merged.reviewSummary, same(band.reviewSummary));
          expect(merged.followers, 300);
          expect(merged.upcoming, ['gig-1']);
        }
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
