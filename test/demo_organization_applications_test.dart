import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
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

  test(
    'DemoRepository stamps and preserves organizer agreement acceptance',
    () async {
      final repository = DemoRepository(auth: FakeAuthService());
      final saved = await repository.saveOrganizationApplicationDraft(
        orgName: 'Signal Collective',
        orgType: OrganizationType.promoter,
        contactName: 'Earplug Fan',
        businessEmail: 'fan@example.com',
      );
      expect(
        (await repository.myOrganizationApplication())!
            .organizerAgreementAcceptedAt,
        isNull,
      );

      final submittedRevision = await repository.submitOrganizationApplication(
        applicationId: saved.applicationId,
        expectedRevision: saved.revision,
        organizerAgreementAccepted: true,
      );
      final submitted = (await repository.myOrganizationApplication())!;
      expect(submitted.status, OrganizationApplicationStatus.submitted);
      expect(submitted.revision, submittedRevision);
      expect(submitted.organizerAgreementAcceptedAt, isNotNull);
      expect(submitted.organizerAgreementAcceptedAt, submitted.updatedAt);

      await repository.submitOrganizationApplication(
        applicationId: saved.applicationId,
        expectedRevision: submittedRevision,
      );
      expect(
        (await repository.myOrganizationApplication())!
            .organizerAgreementAcceptedAt,
        submitted.organizerAgreementAcceptedAt,
      );
    },
  );
}
