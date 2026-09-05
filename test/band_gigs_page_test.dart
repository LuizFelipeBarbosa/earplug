import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_manager.dart';
import 'package:earplug/screens/opportunity_detail.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

void main() {
  testWidgets(
    'public invitations appear once and retain the invitation label',
    (tester) async {
      final harness = await pumpApp(tester, home: const RootShell());
      await _signInBand(tester, harness);
      await harness.app.repository.inviteBandToOpportunity(
        opportunityId: 'opp1',
        bandId: 'b1',
      );
      harness.app.resetTo(Screen.gigMgr);
      await harness.app.refreshBrowse();
      await tester.pumpAndSettle();

      expect(
        harness.app.browse.invited.any((item) => item.opportunity.id == 'opp1'),
        isTrue,
      );
      expect(
        harness.app.browse.items.any((item) => item.opportunity.id == 'opp1'),
        isTrue,
      );
      final card = find.byKey(const Key('opp-card-opp1'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('INVITED')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opportunity back returns to the Gigs page through app navigation',
    (tester) async {
      final harness = await pumpApp(tester, home: const RootShell());
      await _signInBand(tester, harness);
      harness.app.resetTo(Screen.gigMgr);
      harness.app.openOpportunity('friday-night-live');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.gigMgr);
      expect(find.byType(GigManagerScreen), findsOneWidget);
    },
  );

  testWidgets(
    'apply selects the only administered band when another band is active',
    (tester) async {
      final harness = await pumpApp(tester, home: const RootShell());
      await _signInNonAdminMember(tester, harness);
      await harness.app.repository.withdrawApplication('app1');
      await harness.app.repository.withdrawApplication('app2');
      harness.app.openOpportunity('friday-night-live');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('opp-detail-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('opp-apply-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Choose a band you manage to apply.'), findsNothing);
      final applications = await harness.app.repository.myApplications('b1');
      expect(
        applications.where((row) => row.application.status.isActive),
        hasLength(1),
      );
      expect(harness.app.toast, 'Application sent');
    },
  );

  testWidgets('opportunity apply action stays above the band tab bar', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const RootShell());
    await _signInBand(tester, harness);
    harness.app.openOpportunity('private-preview');
    await tester.pumpAndSettle();

    expect(find.byType(OpportunityDetailScreen), findsOneWidget);
    expect(find.byType(BandTabBar), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('opp-detail-apply'))).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(BandTabBar)).top),
    );
  });

  testWidgets('non-admin members can browse gigs without write actions', (
    tester,
  ) async {
    final harness = await _pumpScreen(
      tester,
      home: const Scaffold(
        body: GigManagerScreen(),
        bottomNavigationBar: BandTabBar(),
      ),
    );
    await _signInNonAdminMember(tester, harness);
    expect(harness.app.isAdminOf('b2'), isFalse);
    expect(harness.app.gigWritePolicy, isTrue);

    await tester.tap(find.byIcon(Icons.table_rows_outlined));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.gigMgr);
    for (final segment in ['open', 'applied', 'booked', 'past']) {
      expect(
        find.widgetWithText(EpChip, segment.toUpperCase()),
        findsOneWidget,
      );
    }
    expect(find.text('+ NEW GIG'), findsNothing);
    expect(find.byKey(const Key('opp-card-opp1')), findsOneWidget);

    // Seed a legacy draft so the member's write checks cover a visible row.
    final repository = harness.app.repository as DemoRepository;
    final draft = await repository.createGigDraft('b2');
    await harness.app.refreshManagedGigs();
    await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
    await tester.pumpAndSettle();

    for (final writesEnabled in [true, false]) {
      repository.demoBandGigWrites = writesEnabled;
      await harness.app.refreshGigWritePolicy();
      await tester.pumpAndSettle();

      expect(find.byType(GhostDraftRow), findsOneWidget);
      expect(
        tester.widget<GhostDraftRow>(find.byType(GhostDraftRow)).onResume,
        isNull,
      );
      expect(find.text('RESUME →'), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.byKey(Key('gig-actions-${draft.id}')), findsNothing);
      expect(find.byKey(Key('gig-edit-${draft.id}')), findsNothing);
      expect(find.byKey(Key('gig-preview-${draft.id}')), findsNothing);
      expect(find.byKey(Key('gig-delete-${draft.id}')), findsNothing);
    }
    harness.app.dispose();
  });

  testWidgets('OPEN shows invitations first and excludes drafts', (
    tester,
  ) async {
    final harness = await _pumpScreen(
      tester,
      home: const Scaffold(body: GigManagerScreen()),
    );
    await _signInBand(tester, harness);

    expect(
      tester.widget<EpChip>(find.byKey(const Key('band-gigs-seg-open'))).active,
      isTrue,
    );
    expect(find.byKey(const Key('opp-card-opp1')), findsOneWidget);
    expect(find.byKey(const Key('opp-card-opp3')), findsOneWidget);
    expect(find.byKey(const Key('opp-card-opp2')), findsNothing);
    expect(find.text('Patio Sessions'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('opp-card-opp3')),
        matching: find.text('INVITED'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('opp-card-opp3'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('opp-card-opp1'))).dy),
    );
    expect(find.text(r'HEADLINER · $300.00'), findsOneWidget);
    expect(find.byKey(const Key('band-gigs-load-more')), findsNothing);
    expectNoFieldInCard(tester);
    harness.app.dispose();
  });

  testWidgets('an opportunity card opens its slug in app navigation', (
    tester,
  ) async {
    final harness = await _pumpScreen(
      tester,
      home: const Scaffold(body: GigManagerScreen()),
    );
    await _signInBand(tester, harness);

    await tester.tap(find.byKey(const Key('opp-card-opp1')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.opportunityDetail);
    expect(harness.app.current.param, 'friday-night-live');
    harness.app.dispose();
  });

  testWidgets('APPLIED confirms withdrawal and refreshes the browse status', (
    tester,
  ) async {
    final harness = await _pumpScreen(
      tester,
      home: const Scaffold(body: GigManagerScreen()),
    );
    await _signInBand(tester, harness);
    await tester.tap(find.byKey(const Key('band-gigs-seg-applied')));
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('band-app-app1'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('SUBMITTED')),
      findsOneWidget,
    );
    expect(find.textContaining('SUPPORT'), findsOneWidget);
    await tester.tap(find.byKey(const Key('band-app-app1-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KEEP'));
    await tester.pumpAndSettle();
    expect(
      harness.app.myApplications.single.application.status,
      ArtistApplicationStatus.submitted,
    );

    await _withdrawFromApplied(tester);

    expect(
      harness.app.myApplications.single.application.status,
      ArtistApplicationStatus.withdrawn,
    );
    expect(find.byKey(const Key('band-app-app1-withdraw')), findsNothing);
    expect(
      find.descendant(of: row, matching: find.text('WITHDRAWN')),
      findsOneWidget,
    );
    expect(
      harness.app.browse.items.single.myApplicationStatus?.isActive ?? false,
      isFalse,
    );
    harness.app.dispose();
  });

  testWidgets(
    'write policy hides new gig and leaves only deletion for drafts',
    (tester) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(body: GigManagerScreen()),
      );
      await _signInBand(tester, harness);
      final repository = harness.app.repository as DemoRepository;
      final draft = await repository.createGigDraft('b1');
      await harness.app.refreshManagedGigs();
      expect(find.text('+ NEW GIG'), findsOneWidget);

      repository.demoBandGigWrites = false;
      await harness.app.refreshGigWritePolicy();
      await tester.pumpAndSettle();
      expect(find.text('+ NEW GIG'), findsNothing);

      await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
      await tester.pumpAndSettle();
      expect(find.textContaining('LEGACY DRAFTS'), findsOneWidget);
      expect(find.text('Drafts are read-only now'), findsOneWidget);
      expect(
        tester.widget<GhostDraftRow>(find.byType(GhostDraftRow)).onResume,
        isNull,
      );
      expect(find.byKey(Key('gig-preview-${draft.id}')), findsNothing);
      expect(find.byKey(Key('gig-edit-${draft.id}')), findsNothing);
      expect(find.byKey(Key('gig-actions-${draft.id}')), findsNothing);

      await tester.tap(find.byKey(Key('gig-delete-${draft.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Delete gig permanently?'), findsOneWidget);
      await tester.tap(find.text('CONFIRM'));
      await tester.pumpAndSettle();
      expect(harness.app.managedGigProjects, isEmpty);
      harness.app.dispose();
    },
  );

  testWidgets('published gigs honor write policy and PAST is read-only', (
    tester,
  ) async {
    final harness = await _pumpScreen(
      tester,
      home: const Scaffold(body: GigManagerScreen()),
    );
    await _signInBand(tester, harness);
    final repository = harness.app.repository as DemoRepository;
    final draft = await repository.createGigDraft('b1');
    final startsAt = DateTime.now().add(const Duration(days: 2));
    await repository.saveGigDraft(
      projectId: draft.id,
      revision: draft.revision,
      title: 'Legacy show',
      doorsAt: startsAt.subtract(const Duration(hours: 1)),
      startsAt: startsAt,
      venueId: 'v1',
      price: 0,
      flyKey: 'xerox',
      flyStorageId: null,
      overlay: true,
      desc: '',
      ticketing: Ticketing.rsvp,
      ageRequirement: AgeRequirement.allAges,
      externalUrl: null,
      cap: 'No cap',
    );
    await repository.publishGigDraft(draft.id);
    await harness.app.refreshManagedGigs();
    await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('gig-edit-${draft.id}')), findsOneWidget);
    expect(find.byKey(Key('gig-actions-${draft.id}')), findsOneWidget);

    repository.demoBandGigWrites = false;
    await harness.app.refreshGigWritePolicy();
    await tester.pumpAndSettle();
    expect(
      tester.widget<EpCard>(find.byKey(Key('gig-project-${draft.id}'))).onTap,
      isNull,
    );
    expect(find.byKey(Key('gig-edit-${draft.id}')), findsNothing);
    expect(find.byKey(Key('gig-actions-${draft.id}')), findsOneWidget);
    expect(find.byKey(Key('gig-preview-${draft.id}')), findsOneWidget);
    expect(find.byKey(Key('gig-door-${draft.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('gig-actions-${draft.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate'), findsNothing);
    expect(find.text('Unpublish…'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Cancel gig…'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel gig?'), findsOneWidget);
    await tester.tap(find.text('CONFIRM'));
    await tester.pumpAndSettle();
    expect(
      harness.app.managedGigProjects.single.status,
      GigProjectStatus.cancelled,
    );
    // PAST remains read-only even when the write policy is enabled again.
    repository.demoBandGigWrites = true;
    await harness.app.refreshGigWritePolicy();
    await tester.tap(find.byKey(const Key('band-gigs-seg-past')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('gig-project-${draft.id}')), findsOneWidget);
    expect(
      tester.widget<EpCard>(find.byKey(Key('gig-project-${draft.id}'))).onTap,
      isNull,
    );
    expect(find.byKey(Key('gig-edit-${draft.id}')), findsNothing);
    expect(find.byKey(Key('gig-actions-${draft.id}')), findsNothing);
    expect(find.byKey(Key('gig-door-${draft.id}')), findsNothing);
    expect(find.byType(LedgerRow), findsWidgets);
    harness.app.dispose();
  });

  testWidgets(
    'filters apply area, genre, venue type, and minor-unit guarantee',
    (tester) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(body: GigManagerScreen()),
      );
      await _signInBand(tester, harness);
      await tester.tap(find.byKey(const Key('band-gigs-filters')));
      await tester.pumpAndSettle();
      expectNoFieldInCard(tester);

      await tester.enterText(
        find.byKey(const Key('band-gigs-filter-area')),
        'Oakland',
      );
      await tester.tap(find.widgetWithText(EpChip, 'PUNK'));
      await tester.tap(find.widgetWithText(EpChip, 'BAR'));
      await tester.ensureVisible(
        find.byKey(const Key('band-gigs-filter-minimum')),
      );
      await tester.enterText(
        find.byKey(const Key('band-gigs-filter-minimum')),
        '175.50',
      );
      await tester.tap(find.byKey(const Key('band-gigs-filter-apply')));
      await tester.pumpAndSettle();

      expect(harness.app.browseFilters.area, 'Oakland');
      expect(harness.app.browseFilters.genre, 'punk');
      expect(harness.app.browseFilters.venueType, VenueType.bar);
      expect(harness.app.browseFilters.minGuaranteeMinor, 17550);
      expect(find.byKey(const Key('opp-card-opp1')), findsNothing);
      harness.app.dispose();
    },
  );

  testWidgets('withdraw then apply to the headliner slot from detail', (
    tester,
  ) async {
    final screen = ValueNotifier<Widget>(const GigManagerScreen());
    addTearDown(screen.dispose);
    final harness = await _pumpScreen(
      tester,
      home: Scaffold(
        body: ValueListenableBuilder<Widget>(
          valueListenable: screen,
          builder: (_, child, _) => child,
        ),
      ),
    );
    await _signInBand(tester, harness);
    await tester.tap(find.byKey(const Key('band-gigs-seg-applied')));
    await tester.pumpAndSettle();
    await _withdrawFromApplied(tester);

    // Keep the same repository: app1 must be withdrawn before b1 applies again.
    screen.value = const OpportunityDetailScreen(opportunityRef: 'opp1');
    await tester.pumpAndSettle();
    expect(find.text('SLOTS'), findsOneWidget);
    expect(
      find.byKey(const Key('opp-detail-slot-opp1-headliner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('opp-detail-slot-opp1-support')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('opp-detail-apply')), findsOneWidget);
    expectNoFieldInCard(tester);

    await tester.tap(find.byKey(const Key('opp-detail-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opp-apply-band-b1')), findsNothing);
    expect(
      tester
          .widget<EpChip>(
            find.byKey(const Key('opp-apply-slot-opp1-headliner')),
          )
          .active,
      isTrue,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('opp-apply-fee')))
          .controller!
          .text,
      '300',
    );
    expectNoFieldInCard(tester);
    await tester.enterText(find.byKey(const Key('opp-apply-fee')), '325.50');
    await tester.enterText(
      find.byKey(const Key('opp-apply-availability')),
      'Available after 6',
    );
    await tester.enterText(
      find.byKey(const Key('opp-apply-lineup')),
      'Four musicians',
    );
    await tester.ensureVisible(find.byKey(const Key('opp-apply-message')));
    await tester.enterText(
      find.byKey(const Key('opp-apply-message')),
      'Ready for a full set.',
    );
    await tester.tap(find.byKey(const Key('opp-apply-submit')));
    await tester.pumpAndSettle();

    final applications = await (harness.app.repository as DemoRepository)
        .myApplications('b1');
    final active = applications
        .singleWhere((row) => row.application.status.isActive)
        .application;
    expect(active.id, isNot('app1'));
    expect(active.slotId, 'opp1-headliner');
    expect(active.askMinor, 32550);
    expect(active.availabilityNote, 'Available after 6');
    expect(active.lineupNote, 'Four musicians');
    expect(active.message, 'Ready for a full set.');
    expect(harness.app.toast, 'Application sent');
    expect(find.text('APPLIED · SUBMITTED'), findsOneWidget);
    expect(find.byKey(const Key('opp-detail-apply')), findsNothing);
    expect(find.byKey(const Key('opp-detail-withdraw')), findsOneWidget);
    harness.app.dispose();
  });

  testWidgets('detail can withdraw an existing application', (tester) async {
    final harness = await _pumpScreen(
      tester,
      home: const Scaffold(
        body: OpportunityDetailScreen(opportunityRef: 'opp1'),
      ),
    );
    await _signInBand(tester, harness);
    expect(find.text('APPLIED · SUBMITTED'), findsOneWidget);
    await tester.tap(find.byKey(const Key('opp-detail-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM'));
    await tester.pumpAndSettle();

    expect(
      harness.app.myApplications.single.application.status,
      ArtistApplicationStatus.withdrawn,
    );
    expect(find.byKey(const Key('opp-detail-apply')), findsOneWidget);
    expect(find.byKey(const Key('opp-detail-withdraw')), findsNothing);
    harness.app.dispose();
  });

  testWidgets(
    'an application race shows the repository error inside the sheet',
    (tester) async {
      final harness = await _pumpScreen(
        tester,
        home: const Scaffold(
          body: OpportunityDetailScreen(opportunityRef: 'opp3'),
        ),
      );
      await _signInBand(tester, harness);
      expect(find.text('INVITED'), findsOneWidget);
      await tester.tap(find.byKey(const Key('opp-detail-apply')));
      await tester.pumpAndSettle();

      // Another client applies after this sheet has opened.
      await harness.app.repository.applyToOpportunity(
        opportunityId: 'opp3',
        slotId: 'opp3-headliner',
        bandId: 'b1',
        message: 'Already sent elsewhere',
      );
      await tester.tap(find.byKey(const Key('opp-apply-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('You already applied to this opportunity'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('opp-apply-submit')), findsOneWidget);
      expect(tester.takeException(), isNull);
      harness.app.dispose();
    },
  );

  testWidgets('unavailable detail has a safe back action at the root', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const RootShell(),
      initialOpportunityRef: 'missing',
    );
    expect(find.text("This opportunity isn't available."), findsOneWidget);
    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(harness.app.current.screen, Screen.home);
    expect(find.byType(OpportunityDetailScreen), findsNothing);
  });
}

Future<void> _signInBand(WidgetTester tester, AppHarness harness) async {
  await harness.auth.signInDemo();
  await tester.pumpAndSettle();
  harness.app.switchToBand('b1');
  await tester.pumpAndSettle();
}

Future<void> _signInNonAdminMember(
  WidgetTester tester,
  AppHarness harness,
) async {
  await harness.auth.signInDemo();
  await tester.pumpAndSettle();
  final invite = await harness.app.repository.createBandInvite('b2');
  await harness.app.repository.acceptBandInvite(invite.token);
  await tester.pumpAndSettle();
  harness.app.switchToBand('b2');
  await tester.pumpAndSettle();
}

Future<void> _withdrawFromApplied(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('band-app-app1-withdraw')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CONFIRM'));
  await tester.pumpAndSettle();
}

// These tests explicitly dispose AppState. Shadow the harness's lazy owning
// provider so only this non-owning provider subscribes to the test's state.
Future<AppHarness> _pumpScreen(WidgetTester tester, {required Widget home}) {
  late AppState app;
  return pumpApp(
    tester,
    beforePump: (state) => app = state,
    home: Builder(
      builder: (_) =>
          ChangeNotifierProvider<AppState>.value(value: app, child: home),
    ),
  );
}
