import 'package:earplug/demo_data.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/org_gigs.dart';
import 'package:earplug/screens/org_opportunities.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('the organizer GIGS tab leads with the title, hero and cards', (
    tester,
  ) async {
    await _pumpGigs(tester);
    final openCard = find.byKey(const ValueKey('org-opp-opp1'));
    final quietCard = find.byKey(const ValueKey('org-opp-opp3'));
    final draftCard = find.byKey(const ValueKey('org-opp-opp2'));

    final header = find.byKey(const Key('org-gigs-header'));
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.text('GIGS')),
      findsOneWidget,
    );
    final newPill = tester.widget<EpPill>(
      find.byKey(const Key('org-gigs-new')),
    );
    expect(newPill.label, '+ New opportunity');
    expect(newPill.variant, EpPillVariant.outline);
    expect(newPill.size, EpPillSize.chip);
    // No identity header, role line, Discover chip or segment tabs here.
    expect(find.byKey(const Key('org-dash-discover')), findsNothing);
    expect(find.byKey(const Key('org-opps-tabs')), findsNothing);
    expect(find.textContaining('ORGANIZER · '), findsNothing);

    // Nothing in the demo is fully booked, so the hero prompts for a post.
    expect(find.byKey(const Key('org-gigs-next-event')), findsNothing);
    expect(find.byKey(const Key('org-gigs-next-event-empty')), findsOneWidget);
    expect(find.text('NOTHING CONFIRMED'), findsOneWidget);

    // The demo profile is complete and Stripe is not set up: 1 of 2.
    final readiness = find.byKey(const Key('band-readiness'));
    expect(readiness, findsOneWidget);
    expect(
      find.descendant(of: readiness, matching: find.text('1 OF 2')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('org-gigs-readiness-retry')), findsNothing);

    // Open listings first, the draft last; every card shows its fill state.
    expect(find.text('OPPORTUNITIES · 3'), findsOneWidget);
    expect(
      tester.getTopLeft(openCard).dy,
      lessThan(tester.getTopLeft(quietCard).dy),
    );
    expect(
      tester.getTopLeft(quietCard).dy,
      lessThan(tester.getTopLeft(draftCard).dy),
    );
    final applied = tester.widget<StatusPill>(
      find.byKey(const Key('org-opp-applied-opp1')),
    );
    expect(applied.label, '2 applied');
    expect(applied.tone, EpStatusPillTone.selected);
    expect(
      find.descendant(of: openCard, matching: find.text('2 APPLIED')),
      findsOneWidget,
    );
    final none = tester.widget<StatusPill>(
      find.byKey(const Key('org-opp-applied-opp3')),
    );
    expect(none.label, '0 applied');
    expect(none.tone, EpStatusPillTone.neutral);
    expect(
      find.descendant(of: draftCard, matching: find.text('DRAFT')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openCard,
        matching: find.text(
          DemoData.opportunities['opp1']!.title.toUpperCase(),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openCard,
        matching: find.text('Headliner + Support · 0/2 slots booked'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openCard,
        matching: find.textContaining(' · The Foghorn Club'),
      ),
      findsOneWidget,
    );

    final toggle = find.byKey(const Key('org-gigs-past-toggle'));
    await tester.scrollUntilVisible(toggle, 200);
    expect(find.text('PAST · 0'), findsOneWidget);
    expect(find.byKey(const Key('org-gigs-past-body')), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-gigs-past-body')), findsOneWidget);
  });

  testWidgets('the UP NEXT hero shows the fully booked event and opens it', (
    tester,
  ) async {
    final booked = _fullyBooked(DemoData.opportunities['opp1']!);
    final harness = await _pumpGigs(
      tester,
      size: const Size(390, 844),
      repositoryBuilder: (auth) => StubRepository(auth: auth)
        ..returnsStream<List<Opportunity>>(
          'watchOrganizationOpportunities',
          () => Stream.value([booked]),
        )
        ..returns('organizationStripeStatus', _enabledStripe),
    );

    // Profile and finance are both done, so no module.
    expect(find.byKey(const Key('band-readiness')), findsNothing);
    expect(find.byKey(const Key('org-gigs-next-event-empty')), findsNothing);

    final hero = find.byKey(const Key('org-gigs-next-event'));
    final heroRect = tester.getRect(hero);
    expect(heroRect.top, greaterThanOrEqualTo(0));
    expect(heroRect.bottom, lessThan(844));
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      0,
    );
    expect(find.text('UP NEXT'), findsOneWidget);
    final when = tester.widget<EpMonoText>(
      find.byKey(const Key('org-gigs-next-event-when')),
    );
    expect(when.text, matches(RegExp(r'^\w{3} \w{3} \d{1,2} · \d{1,2}:\d{2}')));
    expect(
      find.descendant(of: hero, matching: find.text(booked.title.toUpperCase())),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.text('The Foghorn Club · Mission'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.text('Headliner + Support · 2/2 slots booked'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.byWidgetPredicate(
          (widget) => widget is StatusPill && widget.label == 'Confirmed',
        ),
      ),
      findsOneWidget,
    );

    // The confirmed event keeps its card, with CONFIRMED instead of applied.
    final card = find.byKey(const ValueKey('org-opp-opp1'));
    expect(find.text('OPPORTUNITIES · 1'), findsOneWidget);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('CONFIRMED')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('org-opp-applied-opp1')), findsNothing);

    final view = find.byKey(const Key('org-gigs-next-event-view'));
    expect(view.hitTestable(), findsOneWidget);
    expect(tester.widget<EpPill>(view).variant, EpPillVariant.outline);
    await tester.tap(view);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgOpportunity);
    expect(harness.app.current.param, 'opp1');
  });

  testWidgets('the empty hero posts a new opportunity', (tester) async {
    final harness = await _pumpGigs(tester);

    final post = find.byKey(const Key('org-gigs-post'));
    expect(tester.widget<EpPill>(post).variant, EpPillVariant.primary);
    await tester.tap(post);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'new');
  });

  testWidgets('the title pill opens the composer', (tester) async {
    final harness = await _pumpGigs(tester);

    await tester.tap(find.byKey(const Key('org-gigs-new')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'new');
  });

  testWidgets('cards open the detail and drafts open the editor', (
    tester,
  ) async {
    final harness = await _pumpGigs(tester);

    await tester.tap(find.byKey(const ValueKey('org-opp-opp1')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgOpportunity);
    expect(harness.app.current.param, 'opp1');

    harness.app.resetTo(Screen.orgOpportunities);
    await tester.pumpAndSettle();
    final draft = find.byKey(const ValueKey('org-opp-opp2'));
    await tester.scrollUntilVisible(draft, 200);
    await tester.tap(draft);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.opportunityEdit);
    expect(harness.app.current.param, 'opp2');
  });

  testWidgets('past opportunities collapse into one row', (tester) async {
    final harness = await _pumpGigs(
      tester,
      repositoryBuilder: (auth) => StubRepository(auth: auth)
        ..wraps<List<Opportunity>>('manageOpportunities', (opportunities) {
          return opportunities.map((opportunity) {
            return switch (opportunity.id) {
              'opp2' => opportunity.copyWith(
                status: OpportunityStatus.completed,
              ),
              'opp3' => opportunity.copyWith(
                status: OpportunityStatus.cancelled,
              ),
              _ => opportunity,
            };
          }).toList();
        }),
    );
    final toggle = find.byKey(const Key('org-gigs-past-toggle'));
    final body = find.byKey(const Key('org-gigs-past-body'));

    expect(find.text('OPPORTUNITIES · 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('org-opp-opp2')), findsNothing);
    expect(find.byKey(const ValueKey('org-opp-opp3')), findsNothing);
    await tester.scrollUntilVisible(toggle, 200);
    expect(find.text('PAST · 2'), findsOneWidget);
    expect(find.text('Incl. 1 cancelled'), findsOneWidget);
    expect(body, findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(body, findsOneWidget);
    final cancelledRow = find.byKey(const ValueKey('org-gigs-past-opp3'));
    expect(
      find.descendant(of: cancelledRow, matching: find.text('CANCELLED')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('org-gigs-past-opp2')),
        matching: find.text('COMPLETED'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(cancelledRow);
    await tester.pumpAndSettle();
    await tester.tap(cancelledRow);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgOpportunity);
    expect(harness.app.current.param, 'opp3');
  });

  testWidgets('a failed dashboard load offers a readiness retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..failOnce('organizationDashboard');
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgGigsScreen()),
    );

    expect(find.byKey(const Key('band-readiness')), findsNothing);
    expect(find.text('READINESS UNAVAILABLE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('org-gigs-readiness-retry')));
    await tester.pumpAndSettle();
    expect(find.text('READINESS UNAVAILABLE'), findsNothing);
    expect(find.byKey(const Key('band-readiness')), findsOneWidget);
  });

  testWidgets('hosts keep the REQUESTS list at the same route', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const RootShell());
    await enterOrganizer(tester, harness, 'org2');
    expect(harness.app.currentIsHost, isTrue);

    await tester.tap(find.byKey(const Key('organizer-tab-opportunities')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgOpportunities);
    expect(find.byType(OrgOpportunitiesScreen), findsOneWidget);
    expect(find.byType(OrgGigsScreen), findsNothing);
    expect(find.byKey(const Key('org-opps-tabs')), findsOneWidget);
    expect(find.byKey(const Key('org-gigs-header')), findsNothing);

    // Switching to a venue operator swaps the same route to GIGS.
    await enterOrganizer(tester, harness, 'org1');
    expect(harness.app.current.screen, Screen.orgOpportunities);
    expect(find.byType(OrgGigsScreen), findsOneWidget);
    expect(find.byType(OrgOpportunitiesScreen), findsNothing);
    expect(find.byKey(const Key('org-gigs-header')), findsOneWidget);
    expect(find.byKey(const Key('org-opps-tabs')), findsNothing);
  });

  for (final role in [OrganizationRole.finance, OrganizationRole.door]) {
    testWidgets('${role.name} members see no post actions or readiness', (
      tester,
    ) async {
      final harness = await _pumpGigs(tester);
      harness.app.myOrganizations = [
        OrganizationMembership(
          organization: DemoData.organizations['org1']!,
          role: role,
        ),
      ];
      await enterOrganizer(tester, harness, 'org1');

      expect(find.byKey(const Key('org-gigs-header')), findsOneWidget);
      expect(find.byKey(const Key('org-gigs-new')), findsNothing);
      expect(
        find.byKey(const Key('org-gigs-next-event-empty')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('org-gigs-post')), findsNothing);
      expect(find.byKey(const Key('band-readiness')), findsNothing);
      expect(find.byKey(const Key('org-gigs-readiness-retry')), findsNothing);
      expect(find.byKey(const ValueKey('org-opp-opp1')), findsOneWidget);
    });
  }
}

/// The GIGS tab for org1 (a venue operator) on its own, the way the shell
/// hosts it, with the demo owner signed in.
Future<AppHarness> _pumpGigs(
  WidgetTester tester, {
  Size size = const Size(402, 900),
  StubRepository Function(FakeAuthService auth)? repositoryBuilder,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final harness = await pumpApp(
    tester,
    size: size,
    auth: auth,
    repository: repositoryBuilder?.call(auth),
    beforePump: (app) => app.switchToOrganization('org1'),
    home: const Scaffold(body: OrgGigsScreen()),
  );
  await enterOrganizer(tester, harness, 'org1');
  return harness;
}

/// Every slot filled by the demo band, so the opportunity counts as confirmed.
Opportunity _fullyBooked(Opportunity opportunity) => opportunity.copyWith(
  slots: [
    for (final slot in opportunity.slots)
      OpportunitySlot(
        id: slot.id,
        order: slot.order,
        role: slot.role,
        setLengthMin: slot.setLengthMin,
        guaranteeMinor: slot.guaranteeMinor,
        required: slot.required,
        status: SlotStatus.booked,
        bandId: 'b1',
      ),
  ],
);

const _enabledStripe = StripeAccountStatus(
  state: StripeAccountState.enabled,
  hasAccount: true,
  chargesEnabled: true,
  payoutsEnabled: true,
  detailsSubmitted: true,
  requirementsDue: [],
);
