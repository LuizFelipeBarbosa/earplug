import 'dart:ui' show Tristate;

import 'package:earplug/app_state.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/venue_detail.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  test('refresh tokens preserve old names and expose semantic aliases', () {
    expect(Ep.volt, Ep.warning);
    expect(Ep.ink, Ep.contentPrimary);
    expect(Ep.raised, Ep.surfaceRaised);
    expect(Ep.selected, Ep.surfaceSelected);
    expect(Ep.dark, Ep.background);

    final text = buildEpTheme().textTheme;
    expect(text.epPosterTitle.fontFamily, 'Archivo Black');
    expect(text.epPosterTitle.fontSize, 22);
    expect(text.epSection.fontSize, 12);
    expect(text.epSection.letterSpacing, 2);
    expect(text.epChipLabel.fontSize, greaterThanOrEqualTo(11));
    expect(text.epMeta.fontSize, greaterThanOrEqualTo(11));
  });

  testWidgets(
    'date, section, status, and ledger primitives expose their data',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var opened = false;
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SectionBar(label: 'Upcoming', count: 2),
              const DateBlock(
                day: '10',
                month: 'Sep',
                semanticLabel: 'Wednesday September 10',
              ),
              const StatusPill(label: 'Going ✓'),
              const ProfileCompleteBadge(),
              LedgerRow(
                title: 'Riptide',
                details: const ['Foghorn Club', 'SEP 10', '56 going'],
                onTap: () => opened = true,
              ),
            ],
          ),
        ),
      );

      expect(find.text('UPCOMING · 2'), findsOne);
      expect(find.text('10'), findsOne);
      expect(find.text('SEP'), findsOne);
      expect(find.bySemanticsLabel('Wednesday September 10'), findsOne);
      expect(find.text('GOING ✓'), findsOne);
      expect(
        tester.widget<Text>(find.text('GOING ✓')).style!.fontSize,
        greaterThanOrEqualTo(11),
      );
      expect(
        tester.widget<Text>(find.text('PROFILE COMPLETE')).style!.fontSize,
        greaterThanOrEqualTo(11),
      );
      expect(
        tester.widget<Text>(find.text('SEP')).style!.fontSize,
        greaterThanOrEqualTo(11),
      );
      expect(
        tester.getSize(find.byType(LedgerRow)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byType(LedgerRow));
      expect(opened, isTrue);
      semantics.dispose();
    },
  );

  testWidgets('chips support volt, neutral, ghost, and removable states', (
    tester,
  ) async {
    var selected = 0;
    var removed = 0;
    await tester.pumpWidget(
      _host(
        Wrap(
          children: [
            EpChip(label: 'Punk', active: true, onTap: () => selected++),
            EpChip(
              label: 'Noise',
              active: true,
              neutralSelected: true,
              onTap: () => selected++,
            ),
            EpChip(
              label: '+ Add',
              active: false,
              ghost: true,
              onTap: () => selected++,
            ),
            EpChip(
              label: 'Luz',
              active: false,
              onTap: null,
              onRemoved: () => removed++,
            ),
          ],
        ),
      ),
    );

    final active = tester.widget<FilterChip>(find.byType(FilterChip).first);
    final neutral = tester.widget<FilterChip>(find.byType(FilterChip).at(1));
    expect(active.selectedColor, Ep.volt);
    expect(neutral.selectedColor, Ep.surfaceDisabled);
    expect(neutral.side!.color, Ep.contentSecondary);
    expect(
      tester.getSize(find.byType(EpChip).at(2)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('+ ADD'));
    await tester.tap(find.byIcon(Icons.close));
    expect(selected, 1);
    expect(removed, 1);
  });

  testWidgets('form grammar remains keyboard-sized and callback-only', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var enabled = false;
    var resumed = false;
    var previewed = false;
    var saved = false;
    var archived = false;
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchRow(
              label: 'Followed-band updates',
              value: enabled,
              caption: 'Send an update when a followed band publishes a gig.',
              onChanged: (value) => enabled = value,
            ),
            GhostDraftRow(
              title: 'Halloween show',
              missing: 'finish lineup to publish',
              onResume: () => resumed = true,
            ),
            StickyActionBar(
              secondaryLabel: 'Preview',
              onSecondary: () => previewed = true,
              primaryLabel: 'Save changes',
              onPrimary: () => saved = true,
            ),
            DangerZone(
              label: 'Archive band',
              consequence: 'Archiving hides this band and its gigs.',
              onPressed: () => archived = true,
            ),
          ],
        ),
      ),
    );

    final switchData = tester
        .getSemantics(find.byType(SwitchRow))
        .getSemanticsData();
    expect(switchData.flagsCollection.isToggled, Tristate.isFalse);
    expect(
      tester.getSize(find.byType(SwitchRow)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byType(SwitchRow));
    await tester.tap(find.text('RESUME →'));
    await tester.tap(find.text('PREVIEW'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.tap(find.text('ARCHIVE BAND'));
    expect(enabled, isTrue);
    expect(resumed, isTrue);
    expect(previewed, isTrue);
    expect(saved, isTrue);
    expect(archived, isTrue);
    semantics.dispose();
  });

  testWidgets('generic action sheet separates its destructive action', (
    tester,
  ) async {
    var duplicated = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEpTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showEpActionSheet(
                context,
                header: 'Riptide release show',
                items: [
                  EpActionSheetItem(
                    label: 'Duplicate',
                    onPressed: () => duplicated = true,
                  ),
                  const EpActionSheetItem(
                    label: 'Delete',
                    onPressed: null,
                    destructive: true,
                  ),
                ],
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(EpActionSheet), findsOne);
    expect(find.text('RIPTIDE RELEASE SHOW'), findsOne);
    expect(
      tester.widget<Text>(find.text('Delete')).style!.color,
      Ep.destructive,
    );
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(duplicated, isTrue);
    expect(find.byType(EpActionSheet), findsNothing);
  });

  testWidgets('stat tile and volt strip preserve hierarchy and actions', (
    tester,
  ) async {
    var launched = false;
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EpStatCard(
              label: 'Followers',
              value: '486',
              caption: 'and counting',
              expand: false,
            ),
            VoltStrip(
              kicker: 'Next up',
              title: 'Riptide Release Show',
              meta: 'Tonight · Doors 8PM',
              actionLabel: 'Door mode',
              onAction: () => launched = true,
            ),
          ],
        ),
      ),
    );

    expect(find.text('FOLLOWERS'), findsOne);
    expect(
      tester.widget<Text>(find.text('FOLLOWERS')).style!.fontSize,
      greaterThanOrEqualTo(11),
    );
    expect(find.text('486'), findsOne);
    expect(find.text('NEXT UP'), findsOne);
    expect(find.text('Riptide Release Show'), findsOne);
    await tester.tap(find.text('DOOR MODE'));
    expect(launched, isTrue);
  });

  testWidgets('navigation item uses the refreshed 66px accessible grammar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 100,
          child: EpNavigationItem(
            icon: Icons.home_outlined,
            label: 'GIGS',
            selected: true,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(EpNavigationItem)).height, 66);
    final indicator = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(EpNavigationItem),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(indicator.constraints!.maxWidth, 24);
    expect(indicator.constraints!.maxHeight, 2.5);
    expect(tester.widget<Text>(find.text('GIGS')).style!.fontSize, 11);
  });

  testWidgets('stat labels wrap instead of truncating on narrow tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 90,
          child: EpStatCard(
            label: 'Next gig RSVPs',
            value: '12',
            caption: 'Riptide Release Show',
            expand: false,
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('NEXT GIG RSVPS'));
    expect(label.maxLines, 2);
    expect(label.style!.fontSize, greaterThanOrEqualTo(11));
    expect(tester.getSize(find.text('NEXT GIG RSVPS')).height, greaterThan(20));
  });

  testWidgets('narrow navigation keeps its full accessible band label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 74,
          child: EpNavigationItem(
            icon: Icons.groups_outlined,
            label: 'SWITCH BAND',
            compactLabel: 'BAND',
            selected: false,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('BAND'), findsOne);
    expect(find.text('SWITCH BAND'), findsNothing);
    expect(
      tester.getSemantics(find.byType(EpNavigationItem)).label,
      'SWITCH BAND',
    );
    semantics.dispose();
  });

  testWidgets('featured custom flyer image receives its contrast scrim', (
    tester,
  ) async {
    late AppState app;
    await pumpApp(
      tester,
      beforePump: (value) => app = value,
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                FanEventCard(
                  gig: _gig(
                    id: 'custom',
                    title: 'Custom Flyer',
                    flyKey: 'custom',
                    flyerUrl: 'https://example.test/custom-flyer.jpg',
                  ),
                  app: app,
                  presentation: FanEventCardPresentation.featured,
                ),
                FanEventCard(
                  gig: _gig(
                    id: 'generated',
                    title: 'Generated Flyer',
                    flyKey: 'paper',
                    flyerUrl: 'https://example.test/ignored-flyer.jpg',
                  ),
                  app: app,
                  presentation: FanEventCardPresentation.featured,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fan-event-custom')),
        matching: find.byKey(const ValueKey('flyer-image-scrim')),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fan-event-generated')),
        matching: find.byKey(const ValueKey('flyer-image-scrim')),
      ),
      findsNothing,
    );
  });

  testWidgets('venue hero foreground remains light in both themes', (
    tester,
  ) async {
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    await pumpApp(
      tester,
      home: ValueListenableBuilder(
        valueListenable: brightness,
        builder: (context, value, child) => Theme(
          data: buildEpTheme(value),
          child: const Scaffold(body: VenueDetailScreen(venueId: 'v1')),
        ),
      ),
    );

    void expectLightHeroText() {
      expect(
        tester.widget<Text>(find.textContaining('VENUE ·')).style!.color,
        Ep.ink,
      );
      expect(
        tester.widget<Text>(find.text('THE FOGHORN CLUB')).style!.color,
        Ep.ink,
      );
    }

    expectLightHeroText();
    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();
    expectLightHeroText();
  });
}

Gig _gig({
  required String id,
  required String title,
  required String flyKey,
  required String flyerUrl,
}) => Gig(
  id: id,
  title: title,
  venueId: 'v1',
  price: 0,
  startsAt: DateTime(2026, 9, 1, 20),
  dateShort: 'TUE SEP 1',
  dateLine: 'TONIGHT · DOORS 8PM',
  time: '8PM',
  when: GigWhen.tonight,
  flyKey: flyKey,
  lineup: const [],
  going: 0,
  genres: const [],
  desc: '',
  tix: Ticketing.rsvp,
  flyerUrl: flyerUrl,
);

Widget _host(Widget child) => MaterialApp(
  theme: buildEpTheme(),
  home: Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  ),
);
