import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_scroll_header_bar.dart';
import 'package:earplug/widgets/ep_search_field.dart';
import 'package:earplug/widgets/feed_spacing.dart';
import 'package:earplug/widgets/friend_row.dart';
import 'package:earplug/widgets/opportunity_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _fieldKey = Key('shell-search-field');
const _clearKey = Key('shell-search-clear');
const _barKey = ValueKey('shell-header-bar');

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildEpTheme(),
    themeAnimationDuration: Duration.zero,
    home: Scaffold(body: child),
  ),
);

BoxDecoration _searchBox(WidgetTester tester) =>
    tester
            .widget<Container>(
              find
                  .ancestor(
                    of: find.byKey(_fieldKey),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Container &&
                          widget.decoration is BoxDecoration,
                    ),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

Opportunity _opportunity(List<OpportunitySlot> slots) {
  final now = DateTime(2026, 9, 16);
  return Opportunity(
    id: 'opp1',
    organizationId: 'org1',
    mode: OpportunityMode.publicEvent,
    title: 'Loud night',
    desc: '',
    genres: const ['punk'],
    startsAt: now,
    ageRequirement: AgeRequirement.allAges,
    flyKey: 'xerox',
    applicationsCloseAt: now,
    visibility: OpportunityVisibility.publicListing,
    ticketing: OpportunityTicketing.none,
    status: OpportunityStatus.booking,
    slug: 'loud-night',
    revision: 1,
    applicationCount: 0,
    slots: slots,
    invitedBandIds: const [],
    createdAt: now,
    updatedAt: now,
    area: 'Bay Area',
    currency: 'usd',
  );
}

OpportunitySlot _slot(
  int order, {
  SlotRole role = SlotRole.support,
  int guarantee = 10000,
  SlotStatus status = SlotStatus.open,
}) => OpportunitySlot(
  id: 'slot-$order',
  order: order,
  role: role,
  guaranteeMinor: guarantee,
  required: true,
  status: status,
);

GigProject _project(String? title) => GigProject(
  id: 'p1',
  bandId: 'b1',
  status: GigProjectStatus.draft,
  revision: 1,
  price: 0,
  flyKey: 'blue',
  overlay: true,
  desc: '',
  ticketing: Ticketing.rsvp,
  ageRequirement: AgeRequirement.allAges,
  cap: 'No cap',
  updatedAt: DateTime(2026, 9, 16),
  performers: const [],
  title: title,
);

void main() {
  group('EpSearchField', () {
    testWidgets('keeps its keys, clears through onClear and reports changes', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      var cleared = 0;
      String? submitted;
      await _pump(
        tester,
        EpSearchField(
          fieldKey: _fieldKey,
          clearKey: _clearKey,
          controller: controller,
          hint: 'Search by name',
          onChanged: changes.add,
          onClear: () {
            cleared++;
            controller.clear();
          },
          onSubmitted: (text) => submitted = text,
        ),
      );

      expect(find.byKey(_fieldKey), findsOneWidget);
      expect(find.text('Search by name'), findsOneWidget);
      expect(find.byKey(_clearKey), findsNothing);
      expect(find.byIcon(Icons.search), findsOneWidget);

      await tester.enterText(find.byKey(_fieldKey), 'fog');
      await tester.pump();
      expect(changes, ['fog']);
      expect(find.byKey(_clearKey), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(submitted, 'fog');

      await tester.tap(find.byKey(_clearKey));
      await tester.pump();
      expect(cleared, 1);
      expect(controller.text, isEmpty);
      expect(find.byKey(_clearKey), findsNothing);
    });

    testWidgets('square box thickens to the accent hairline while focused', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        EpSearchField(
          fieldKey: _fieldKey,
          clearKey: _clearKey,
          controller: controller,
          hint: 'Search',
          onChanged: (_) {},
          onClear: () {},
        ),
      );
      final colors = tester.element(find.byKey(_fieldKey)).epColors;

      expect(_searchBox(tester).borderRadius, isNull);
      expect(_searchBox(tester).border, Border.all(color: colors.line));
      expect(
        tester
            .widget<Container>(
              find
                  .ancestor(
                    of: find.byKey(_fieldKey),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .constraints,
        const BoxConstraints(minHeight: 44),
      );
      expect(
        tester.getSize(find.byType(EpSearchField)).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      expect(
        _searchBox(tester).border,
        Border.all(color: colors.accent, width: 1.5),
      );

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(_searchBox(tester).border, Border.all(color: colors.line));
    });

    testWidgets('pill radius rounds the box without changing its border', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        EpSearchField(
          fieldKey: _fieldKey,
          clearKey: _clearKey,
          controller: controller,
          hint: 'Search',
          onChanged: (_) {},
          onClear: () {},
          radius: EpLayout.pillRadius,
        ),
      );
      final colors = tester.element(find.byKey(_fieldKey)).epColors;

      expect(
        _searchBox(tester).borderRadius,
        BorderRadius.circular(EpLayout.pillRadius),
      );
      expect(_searchBox(tester).border, Border.all(color: colors.line));
    });
  });

  group('EpScrollHeaderBar', () {
    Widget bar({required bool hairlineInForeground, double progress = 1}) =>
        EpScrollHeaderBar(
          barKey: _barKey,
          topInset: 20,
          progress: progress,
          hairlineInForeground: hairlineInForeground,
          leading: const Icon(Icons.arrow_back),
          title: const Text('Fog Horn'),
          trailing: const [Icon(Icons.share)],
        );

    testWidgets('paints the hairline in the foreground by default', (
      tester,
    ) async {
      await _pump(tester, bar(hairlineInForeground: true));
      final container = tester.widget<Container>(find.byKey(_barKey));
      final colors = tester.element(find.byKey(_barKey)).epColors;

      final background = container.decoration! as BoxDecoration;
      expect(background.border, isNull);
      expect(background.color, colors.background);
      final foreground = container.foregroundDecoration! as BoxDecoration;
      expect(foreground.border, Border(bottom: BorderSide(color: colors.line)));
      expect(tester.getSize(find.byKey(_barKey)).height, 56 + 20);
      expect(find.text('Fog Horn'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });

    testWidgets('moves the hairline into the background border on request', (
      tester,
    ) async {
      await _pump(tester, bar(hairlineInForeground: false));
      final container = tester.widget<Container>(find.byKey(_barKey));
      final colors = tester.element(find.byKey(_barKey)).epColors;

      final background = container.decoration! as BoxDecoration;
      expect(background.border, Border(bottom: BorderSide(color: colors.line)));
      expect(container.foregroundDecoration, isNull);
      expect(tester.getSize(find.byKey(_barKey)).height, 56 + 20);
    });

    testWidgets('fades the title and surfaces with progress', (tester) async {
      await _pump(tester, bar(hairlineInForeground: true, progress: 0));
      final container = tester.widget<Container>(find.byKey(_barKey));
      final colors = tester.element(find.byKey(_barKey)).epColors;

      final background = container.decoration! as BoxDecoration;
      expect(background.color, colors.background.withValues(alpha: 0));
      final foreground = container.foregroundDecoration! as BoxDecoration;
      expect(
        foreground.border,
        Border(bottom: BorderSide(color: colors.line.withValues(alpha: 0))),
      );
      final title = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Fog Horn'), matching: find.byType(Opacity))
            .first,
      );
      expect(title.opacity, 0);
    });

    test('scrollFadeProgress clamps the offset over the fade distance', () {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      expect(scrollFadeProgress(controller), 0);
      expect(scrollFadeProgress(controller, fade: 40), 0);
    });
  });

  testWidgets('FriendRow loads the card and keeps its key and sub', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(
        body: FriendRow(
          userId: 'u-maya',
          rowKey: ValueKey('friend-u-maya'),
          sub: 'Friend',
        ),
      ),
    );

    expect(find.byKey(const ValueKey('friend-u-maya')), findsOneWidget);
    expect(find.byType(EpEntityRow), findsOneWidget);
    expect(find.text('MAYA OKAFOR'), findsOneWidget);
    expect(find.bySemanticsLabel('Maya Okafor'), findsOneWidget);
    expect(find.text('Friend'), findsOneWidget);
  });

  group('labels', () {
    test('organization roles', () {
      expect(organizationRoleLabel(OrganizationRole.owner), 'Owner');
      expect(organizationRoleLabel(OrganizationRole.manager), 'Manager');
      expect(organizationRoleLabel(OrganizationRole.finance), 'Finance');
      expect(organizationRoleLabel(OrganizationRole.door), 'Door');
    });

    test('organization application statuses title-case the wire value', () {
      expect(
        organizationApplicationStatusLabel(
          OrganizationApplicationStatus.underReview,
        ),
        'Under Review',
      );
      expect(
        organizationApplicationStatusLabel(
          OrganizationApplicationStatus.needsInfo,
        ),
        'Needs Info',
      );
      expect(
        organizationApplicationStatusLabel(
          OrganizationApplicationStatus.approved,
        ),
        'Approved',
      );
    });

    test('venue types', () {
      expect(venueTypeLabel(VenueType.bar), 'Bar');
      expect(venueTypeLabel(VenueType.club), 'Club');
      expect(venueTypeLabel(VenueType.hall), 'Hall');
      expect(venueTypeLabel(VenueType.house), 'House');
      expect(venueTypeLabel(VenueType.outdoor), 'Outdoor');
      expect(venueTypeLabel(VenueType.private), 'Private');
      expect(venueTypeLabel(VenueType.other), 'Other');
    });

    test('estimated draw', () {
      expect(estimatedDrawLabel(null), 'Estimated draw: No history yet');
      expect(
        estimatedDrawLabel(
          const EstimatedDraw(
            low: 40,
            high: 60,
            confidence: DrawConfidence.medium,
            events: 3,
            basis: DrawBasis.checkIns,
          ),
        ),
        'Estimated draw: 40–60 · medium confidence · based on check-ins',
      );
      expect(
        estimatedDrawLabel(
          const EstimatedDraw(
            low: 10,
            high: 20,
            confidence: DrawConfidence.low,
            events: 1,
            basis: DrawBasis.rsvps,
          ),
        ),
        'Estimated draw: 10–20 · low confidence · based on RSVPs',
      );
    });

    test('project title falls back when blank', () {
      expect(projectTitle(_project('  Fog Horn ')), 'Fog Horn');
      expect(projectTitle(_project(null)), 'Untitled gig');
      expect(projectTitle(_project('   ')), 'Untitled gig');
      expect(projectTitle(_project(''), fallback: 'New gig'), 'New gig');
    });

    test('booked slot line orders slots and counts extra roles on request', () {
      final opportunity = _opportunity([
        _slot(1, status: SlotStatus.booked),
        _slot(
          0,
          role: SlotRole.headliner,
          guarantee: 30000,
          status: SlotStatus.booked,
        ),
        _slot(2, role: SlotRole.opener, guarantee: 5000),
      ]);

      expect(
        bookedSlotLine(opportunity),
        r'Headliner · $300.00 · 2/3 slots booked',
      );
      expect(
        bookedSlotLine(opportunity, countExtraRoles: true),
        r'Headliner · $300.00 + 2 more · 2/3 slots booked',
      );
      expect(
        bookedSlotLine(_opportunity([_slot(0)]), countExtraRoles: true),
        r'Support · $100.00 · 0/1 slots booked',
      );
      expect(bookedSlotLine(_opportunity(const [])), '0/0 slots booked');
    });
  });

  testWidgets('epGutter pads by the page gutter', (tester) async {
    await _pump(tester, epGutter(const Text('Inside')));
    final padding = tester.widget<Padding>(
      find
          .ancestor(of: find.text('Inside'), matching: find.byType(Padding))
          .first,
    );
    expect(
      padding.padding,
      const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
    );
  });
}
