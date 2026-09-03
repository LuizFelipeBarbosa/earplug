import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:earplug/app_state.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/venue_detail.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/branding.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  group('EarPlug theme', () {
    test('semantic content colors meet WCAG AA on their dark surfaces', () {
      final pairs = <(Color, Color)>[
        (Ep.contentPrimary, Ep.background),
        (Ep.contentPrimary, Ep.surface),
        (Ep.contentSecondary, Ep.surface),
        (Ep.contentDisabled, Ep.surfaceDisabled),
        (Ep.contentDisabled, Ep.surfaceSelected),
        (Ep.accent, Ep.background),
        (Ep.accent, Ep.surface),
        (Ep.accent, Ep.surfaceSelected),
        (Ep.success, Ep.background),
        (Ep.warning, Ep.background),
        (Ep.destructive, Ep.background),
        (Colors.white, Ep.brand),
      ];

      for (final (foreground, background) in pairs) {
        expect(
          _contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason:
              '${foreground.toARGB32().toRadixString(16)} on '
              '${background.toARGB32().toRadixString(16)}',
        );
      }
    });

    test('maps semantic tokens and all six Archivo roles into ThemeData', () {
      final theme = buildEpTheme();

      expect(theme.scaffoldBackgroundColor, Ep.background);
      expect(theme.colorScheme.primary, Ep.brand);
      expect(theme.colorScheme.secondary, Ep.accent);
      expect(theme.colorScheme.surface, Ep.surface);
      expect(theme.colorScheme.error, Ep.destructive);

      final roles = [
        theme.textTheme.epDisplay,
        theme.textTheme.epPageHeading,
        theme.textTheme.epSectionHeading,
        theme.textTheme.epBody,
        theme.textTheme.epLabel,
        theme.textTheme.epCaption,
      ];
      expect(roles, everyElement(isA<TextStyle>()));
      expect(theme.textTheme.epDisplay.fontFamily, 'Archivo Black');
      for (final role in roles.skip(1)) {
        expect(role.fontFamily, contains('Archivo'));
        expect(role.fontFamily, isNot(contains('Archivo Black')));
      }
    });

    test('uses the specified warm light palette and semantic mappings', () {
      final theme = buildEpTheme(Brightness.light);
      final palette = theme.extension<EpPalette>()!;

      expect(palette.background, const Color(0xFFF6F5F1));
      expect(palette.surface, const Color(0xFFFFFFFF));
      expect(palette.surfaceRaised, const Color(0xFFFCFCFA));
      expect(palette.surfaceSelected, const Color(0xFFE7EBFF));
      expect(palette.surfaceDisabled, const Color(0xFFE5E7EC));
      expect(palette.border, const Color(0xFFCDD1DA));
      expect(palette.contentPrimary, const Color(0xFF16171C));
      expect(palette.contentSecondary, const Color(0xFF525761));
      expect(palette.contentDisabled, const Color(0xFF5E6470));
      expect(palette.brand, const Color(0xFF1435F0));
      expect(palette.success, const Color(0xFF087A5B));
      expect(palette.warning, const Color(0xFF6F6500));
      expect(palette.destructive, const Color(0xFFB4232D));
      expect(theme.scaffoldBackgroundColor, palette.background);
      expect(theme.colorScheme.surface, palette.surface);
      expect(theme.colorScheme.error, palette.destructive);
      expect(theme.textTheme.epBody.color, palette.contentPrimary);
    });

    test('semantic light text and status colors meet WCAG AA', () {
      const palette = EpPalette.lightMode;
      final pairs = <(Color, Color)>[
        (palette.contentPrimary, palette.background),
        (palette.contentPrimary, palette.surface),
        (palette.contentSecondary, palette.surface),
        (palette.contentDisabled, palette.surfaceDisabled),
        (palette.contentDisabled, palette.surfaceSelected),
        (palette.brand, palette.background),
        (palette.success, palette.background),
        (palette.warning, palette.background),
        (palette.destructive, palette.background),
        (Colors.white, palette.brand),
      ];

      for (final (foreground, background) in pairs) {
        expect(
          _contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason:
              '${foreground.toARGB32().toRadixString(16)} on '
              '${background.toARGB32().toRadixString(16)}',
        );
      }
    });

    test('dark surfaces remain visibly ordered from background to border', () {
      final luminance = [
        Ep.background,
        Ep.surface,
        Ep.surfaceRaised,
        Ep.surfaceDisabled,
        Ep.surfaceSelected,
        Ep.border,
      ].map(_relativeLuminance).toList();

      for (var index = 1; index < luminance.length; index++) {
        expect(luminance[index], greaterThan(luminance[index - 1]));
      }
    });

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
  });

  group('shared components', () {
    testWidgets('controls expose disabled semantics and 48px tap targets', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EpButton('DISABLED', onTap: null),
              EpChip(label: 'punk', active: false, onTap: null),
              CircleIconButton(onTap: null, tooltip: 'Back'),
            ],
          ),
        ),
      );

      expect(tester.getSize(find.byType(FilledButton)).height, 48);
      expect(
        tester.getSize(find.byType(FilterChip)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
      final circleVisual = find.descendant(
        of: find.byType(CircleIconButton),
        matching: find.byType(Container),
      );
      expect(tester.getSize(circleVisual), const Size(32, 32));
      expect(find.byTooltip('Back'), findsOne);

      final buttonData = tester
          .getSemantics(find.byType(FilledButton))
          .getSemanticsData();
      expect(buttonData.flagsCollection.isEnabled, Tristate.isFalse);
      expect(buttonData.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('button has a visible keyboard-focus treatment and no glow', (
      tester,
    ) async {
      await tester.pumpWidget(_host(EpButton('PLUG IN', onTap: () {})));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final focusedSide = button.style!.side!.resolve({WidgetState.focused});
      expect(focusedSide, const BorderSide(color: Ep.contentPrimary, width: 2));
      expect(button.style!.shadowColor, isNull);
      expect(button.style!.elevation, isNull);
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });

    testWidgets(
      'selected navigation item is announced, 66px tall, and strongly marked',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var pressed = false;

        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 120,
              child: EpNavigationItem(
                icon: Icons.person_outline,
                label: 'PROFILE',
                selected: true,
                onPressed: () => pressed = true,
              ),
            ),
          ),
        );

        final node = tester.getSemantics(find.byType(EpNavigationItem));
        final data = node.getSemanticsData();
        expect(data.label, 'PROFILE');
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isSelected, Tristate.isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);

        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        expect(pressed, isTrue);

        expect(tester.getSize(find.byType(EpNavigationItem)).height, 66);
        expect(tester.widget<Text>(find.text('PROFILE')).style!.fontSize, 11);
        final indicator = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(EpNavigationItem),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(indicator.constraints!.maxWidth, 24);
        expect(indicator.constraints!.maxHeight, 2.5);
        expect((indicator.decoration! as BoxDecoration).color, Ep.brand);
        semantics.dispose();
      },
    );

    testWidgets('cards expose all semantic surface variants', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              EpCard(key: Key('standard'), child: Text('standard')),
              EpCard(
                key: Key('raised'),
                variant: EpCardVariant.raised,
                child: Text('raised'),
              ),
              EpCard(
                key: Key('selected'),
                variant: EpCardVariant.selected,
                child: Text('selected'),
              ),
              EpCard(
                key: Key('disabled'),
                variant: EpCardVariant.disabled,
                child: Text('disabled'),
              ),
            ],
          ),
        ),
      );

      expect(_cardColor(tester, 'standard'), Ep.surface);
      expect(_cardColor(tester, 'raised'), Ep.surfaceRaised);
      expect(_cardColor(tester, 'selected'), Ep.surfaceSelected);
      expect(_cardColor(tester, 'disabled'), Ep.surfaceDisabled);
    });

    testWidgets('profile avatars are upright and use accessible fallbacks', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EpProfileAvatar(name: 'Sam Reyes'),
              EpProfileAvatar(name: null),
            ],
          ),
        ),
      );

      expect(find.text('SR'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(EpProfileAvatar),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Sam Reyes avatar'))
            .getSemanticsData()
            .flagsCollection
            .isImage,
        isTrue,
      );
      semantics.dispose();
    });

    testWidgets('logo variants use the full lockup and compact ear asset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [EpLogo.full(), EpLogo.compact()],
          ),
        ),
      );

      final assets = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => (image.image as AssetImage).assetName);
      expect(
        assets,
        containsAll([
          'assets/images/listen_local_bw.png',
          'assets/images/earplug_mark.png',
        ]),
      );
    });

    testWidgets('logos keep their artwork dark and invert for light surfaces', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const EpLogo.full(), brightness: Brightness.dark),
      );
      expect(find.byType(ColorFiltered), findsNothing);

      await tester.pumpWidget(
        _host(const EpLogo.full(), brightness: Brightness.light),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ColorFiltered), findsOne);
      expect(find.byType(Image), findsOne);
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
      expect(
        tester.getSize(find.text('NEXT GIG RSVPS')).height,
        greaterThan(20),
      );
    });

    testWidgets('stat tiles accommodate accessibility text at both widths', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(402, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  child: EpStatCard(
                    label: 'Next gig RSVPs',
                    value: '12',
                    caption: 'Riptide Release Show',
                    expand: false,
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: EpStatCard(
                    label: 'Followers',
                    value: '486',
                    caption: 'and counting',
                    expand: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(EpStatCard), findsNWidgets(2));
      expect(
        tester.getSize(find.byType(EpStatCard).first).height,
        greaterThan(200),
      );
      expect(
        tester.getSize(find.byType(EpStatCard).last).height,
        greaterThan(150),
      );
      expect(tester.takeException(), isNull);
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
      app.dispose();
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
  });
}

