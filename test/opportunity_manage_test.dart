import 'package:earplug/app_state.dart';
import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/opportunity_applicants.dart';
import 'package:earplug/screens/org_opportunities.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  testWidgets('opportunities group drafts and open listings with counts', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );
    final openSection = find.byKey(const ValueKey('org-opps-section-OPEN'));
    final draftsSection = find.byKey(const ValueKey('org-opps-section-DRAFTS'));
    final openCard = find.byKey(const ValueKey('org-opp-opp1'));
    final draftCard = find.byKey(const ValueKey('org-opp-opp2'));

    expect(
      tester
          .widget<SectionBar>(
            find.descendant(of: openSection, matching: find.byType(SectionBar)),
          )
          .count,
      2,
    );
    expect(
      tester
          .widget<SectionBar>(
            find.descendant(
              of: draftsSection,
              matching: find.byType(SectionBar),
            ),
          )
          .label,
      'DRAFTS',
    );
    expect(
      find.descendant(of: openSection, matching: openCard),
      findsOneWidget,
    );
    expect(
      find.descendant(of: draftsSection, matching: draftCard),
      findsOneWidget,
    );
    expect(
      find.descendant(of: openCard, matching: find.text('2 applied')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openCard,
        matching: find.text(DemoData.opportunities['opp1']!.title),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openCard,
        matching: find.text(r'Headliner $300.00 · Support $150.00'),
      ),
      findsOneWidget,
    );
    harness.app.dispose();
  });

  testWidgets('new opportunity opens the editor with the new parameter', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await tester.tap(find.byKey(const Key('org-opps-new')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'new');
    harness.app.dispose();
  });

  testWidgets('close applications moves the opportunity to CLOSED', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await _chooseOpportunityAction(tester, 'opp1', 'CLOSE APPLICATIONS');

    final card = find.byKey(const ValueKey('org-opp-opp1'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final closedSection = find.byKey(const ValueKey('org-opps-section-CLOSED'));
    expect(find.descendant(of: closedSection, matching: card), findsOneWidget);
    expect(
      tester
          .widget<SectionBar>(
            find.descendant(
              of: closedSection,
              matching: find.byType(SectionBar),
            ),
          )
          .label,
      'CLOSED',
    );
    final opportunities = await harness.app.repository.manageOpportunities(
      'org1',
    );
    expect(
      opportunities
          .singleWhere((opportunity) => opportunity.id == 'opp1')
          .status,
      OpportunityStatus.applicationsClosed,
    );
    expect(harness.app.toast, 'Applications closed.');
    harness.app.dispose();
  });

  testWidgets('delete draft removes the opportunity without another dialog', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await _chooseOpportunityAction(tester, 'opp2', 'DELETE DRAFT');

    expect(find.byKey(const ValueKey('org-opp-opp2')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(harness.app.toast, 'Draft deleted.');
    harness.app.dispose();
  });

  testWidgets('duplicate adds a draft with no active applications', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await _chooseOpportunityAction(tester, 'opp1', 'DUPLICATE');

    final duplicate = harness.app
        .opportunitiesFor('org1')
        .singleWhere(
          (opportunity) => !DemoData.opportunities.containsKey(opportunity.id),
        );
    expect(duplicate.status, OpportunityStatus.draft);
    expect(duplicate.applicationCount, 0);
    expect(find.byKey(ValueKey('org-opp-${duplicate.id}')), findsOneWidget);
    expect(harness.app.toast, 'Opportunity duplicated.');
    harness.app.dispose();
  });

  testWidgets('cancel opportunity requires confirmation', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );

    await _chooseOpportunityAction(tester, 'opp1', 'CANCEL…');
    expect(find.text('Cancel opportunity?'), findsOneWidget);
    expect(
      (await harness.app.repository.opportunity('opp1'))!.status,
      OpportunityStatus.open,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
    await tester.pumpAndSettle();

    final opportunity = await harness.app.repository.opportunity('opp1');
    expect(opportunity!.status, OpportunityStatus.cancelled);
    expect(opportunity.applicationCount, 0);
    expect(harness.app.toast, 'Opportunity cancelled.');
    harness.app.dispose();
  });

  testWidgets('reopen uses a picked deadline and returns to OPEN', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OrgOpportunitiesScreen(),
    );
    await _chooseOpportunityAction(tester, 'opp1', 'CLOSE APPLICATIONS');

    await _chooseOpportunityAction(tester, 'opp1', 'REOPEN');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final opportunity = await harness.app.repository.opportunity('opp1');
    expect(opportunity!.status, OpportunityStatus.open);
    expect(
      DateUtils.isSameDay(opportunity.applicationsCloseAt, DateTime.now()),
      isTrue,
    );
    expect(harness.app.toast, 'Opportunity reopened.');
    harness.app.dispose();
  });

  testWidgets('applicants show both bands and the matching slot guarantees', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );
    final support = find.byKey(const ValueKey('applicant-app1'));
    final headliner = find.byKey(const ValueKey('applicant-app2'));

    expect(support, findsOneWidget);
    expect(headliner, findsOneWidget);
    expect(
      find.descendant(of: support, matching: find.text(r'Slot $150.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: headliner, matching: find.text(r'Slot $300.00')),
      findsOneWidget,
    );
    expect(find.text('2 applicants'), findsOneWidget);
    expect(find.text('We can bring 40 people.'), findsOneWidget);
    expect(
      find.text(DemoData.organizationMembers[DemoData.demoUserId]!.email!),
      findsOneWidget,
    );
    harness.app.dispose();
  });

  testWidgets('shortlisting updates the applicant status pill', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app1-shortlist')));
    await tester.pumpAndSettle();

    expect(_applicantPill(tester, 'app1').label, 'Shortlisted');
    expect(
      find.byKey(const ValueKey('applicant-app1-shortlist')),
      findsNothing,
    );
    expect(find.text('2 applicants'), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets(
    'declining refreshes the status pill and active applicant count',
    (tester) async {
      final harness = await _pumpOrganizerScreen(
        tester,
        const OpportunityApplicantsScreen(opportunityId: 'opp1'),
      );
      expect(find.text('2 applicants'), findsOneWidget);
      final decline = find.byKey(const ValueKey('applicant-app2-decline'));
      await tester.ensureVisible(decline);
      await tester.tap(decline);
      await tester.pumpAndSettle();
      expect(find.text('Decline this applicant?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
      await tester.pumpAndSettle();

      expect(_applicantPill(tester, 'app2').label, 'Declined');
      expect(find.text('1 applicants'), findsOneWidget);
      expect(find.text('2 applicants'), findsNothing);
      expect(
        find.byKey(const ValueKey('applicant-app2-decline')),
        findsNothing,
      );
      harness.app.dispose();
    },
  );

  testWidgets('keeping an applicant cancels the decline', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app1-decline')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
    await tester.pumpAndSettle();

    expect(_applicantPill(tester, 'app1').label, 'Submitted');
    expect(find.text('2 applicants'), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets('starting review preserves shortlist and decline actions', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.byKey(const ValueKey('applicant-app1-review')));
    await tester.pumpAndSettle();

    expect(_applicantPill(tester, 'app1').label, 'Under review');
    expect(find.byKey(const ValueKey('applicant-app1-review')), findsNothing);
    expect(
      find.byKey(const ValueKey('applicant-app1-shortlist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('applicant-app1-decline')),
      findsOneWidget,
    );
    harness.app.dispose();
  });

  testWidgets('slot chips filter applicants and ALL restores both', (
    tester,
  ) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    final support = find.byKey(const ValueKey('applicants-slot-opp1-support'));
    await tester.tap(support);
    await tester.pumpAndSettle();
    expect(tester.widget<EpChip>(support).active, isTrue);
    expect(find.byKey(const ValueKey('applicant-app1')), findsOneWidget);
    expect(find.byKey(const ValueKey('applicant-app2')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('applicants-slot-opp1-headliner')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('applicant-app1')), findsNothing);
    expect(find.byKey(const ValueKey('applicant-app2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('applicants-slot-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('applicant-app1')), findsOneWidget);
    expect(find.byKey(const ValueKey('applicant-app2')), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets('tapping the band name opens its profile', (tester) async {
    final harness = await _pumpOrganizerScreen(
      tester,
      const OpportunityApplicantsScreen(opportunityId: 'opp1'),
    );

    await tester.tap(find.text(DemoData.bands['b1']!.name));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.band);
    expect(harness.app.current.param, 'b1');
    harness.app.dispose();
  });

  for (final role in [OrganizationRole.finance, OrganizationRole.door]) {
    testWidgets('${role.name} members can read applicants without actions', (
      tester,
    ) async {
      final harness = await _pumpOrganizerScreen(
        tester,
        const OpportunityApplicantsScreen(opportunityId: 'opp1'),
      );
      harness.app.myOrganizations = [
        OrganizationMembership(
          organization: DemoData.organizations['org1']!,
          role: role,
        ),
      ];
      await enterOrganizer(tester, harness, 'org1');

      expect(find.byKey(const ValueKey('applicant-app1')), findsOneWidget);
      expect(find.byKey(const ValueKey('applicant-app2')), findsOneWidget);
      expect(find.text('START REVIEW'), findsNothing);
      expect(find.text('SHORTLIST'), findsNothing);
      expect(find.text('DECLINE'), findsNothing);
      harness.app.dispose();
    });
  }

  for (final screen in const [
    OrgOpportunitiesScreen(),
    OpportunityApplicantsScreen(opportunityId: 'opp1'),
  ]) {
    testWidgets('${screen.runtimeType} has no text fields inside cards', (
      tester,
    ) async {
      final harness = await _pumpOrganizerScreen(tester, screen);

      expect(find.byType(EpCard), findsWidgets);
      expect(
        find.ancestor(
          of: find.byType(TextField),
          matching: find.byType(EpCard),
        ),
        findsNothing,
      );
      harness.app.dispose();
    });
  }
}

Future<AppHarness> _pumpOrganizerScreen(
  WidgetTester tester,
  Widget screen,
) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final repository = DemoRepository(auth: auth);
  final app = AppState(repository: repository, auth: auth);
  final picker = FakeMediaPicker();
  final media = BandMediaController(
    repository: repository,
    picker: picker,
    uploader: app.mediaUploader,
    say: app.say,
  );
  app.attachMediaController(media);
  addTearDown(media.dispose);
  final harness = AppHarness(
    app: app,
    auth: auth,
    media: media,
    picker: picker,
    geocoding: FakeGeocodingService(),
  );

  // Unlike pumpApp, this wrapper leaves disposal to each test body. Providing
  // the existing app by value prevents the provider from disposing it twice.
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  app.switchToOrganization('org1');
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildEpTheme(),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await enterOrganizer(tester, harness, 'org1');
  return harness;
}

Future<void> _chooseOpportunityAction(
  WidgetTester tester,
  String opportunityId,
  String action,
) async {
  final card = find.byKey(ValueKey('org-opp-$opportunityId'));
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

StatusPill _applicantPill(WidgetTester tester, String applicationId) =>
    tester.widget<StatusPill>(
      find.descendant(
        of: find.byKey(ValueKey('applicant-$applicationId')),
        matching: find.byType(StatusPill),
      ),
    );
