import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/pump.dart';

void main() {
  group('ExploreEventRow', () {
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

    testWidgets('event row shows three lines, generated flyer, and taps', (
      tester,
    ) async {
      var tapped = false;
      final gig = gigFixture(
        id: 'event-row',
        title: 'Neon Nights',
        startsAt: DateTime(2026, 9, 23),
      );
      await tester.pumpWidget(
        plain(
          ExploreEventRow(
            gig: gig,
            venueName: 'The Foghorn',
            lines: GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: gig.title,
              location: 'Southside · 11.2 mi',
              price: gig.priceLabel,
            ),
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.text('NEON NIGHTS'), findsOneWidget);
      expect(find.byType(GigFlyer), findsOneWidget);
      expect(find.text('NN'), findsNothing);
      expect(find.text('WED, SEP 23 AT 8PM'), findsOneWidget);
      expect(find.text('Southside · 11.2 mi'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
      final dateRect = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
      final titleRect = tester.getRect(find.text('NEON NIGHTS'));
      final locationRect = tester.getRect(find.text('Southside · 11.2 mi'));
      final priceRect = tester.getRect(
        find.byKey(ValueKey('gig-price-${gig.id}')),
      );
      expect(titleRect.top - dateRect.bottom, closeTo(8, 0.1));
      expect(priceRect.top - titleRect.bottom, closeTo(8, 0.1));
      expect(locationRect.center.dy, closeTo(priceRect.center.dy, 0.1));
      await tester.tap(find.text('NEON NIGHTS'));
      expect(tapped, isTrue);

      await tester.pumpWidget(
        plain(
          ExploreEventRow(
            gig: gigFixture(id: 'paid-row', title: 'Paid Night', price: 12),
            venueName: 'The Foghorn',
            lines: const GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: 'Paid Night',
              location: 'Southside',
              price: '\$12',
            ),
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('FREE'), findsNothing);
      expect(find.text('\$12'), findsOneWidget);
    });

    testWidgets('cancelled event row shows the CANCELLED marker', (tester) async {
      final gig = gigFixture(
        id: 'cancelled-row',
        title: 'Cancelled Show',
        lifecycle: GigLifecycle.cancelled,
      );
      await tester.pumpWidget(
        plain(
          ExploreEventRow(
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
      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.byKey(ValueKey('gig-cancelled-${gig.id}')), findsOneWidget);
    });

    testWidgets('event row shows a hairline by default', (tester) async {
      final gig = gigFixture(id: 'hairline-row', title: 'Live Music');
      await tester.pumpWidget(
        plain(
          ExploreEventRow(
            gig: gig,
            venueName: 'The Foghorn',
            lines: GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: gig.title,
              location: 'Southside',
              price: gig.priceLabel,
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.byType(EpHairline), findsOneWidget);
      expect(find.text('LIVE MUSIC'), findsOneWidget);
    });

    testWidgets('event row can hide its hairline while preserving content', (
      tester,
    ) async {
      final gig = gigFixture(id: 'hairline-row', title: 'Live Music');
      await tester.pumpWidget(
        plain(
          ExploreEventRow(
            gig: gig,
            venueName: 'The Foghorn',
            lines: GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: gig.title,
              location: 'Southside',
              price: gig.priceLabel,
            ),
            onTap: () {},
            showHairline: false,
          ),
        ),
      );

      expect(find.byType(EpHairline), findsNothing);
      expect(find.text('LIVE MUSIC'), findsOneWidget);
    });

    testWidgets('event row supports supplied lines, sub, and thumbnail size', (
      tester,
    ) async {
      final gig = gigFixture(id: 'custom-lines-row');
      const sub = 'Maya and Dev are going';
      await tester.pumpWidget(
        plain(
          ExploreEventRow(
            gig: gig,
            venueName: 'The Foghorn',
            lines: GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: gig.title,
              location: 'Southside · 11.2 mi',
              price: gig.priceLabel,
            ),
            sub: sub,
            thumbnailSize: 72.5,
            onTap: () {},
          ),
        ),
      );
      final dateText = tester.widget<Text>(find.text('WED, SEP 23 AT 8PM'));
      expect(dateText.maxLines, 1);
      expect(dateText.overflow, TextOverflow.ellipsis);
      expect(find.textContaining('The Foghorn'), findsNothing);
      final subText = tester.widget<Text>(find.text(sub));
      expect(subText.maxLines, 1);
      expect(subText.overflow, TextOverflow.ellipsis);
      expect(
        subText.style?.color,
        tester.element(find.byType(ExploreEventRow)).epColors.muted,
      );
      expect(
        tester.getRect(find.text(sub)).top,
        greaterThan(
          tester.getRect(find.byKey(ValueKey('gig-price-${gig.id}'))).bottom,
        ),
      );
      final thumbnail = find.byType(EpNetworkImage);
      final thumbnailSize = tester.getSize(thumbnail);
      final rowHeight = tester.getSize(find.byType(ExploreEventRow)).height;
      expect(thumbnailSize.width, 72.5);
      expect(thumbnailSize.height, closeTo(rowHeight - 25, 0.1));
      final image = tester.widget<EpNetworkImage>(thumbnail);
      expect(image.cacheWidth, 73);
      expect(image.cacheHeight, isNull);
    });

    testWidgets('event row thumbnail matches its natural text column height', (
      tester,
    ) async {
      for (final title in [
        'Live Music',
        'A Long Event Title That Wraps Across Several Lines',
      ]) {
        final gig = gigFixture(id: 'content-height-row', title: title);
        await tester.pumpWidget(
          plain(
            SizedBox(
              width: 320,
              child: ExploreEventRow(
                gig: gig,
                venueName: 'The Foghorn',
                lines: GigCardLines(
                  dateLine: 'WED, SEP 23 AT 8PM',
                  title: gig.title,
                  location: 'Southside',
                  price: gig.priceLabel,
                ),
                onTap: () {},
              ),
            ),
          ),
        );
        final thumbnail = find.byType(EpNetworkImage);
        final textColumn = find.descendant(
          of: find.byType(ExploreEventRow),
          matching: find.byWidgetPredicate(
            (widget) => widget is Expanded && widget.child is Column,
          ),
        );
        final thumbnailRect = tester.getRect(thumbnail);
        final textRect = tester.getRect(textColumn);
        final dateRect = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
        final priceRect = tester.getRect(
          find.byKey(ValueKey('gig-price-${gig.id}')),
        );
        expect(thumbnailRect.width, 96);
        expect(thumbnailRect.height, closeTo(textRect.height, 0.1));
        expect(thumbnailRect.top, closeTo(textRect.top, 0.1));
        expect(textRect.top, closeTo(dateRect.top, 0.1));
        expect(textRect.bottom, closeTo(priceRect.bottom, 0.1));
        expect(tester.widget<EpNetworkImage>(thumbnail).fit, BoxFit.cover);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('event imagery uses flyer photos for every fly key', (
      tester,
    ) async {
      const flyerUrl = 'https://example.com/flyer.jpg';
      final gig = gigFixture(
        id: 'photo-row',
        title: 'Photo Event',
        flyKey: 'paper',
        flyerUrl: flyerUrl,
      );
      await tester.pumpWidget(
        plain(
          Column(
            children: [
              ExploreEventRow(
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
            ],
          ),
        ),
      );

      final images = tester.widgetList<EpNetworkImage>(
        find.byType(EpNetworkImage),
      );
      expect(images, hasLength(2));
      expect(images.every((image) => image.url == flyerUrl), isTrue);
    });

    testWidgets('event row puts its save action at the end of the date line', (
      tester,
    ) async {
      final gig = gigFixture(id: 'poster-actions', title: 'Live Music');
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(
          plain(
            SizedBox(
              width: 300,
              child: ExploreEventRow(
                gig: gig,
                venueName: 'The Foghorn',
                lines: GigCardLines(
                  dateLine: 'WED, SEP 23 AT 8PM',
                  title: gig.title,
                  location: 'Southside · 11.2 mi',
                  price: gig.priceLabel,
                ),
                saveAction: ExploreCardIconButton(
                  key: const Key('poster-save'),
                  icon: Icons.bookmark_border,
                  semanticLabel: 'Save event',
                  ring: true,
                  onPressed: () {},
                ),
                onTap: () {},
              ),
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );
        final row = tester.getRect(find.byType(ExploreEventRow));
        final date = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
        final action = tester.getRect(find.byKey(const Key('poster-save')));
        expect(action.top, closeTo(date.top, 0.1));
        expect(date.right, lessThanOrEqualTo(action.left + 0.1));
        expect(action.right, closeTo(row.right, 0.1));
        expect(tester.takeException(), isNull, reason: 'scale $scale');
      }
    });

    testWidgets('event row never renders a chevron or share action', (
      tester,
    ) async {
      final gig = gigFixture(id: 'actions-no-chevron', title: 'Action Event');
      for (final withSave in [false, true]) {
        await tester.pumpWidget(
          plain(
            ExploreEventRow(
              gig: gig,
              venueName: 'The Foghorn',
              lines: GigCardLines(
                dateLine: 'WED, SEP 23 AT 8PM',
                title: gig.title,
                location: 'Southside · 11.2 mi',
                price: gig.priceLabel,
              ),
              saveAction: withSave
                  ? ExploreCardIconButton(
                      icon: Icons.bookmark_border,
                      semanticLabel: 'Save event',
                      ring: true,
                      onPressed: () {},
                    )
                  : null,
              onTap: () {},
            ),
          ),
        );
        expect(find.byIcon(Icons.chevron_right), findsNothing);
        expect(find.byIcon(Icons.ios_share), findsNothing);
      }
    });

    testWidgets('event row wraps a long title with the original date gap', (
      tester,
    ) async {
      const title =
          'A Very Long Event Title That Must Wrap Within A Narrow Card Width';
      final gig = gigFixture(id: 'long-title-actions', title: title, price: 15);
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(
          plain(
            SizedBox(
              width: 300,
              child: ExploreEventRow(
                gig: gig,
                venueName: 'The Foghorn',
                lines: GigCardLines(
                  dateLine: 'WED, SEP 23 AT 8PM',
                  title: gig.title,
                  location: 'Southside · 11.2 mi',
                  price: gig.priceLabel,
                ),
                saveAction: ExploreCardIconButton(
                  icon: Icons.bookmark_border,
                  semanticLabel: 'Save event',
                  ring: true,
                  onPressed: () {},
                ),
                onTap: () {},
              ),
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'scale $scale');
        final titleFinder = find.text(title.toUpperCase());
        final titleText = tester.widget<Text>(titleFinder);
        expect(tester.getSize(titleFinder).height, greaterThan(24));
        expect(titleText.softWrap, isTrue);
        expect(titleText.style?.fontSize, 18);
        expect(titleText.overflow, TextOverflow.clip);
        final titleRect = tester.getRect(titleFinder);
        final dateRect = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
        expect(titleRect.top - dateRect.bottom, closeTo(8, 0.1));
        expect(titleRect.left, closeTo(dateRect.left, 0.1));
        final buttonRect = tester.getRect(find.byType(ExploreCardIconButton));
        expect(titleRect.right, lessThanOrEqualTo(buttonRect.left + 0.1));
      }
    });

    testWidgets(
      'event row uses a regular mono date, muted location, and an accent paid price',
      (tester) async {
        final gig = gigFixture(id: 'structured-lines', price: 12);
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            plain(
              ExploreEventRow(
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
              brightness: brightness,
            ),
          );
          final row = find.byType(ExploreEventRow);
          final palette = tester.element(row).epColors;
          final date = tester.widget<Text>(find.text('WED, SEP 23 AT 8PM'));
          expect(date.textSpan, isNull);
          expect(date.style?.fontFamily, 'Azeret Mono');
          expect(date.style?.fontSize, 11);
          expect(date.style?.fontWeight, FontWeight.w400);
          expect(date.style?.color, palette.muted);
          expect(date.maxLines, 1);
          expect(date.overflow, TextOverflow.ellipsis);
          final location = tester.widget<Text>(find.text('Southside · 11.2 mi'));
          expect(
            location.style,
            Theme.of(
              tester.element(row),
            ).textTheme.epCaption.copyWith(color: palette.muted),
          );
          expect(location.maxLines, 1);
          expect(location.overflow, TextOverflow.ellipsis);
          final price = tester.widget(
            find.byKey(ValueKey('gig-price-${gig.id}')),
          );
          expect(price, isA<Container>());
          expect((price as Container).color, palette.accent);
          expect(price.child, isA<Text>());
          final label = price.child! as Text;
          expect(label.data, '\$12');
          expect(label.style?.fontFamily, 'Azeret Mono');
          expect(label.style?.fontSize, 13);
          expect(label.style?.color, palette.onAccent);
          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}