Gig _gig({
  required String id,
  required String title,
  required String flyKey,
  required String flyerUrl,
}) => gigFixture(
  id: id,
  title: title,
  startsAt: DateTime(2026, 9, 1, 20),
  dateShort: 'TUE SEP 1',
  dateLine: 'TONIGHT · DOORS 8PM',
  time: '8PM',
  when: GigWhen.tonight,
  flyKey: flyKey,
  flyerUrl: flyerUrl,
);

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: buildEpTheme(brightness),
      darkTheme: buildEpTheme(Brightness.dark),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );

Color _cardColor(WidgetTester tester, String key) {
  final material = tester.widget<Material>(
    find
        .descendant(of: find.byKey(Key(key)), matching: find.byType(Material))
        .first,
  );
  return material.color!;
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = _relativeLuminance(foreground);
  final darker = _relativeLuminance(background);
  final high = lighter > darker ? lighter : darker;
  final low = lighter > darker ? darker : lighter;
  return (high + .05) / (low + .05);
}

double _relativeLuminance(Color color) {
  final argb = color.toARGB32();
  final channels = [
    (argb >> 16 & 0xff) / 255,
    (argb >> 8 & 0xff) / 255,
    (argb & 0xff) / 255,
  ];
  final linear = channels
      .map(
        (value) => value <= .04045
            ? value / 12.92
            : math.pow((value + .055) / 1.055, 2.4).toDouble(),
      )
      .toList();
  return .2126 * linear[0] + .7152 * linear[1] + .0722 * linear[2];
}
