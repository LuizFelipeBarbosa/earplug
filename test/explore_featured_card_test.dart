import 'package:earplug/app_state.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/pump.dart';

void main() {
  group('ExploreFeaturedCard', () {
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

    testWidgets('compact and featured cards have no ticket pills', (
      tester,
    ) async {
      await pumpApp(
        tester,
        home: Scaffold(
          body: Consumer<AppState>(
            builder: (context, app, _) => FanEventCard(
              gig: gigFixture(id: 'compact-no-ticket'),
              app: app,
            ),
          ),
        ),
      );
      expect(find.byType(EpPill), findsNothing);
      await tester.pumpWidget(
        plain(
          ExploreFeaturedCard(
            gig: gigFixture(id: 'featured-no-ticket'),
            venueName: 'The Foghorn',
            lines: const GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: 'featured-no-ticket',
              location: 'Southside',
              price: 'FREE',
            ),
            onTap: () {},
          ),
        ),
      );
      expect(find.byType(EpPill), findsNothing);
    });

    testWidgets(
      'featured card renders three lines and price without date blocks or lineup',
      (tester) async {
        const lines = GigCardLines(
          dateLine: 'WED, SEP 23 AT 8PM',
          title: 'Featured Event',
          location: 'Southside · 11.2 mi',
          price: 'free',
        );
        final gig = gigFixture(id: 'featured-lines', title: lines.title);
        await tester.pumpWidget(
          plain(
            ExploreFeaturedCard(
              gig: gig,
              venueName: 'The Foghorn',
              lines: lines,
              onTap: () {},
              width: 334,
              height: 200,
            ),
          ),
        );
        expect(find.text(lines.dateLine), findsOneWidget);
        expect(find.text(lines.title.toUpperCase()), findsOneWidget);
        expect(find.text(lines.location), findsOneWidget);
        expect(find.text('FREE'), findsOneWidget);
        expect(find.byKey(ValueKey('gig-price-${gig.id}')), findsOneWidget);
        expect(find.byType(EpDateBlock), findsNothing);
        expect(find.byType(EpAvatarTile), findsNothing);
        final date = tester.getRect(find.text(lines.dateLine));
        final title = tester.getRect(find.text(lines.title.toUpperCase()));
        final location = tester.getRect(find.text(lines.location));
        final price = tester.getRect(find.byKey(ValueKey('gig-price-${gig.id}')));
        expect(title.top - date.bottom, closeTo(8, 0.1));
        expect(price.top - title.bottom, closeTo(6, 0.1));
        expect(location.center.dy, closeTo(price.center.dy, 0.1));
      },
    );

    testWidgets(
      'featured three-line typography and price match in both layouts',
      (tester) async {
        for (final brightness in Brightness.values) {
          for (final flyKey in ['paper', 'panel']) {
            for (final size in [const Size(300, 380), const Size(334, 200)]) {
              final gig = gigFixture(
                id: 'featured-styles',
                title: 'Featured Event',
                flyKey: flyKey,
              );
              await tester.pumpWidget(
                plain(
                  ExploreFeaturedCard(
                    gig: gig,
                    venueName: 'The Foghorn',
                    lines: GigCardLines(
                      dateLine: 'WED, SEP 23 AT 8PM',
                      title: gig.title,
                      location: 'Southside · 11.2 mi',
                      price: gig.priceLabel,
                    ),
                    onTap: () {},
                    width: size.width,
                    height: size.height,
                  ),
                  brightness: brightness,
                ),
              );
              final date = tester.widget<Text>(find.text('WED, SEP 23 AT 8PM'));
              expect(date.style?.fontFamily, 'Azeret Mono');
              expect(date.style?.fontSize, 12);
              expect(date.style?.fontWeight, FontWeight.w400);
              expect(date.style?.color, Ep.ink.withValues(alpha: 0.72));
              expect(date.maxLines, 1);
              expect(date.overflow, TextOverflow.ellipsis);
              final display = tester.widget<EpDisplay>(find.byType(EpDisplay));
              expect(display.text, gig.title);
              expect(display.size, 24);
              expect(display.maxLines, 2);
              expect(display.overflow, TextOverflow.ellipsis);
              expect(display.color, Ep.ink);
              final location = tester.widget<Text>(
                find.text('Southside · 11.2 mi'),
              );
              expect(location.style?.fontFamily, 'PP Telegraf');
              expect(location.style?.fontSize, 14);
              expect(location.style?.color, Ep.ink.withValues(alpha: 0.85));
              expect(location.maxLines, 1);
              expect(location.overflow, TextOverflow.ellipsis);
              final price = tester.widget<Container>(
                find.byKey(ValueKey('gig-price-${gig.id}')),
              );
              final palette = tester
                  .element(find.byType(ExploreFeaturedCard))
                  .epColors;
              expect(price.color, palette.accent);
              expect(price.decoration, isNull);
              expect(
                price.padding,
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              );
              final label = price.child! as Text;
              expect(label.data, 'FREE');
              expect(label.style?.fontFamily, 'Azeret Mono');
              expect(label.style?.fontSize, 13);
              expect(label.style?.color, palette.onAccent);
              final scrim = tester.widget<DecoratedBox>(
                find.descendant(
                  of: find.byType(ExploreFeaturedCard),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is DecoratedBox &&
                        widget.decoration is BoxDecoration &&
                        (widget.decoration as BoxDecoration).gradient
                            is LinearGradient,
                  ),
                ),
              );
              final gradient =
                  (scrim.decoration as BoxDecoration).gradient! as LinearGradient;
              expect(gradient.colors, [
                Ep.background.withValues(alpha: 0),
                Ep.background.withValues(alpha: .94),
              ]);
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );

    testWidgets(
      'featured fan actions use black circles and white glyphs for every artwork',
      (tester) async {
        for (final artwork in [
          (flyKey: 'paper', url: null),
          (flyKey: 'panel', url: ''),
          (flyKey: 'accent', url: null),
          (flyKey: 'unknown', url: null),
          (flyKey: 'paper', url: 'https://example.com/flyer.jpg'),
        ]) {
          final gig = gigFixture(
            id: 'featured-action-contrast',
            title: 'Featured Event',
            startsAt: DateTime(2026, 9, 23),
            flyKey: artwork.flyKey,
            flyerUrl: artwork.url,
          );
          await pumpApp(
            tester,
            home: Scaffold(
              body: Consumer<AppState>(
                builder: (context, app, _) => FanEventCard(
                  gig: gig,
                  app: app,
                  presentation: FanEventCardPresentation.featured,
                ),
              ),
            ),
          );
          expect(find.byKey(ValueKey('fan-event-${gig.id}')), findsOneWidget);
          for (final action in ['share', 'save']) {
            final button = find.byKey(ValueKey('$action-${gig.id}'));
            final widget = tester.widget<ExploreCardIconButton>(button);
            expect(widget.circle, isTrue);
            expect(widget.ring, isFalse);
            final glyph = tester.widget<Icon>(
              find.descendant(of: button, matching: find.byType(Icon)),
            );
            expect(glyph.color, Ep.ink);
            expect(glyph.size, 20);
            expect(glyph.shadows, isNull);
            final circle = tester.widget<DecoratedBox>(
              find.descendant(of: button, matching: find.byType(DecoratedBox)),
            );
            final decoration = circle.decoration as BoxDecoration;
            expect(decoration.color, Ep.background);
            expect(decoration.shape, BoxShape.circle);
            expect(decoration.border, isNull);
          }
          expect(find.byIcon(Icons.bookmark), findsNothing);
          expect(find.text('WED, SEP 23 AT 8PM'), findsOneWidget);
          expect(find.text('FREE'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('featured card uses generated flyer without duplicating title', (
      tester,
    ) async {
      final gig = gigFixture(
        id: 'featured-generated-flyer',
        title: 'Generated Flyer Event',
        flyerUrl: null,
      );
      await tester.pumpWidget(
        plain(
          ExploreFeaturedCard(
            gig: gig,
            venueName: 'The Foghorn',
            lines: GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: gig.title,
              location: 'Southside · 11.2 mi',
              price: gig.priceLabel,
            ),
            onTap: () {},
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(ExploreFeaturedCard),
          matching: find.byType(GigFlyer),
        ),
        findsOneWidget,
      );
      expect(find.text('GENERATED FLYER EVENT'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ExploreFeaturedCard),
          matching: find.byType(EpDateBlock),
        ),
        findsNothing,
      );
    });

    testWidgets('featured card shows details and taps', (tester) async {
      var tapped = false;
      for (final tix in Ticketing.values) {
        await tester.pumpWidget(
          plain(
            ExploreFeaturedCard(
              gig: gigFixture(
                id: 'featured-${tix.name}',
                title: 'A Long Featured Event Title',
                time: '8PM / 9PM',
                tix: tix,
              ),
              venueName: 'The Foghorn',
              lines: const GigCardLines(
                dateLine: 'WED, SEP 23 AT 8PM',
                title: 'A Long Featured Event Title',
                location: 'Southside',
                price: 'FREE',
              ),
              onTap: () => tapped = true,
            ),
          ),
        );
        expect(find.text('A LONG FEATURED EVENT TITLE'), findsOneWidget);
        expect(find.text('WED, SEP 23 AT 8PM'), findsOneWidget);
        expect(find.text('Southside'), findsOneWidget);
        expect(find.text('RSVP'), findsNothing);
        expect(find.text('TICKETS'), findsNothing);
        expect(find.text('GOING'), findsNothing);
        await tester.tap(find.text('A LONG FEATURED EVENT TITLE'));
      }
      expect(tapped, isTrue);
    });

    testWidgets(
      'featured circle actions sit at the top-right with a four-pixel gap',
      (tester) async {
        final gig = gigFixture(
          id: 'featured-action-corners',
          title: 'Live Music',
        );
        for (final width in [360.0, 240.0]) {
          await tester.pumpWidget(
            plain(
              Center(
                child: ExploreFeaturedCard(
                  gig: gig,
                  venueName: 'The Foghorn',
                  lines: GigCardLines(
                    dateLine: 'WED, SEP 23 AT 8PM',
                    title: gig.title,
                    location: 'Southside · 11.2 mi',
                    price: gig.priceLabel,
                  ),
                  width: width,
                  height: 180,
                  actions: [
                    ExploreCardIconButton(
                      key: const Key('featured-share'),
                      icon: Icons.ios_share,
                      semanticLabel: 'Share event',
                      circle: true,
                      onPressed: () {},
                    ),
                    ExploreCardIconButton(
                      key: const Key('featured-save'),
                      icon: Icons.bookmark_border,
                      fillIcon: Icons.bookmark,
                      semanticLabel: 'Save event',
                      circle: true,
                      onPressed: () {},
                    ),
                  ],
                  onTap: () {},
                ),
              ),
              textScaler: TextScaler.linear(1.5),
            ),
          );
          expect(tester.takeException(), isNull, reason: 'width $width');
          final card = tester.getRect(find.byType(ExploreFeaturedCard));
          final save = tester.getRect(find.byKey(const Key('featured-save')));
          final share = tester.getRect(find.byKey(const Key('featured-share')));
          for (final action in [save, share]) {
            expect(action.top - card.top, closeTo(8, 0.1));
            expect(action.size, const Size(36, 36));
          }
          expect(card.right - save.right, closeTo(8, 0.1));
          expect(save.left - share.right, closeTo(4, 0.1));
        }
      },
    );

    testWidgets('landscape featured card fits its three lines at 1.0 and 1.5', (
      tester,
    ) async {
      final gig = gigFixture(
        id: 'featured-landscape',
        title: 'A Very Long Featured Event Title That Needs Trimming',
        time: '8PM / 9PM',
        tix: Ticketing.paid,
      );
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(
          plain(
            ExploreFeaturedCard(
              gig: gig,
              venueName: 'A Venue With A Long Name',
              lines: GigCardLines(
                dateLine: 'WED, SEP 23 AT 8PM',
                title: gig.title,
                location: 'Southside · 11.2 mi',
                price: gig.priceLabel,
              ),
              onTap: () {},
              width: 334,
              height: 200,
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'scale $scale');
        final card = tester.getRect(find.byType(ExploreFeaturedCard));
        expect(card.size, const Size(334, 200));
        expect(find.text(gig.title.toUpperCase()), findsOneWidget);
        expect(find.text('WED, SEP 23 AT 8PM'), findsOneWidget);
        expect(find.text('Southside · 11.2 mi'), findsOneWidget);
        expect(find.text('TICKETS'), findsNothing);
        final date = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
        final price = tester.getRect(find.byKey(ValueKey('gig-price-${gig.id}')));
        expect(date.top, greaterThanOrEqualTo(card.top));
        expect(price.bottom, lessThanOrEqualTo(card.bottom - 16));
      }
    });
  });
}
