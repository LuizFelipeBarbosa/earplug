import 'package:earplug/data/demo_repository.dart';
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
}
