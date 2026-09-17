import 'package:earplug/theme.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/pump.dart';

void main() {
  group('ExploreCardIconButton', () {
    Widget plain(
      Widget child, {
      TextScaler? textScaler,
      Brightness brightness = Brightness.dark,
    }) => epApp(
      child,
      brightness: brightness,
      media: MediaQueryData(
        size: const Size(400, 800),
        textScaler: textScaler ?? TextScaler.noScaling,
      ),
      mediaOutsideScaffold: true,
    );

    testWidgets('card icon button layers the fill beneath the ink outline', (
      tester,
    ) async {
      for (final active in [false, true]) {
        await tester.pumpWidget(
          plain(
            Center(
              child: ExploreCardIconButton(
                icon: Icons.bookmark_border,
                fillIcon: Icons.bookmark,
                semanticLabel: 'Save event',
                active: active,
                onPressed: () {},
              ),
            ),
          ),
        );
        final button = find.byType(ExploreCardIconButton);
        final colors = tester.element(button).epColors;
        final fill = tester.widget<Icon>(find.byIcon(Icons.bookmark));
        final outline = tester.widget<Icon>(find.byIcon(Icons.bookmark_border));
        expect(
          fill.color,
          active
              ? colors.accent.withValues(alpha: 0.60)
              : colors.ink.withValues(alpha: 0.22),
        );
        expect(fill.color!.a, closeTo(active ? 0.60 : 0.22, 0.001));
        expect(outline.color, colors.ink);
        expect(outline.color!.a, 1);
        expect(fill.size, 16);
        expect(outline.size, 16);
        expect(tester.getSize(button), const Size(28, 28));
        expect(
          tester.getRect(find.byIcon(Icons.bookmark)),
          tester.getRect(find.byIcon(Icons.bookmark_border)),
        );
        final layers = tester.widget<Stack>(
          find.descendant(of: button, matching: find.byType(Stack)),
        );
        expect((layers.children.first as Icon).icon, Icons.bookmark);
        expect((layers.children.last as Icon).icon, Icons.bookmark_border);
      }
    });

    testWidgets('non-ring action color tints both layers and shadows the glyph', (
      tester,
    ) async {
      final shadows = [
        Shadow(color: Ep.background.withValues(alpha: 0.60), blurRadius: 4),
      ];
      for (final active in [false, true]) {
        await tester.pumpWidget(
          plain(
            Center(
              child: ExploreCardIconButton(
                icon: Icons.bookmark_border,
                fillIcon: Icons.bookmark,
                semanticLabel: 'Save event',
                active: active,
                color: Ep.ink,
                iconShadows: shadows,
                onPressed: () {},
              ),
            ),
            brightness: Brightness.light,
          ),
        );
        final fill = tester.widget<Icon>(find.byIcon(Icons.bookmark));
        final outline = tester.widget<Icon>(find.byIcon(Icons.bookmark_border));
        expect(fill.color, Ep.ink.withValues(alpha: active ? 0.60 : 0.22));
        expect(fill.shadows, isNull);
        expect(outline.color, Ep.ink);
        expect(outline.shadows, shadows);
      }
    });

    testWidgets('ring actions stay unfilled in both themes and all states', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        for (final enabled in [false, true]) {
          for (final active in [false, true]) {
            await tester.pumpWidget(
              plain(
                Center(
                  child: ExploreCardIconButton(
                    icon: Icons.bookmark_border,
                    fillIcon: Icons.bookmark,
                    semanticLabel: 'Save event',
                    ring: true,
                    active: active,
                    color: Ep.ink,
                    iconShadows: const [Shadow(color: Ep.background)],
                    onPressed: enabled ? () {} : null,
                  ),
                ),
                brightness: brightness,
              ),
            );
            final button = find.byType(ExploreCardIconButton);
            final palette = tester.element(button).epColors;
            final outline = tester.widget<Icon>(
              find.byIcon(Icons.bookmark_border),
            );
            expect(find.byIcon(Icons.bookmark), findsNothing);
            expect(
              find.descendant(of: button, matching: find.byType(Stack)),
              findsNothing,
            );
            expect(
              outline.color,
              !enabled
                  ? palette.contentDisabled
                  : active
                  ? palette.accent
                  : palette.muted,
            );
            expect(outline.shadows, isNull);
            final ring = tester.widget<DecoratedBox>(
              find.descendant(of: button, matching: find.byType(DecoratedBox)),
            );
            final decoration = ring.decoration as ShapeDecoration;
            expect(decoration.color, isNull);
            expect(
              (decoration.shape as CircleBorder).side,
              BorderSide(color: palette.line, width: 1),
            );
          }
        }
      }
    });

    testWidgets('card icon button has a flush 36px ring and a 44px target', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        plain(
          Center(
            child: ExploreCardIconButton(
              icon: Icons.bookmark_border,
              fillIcon: Icons.bookmark,
              semanticLabel: 'Save event',
              ring: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      final button = find.byType(ExploreCardIconButton);
      final buttonRect = tester.getRect(button);
      final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
      final semantics = find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Save event',
        ),
      );
      expect(buttonRect.size, const Size(36, 36));
      expect(tester.getSize(inkWell), const Size(44, 44));
      expect(tester.getRect(inkWell), buttonRect.inflate(4));
      expect(tester.getRect(semantics), buttonRect.inflate(4));
      final ring = find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && widget.decoration is ShapeDecoration,
        ),
      );
      final decoration =
          tester.widget<DecoratedBox>(ring).decoration as ShapeDecoration;
      expect(decoration.color, isNull);
      expect((decoration.shape as CircleBorder).side.width, 1);
      expect(tester.getRect(ring).top, closeTo(buttonRect.top, 0.5));
      expect(tester.getSize(ring), const Size(36, 36));
      await tester.tap(button);
      expect(taps, 1);
      for (final offset in const [
        Offset(-21, 0),
        Offset(21, 0),
        Offset(0, -21),
        Offset(0, 21),
      ]) {
        await tester.tapAt(buttonRect.center + offset);
      }
      expect(taps, 5);
    });

    testWidgets('circle action keeps its white glyph and 44px tap target', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        plain(
          Center(
            child: ExploreCardIconButton(
              icon: Icons.bookmark_border,
              fillIcon: Icons.bookmark,
              semanticLabel: 'Save event',
              circle: true,
              active: true,
              color: Ep.accent,
              iconShadows: const [Shadow(color: Ep.accent)],
              onPressed: () => taps++,
            ),
          ),
          brightness: Brightness.light,
        ),
      );
      final button = find.byType(ExploreCardIconButton);
      final buttonRect = tester.getRect(button);
      final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
      expect(buttonRect.size, const Size(36, 36));
      expect(tester.getRect(inkWell), buttonRect.inflate(4));
      final circle = find.descendant(
        of: button,
        matching: find.byType(DecoratedBox),
      );
      final decoration =
          tester.widget<DecoratedBox>(circle).decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, Ep.background);
      expect(decoration.border, isNull);
      expect(tester.getRect(circle), buttonRect);
      expect(
        find.descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox && widget.decoration is ShapeDecoration,
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: button, matching: find.byType(Stack)),
        findsNothing,
      );
      expect(find.byIcon(Icons.bookmark), findsNothing);
      final glyph = tester.widget<Icon>(find.byIcon(Icons.bookmark_border));
      expect(glyph.size, 20);
      expect(glyph.color, Ep.ink);
      expect(glyph.shadows, isNull);
      expect(
        tester.getCenter(find.byIcon(Icons.bookmark_border)),
        buttonRect.center,
      );
      await tester.tap(button);
      for (final offset in const [
        Offset(-21, 0),
        Offset(21, 0),
        Offset(0, -21),
        Offset(0, 21),
      ]) {
        await tester.tapAt(buttonRect.center + offset);
      }
      expect(taps, 5);
    });

    testWidgets('ring and circle visuals are 36px with centered 44px targets', (
      tester,
    ) async {
      for (final ring in [true, false]) {
        await tester.pumpWidget(
          plain(
            Center(
              child: ExploreCardIconButton(
                icon: Icons.bookmark_border,
                semanticLabel: 'Save event',
                ring: ring,
                circle: !ring,
                onPressed: () {},
              ),
            ),
          ),
        );
        final button = find.byType(ExploreCardIconButton);
        final visual = find.descendant(
          of: button,
          matching: find.byType(DecoratedBox),
        );
        final target = find.descendant(
          of: button,
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(button), const Size(36, 36));
        expect(tester.getRect(visual), tester.getRect(button));
        expect(
          tester.getSize(find.byIcon(Icons.bookmark_border)),
          const Size(20, 20),
        );
        expect(tester.getSize(target), const Size(44, 44));
        expect(tester.getCenter(target), tester.getCenter(button));
      }
    });

    testWidgets('card actions receive overflow taps without opening the gig', (
      tester,
    ) async {
      final gig = gigFixture(id: 'action-hit-targets');
      for (final featured in [false, true]) {
        var saves = 0;
        var shares = 0;
        var opens = 0;
        final save = ExploreCardIconButton(
          key: const Key('hit-save'),
          icon: Icons.bookmark_border,
          fillIcon: Icons.bookmark,
          semanticLabel: 'Save event',
          ring: !featured,
          circle: featured,
          onPressed: () => saves++,
        );
        await tester.pumpWidget(
          plain(
            Center(
              child: SizedBox(
                width: 320,
                child: featured
                    ? ExploreFeaturedCard(
                        gig: gig,
                        venueName: 'The Foghorn',
                        lines: GigCardLines(
                          dateLine: 'WED, SEP 23 AT 8PM',
                          title: gig.title,
                          location: 'Southside · 11.2 mi',
                          price: gig.priceLabel,
                        ),
                        width: 320,
                        height: 200,
                        actions: [
                          ExploreCardIconButton(
                            key: const Key('hit-share'),
                            icon: Icons.ios_share,
                            semanticLabel: 'Share event',
                            circle: true,
                            onPressed: () => shares++,
                          ),
                          save,
                        ],
                        onTap: () => opens++,
                      )
                    : ExploreEventRow(
                        gig: gig,
                        venueName: 'The Foghorn',
                        lines: GigCardLines(
                          dateLine: 'WED, SEP 23 AT 8PM',
                          title: gig.title,
                          location: 'Southside · 11.2 mi',
                          price: gig.priceLabel,
                        ),
                        saveAction: save,
                        onTap: () => opens++,
                      ),
              ),
            ),
          ),
        );
        final saveRect = tester.getRect(find.byKey(const Key('hit-save')));
        for (final offset in [
          featured ? const Offset(21, 0) : const Offset(-21, 0),
          const Offset(0, -21),
          const Offset(0, 21),
        ]) {
          await tester.tapAt(saveRect.center + offset);
        }
        expect(saves, 3);
        if (featured) {
          final shareRect = tester.getRect(find.byKey(const Key('hit-share')));
          for (final offset in const [
            Offset(-21, 0),
            Offset(0, -21),
            Offset(0, 21),
          ]) {
            await tester.tapAt(shareRect.center + offset);
          }
          expect(shares, 3);
          // The overlapping part of the targets belongs to the nearest button.
          await tester.tapAt(shareRect.center + const Offset(21, 0));
          expect(saves, 4);
          expect(shares, 3);
        } else {
          await tester.tapAt(saveRect.center);
          expect(saves, 4);
          expect(shares, 0);
          expect(find.byIcon(Icons.ios_share), findsNothing);
        }
        expect(opens, 0);
        await tester.tap(find.text(gig.title.toUpperCase()));
        expect(opens, 1);
      }
    });

    testWidgets('disabled share button has only its outline and no ring', (
      tester,
    ) async {
      await tester.pumpWidget(
        plain(
          const Center(
            child: ExploreCardIconButton(
              icon: Icons.ios_share,
              semanticLabel: 'Share event',
              onPressed: null,
            ),
          ),
        ),
      );
      final button = find.byType(ExploreCardIconButton);
      expect(
        find.descendant(of: button, matching: find.byType(Icon)),
        findsOneWidget,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.ios_share)).color,
        tester.element(button).epColors.contentDisabled,
      );
      expect(
        find.descendant(of: button, matching: find.byType(DecoratedBox)),
        findsNothing,
      );
      final semantics = tester.widget<Semantics>(
        find.descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'Share event',
          ),
        ),
      );
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.enabled, isFalse);
    });
  });
}
