import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:earplug/theme.dart';
import 'package:earplug/widgets/branding.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

    testWidgets('selected navigation item is announced and strongly marked', (
      tester,
    ) async {
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

      final indicator = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(EpNavigationItem),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((indicator.single.decoration! as BoxDecoration).color, Ep.brand);
      semantics.dispose();
    });

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
  });
}

Widget _host(Widget child) => MaterialApp(
  theme: buildEpTheme(),
  home: Scaffold(body: Center(child: child)),
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
