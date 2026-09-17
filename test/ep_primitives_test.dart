import 'dart:ui' show Tristate;

import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildEpTheme(brightness),
    themeAnimationDuration: Duration.zero,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  ),
);

RenderParagraph _paragraph(WidgetTester tester, Finder text) => tester
    .renderObject(find.descendant(of: text, matching: find.byType(RichText)));

Material _pillMaterial(WidgetTester tester) => tester.widget<Material>(
  find.descendant(of: find.byType(EpPill), matching: find.byType(Material)),
);

void main() {
  test('genre tints are stable, case-insensitive palette colours', () {
    expect(genreTint('punk'), genreTint('PUNK'));
    const genres = ['punk', 'jazz', 'ambient', 'soul', 'techno'];
    for (final genre in genres) {
      expect(genreTint(genre), genreTint(genre));
      expect(Ep.genreTints, contains(genreTint(genre)));
    }
    expect(genres.map(genreTint).toSet().length, greaterThan(1));
  });

  testWidgets('section action aligns right and keeps a 44px tap target', (
    tester,
  ) async {
    var tapped = false;
    await _pump(
      tester,
      SizedBox(
        width: 360,
        child: EpSectionHeader(
          label: 'This week',
          action: 'See all',
          onAction: () => tapped = true,
        ),
      ),
    );

    final header = find.byType(EpSectionHeader);
    final action = find.text('SEE ALL');
    final padding = tester.widget<EpSectionHeader>(header).padding;
    expect(
      tester.getRect(action).right,
      closeTo(tester.getRect(header).right - padding.right, 0.5),
    );
    final buttonSize = tester.getSize(find.byType(TextButton));
    expect(buttonSize.width, greaterThanOrEqualTo(44));
    expect(buttonSize.height, greaterThanOrEqualTo(44));

    await tester.tap(action);
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uppercase and original-case semantics', (tester) async {
    const label = 'Riptide Release Show';
    for (final widget in <Widget>[
      const EpDisplay(label),
      const EpEyebrow(label),
      const EpEyebrow.accent(label),
      const EpMonoText(label),
      const EpPill(label: label),
      const EpBadge(label: label),
    ]) {
      await _pump(tester, widget);
      expect(find.text('RIPTIDE RELEASE SHOW'), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    for (final widget in <Widget>[
      const EpDisplay('EarPlug', keepCase: true),
      const EpEyebrow('EarPlug', keepCase: true),
      const EpMonoText('EarPlug', keepCase: true),
      const EpPill(label: 'EarPlug', keepCase: true),
    ]) {
      await _pump(tester, widget);
      expect(find.text('EarPlug'), findsOneWidget);
    }
  });

  testWidgets('pill palettes and disabled semantics', (tester) async {
    for (final brightness in Brightness.values) {
      final palette = buildEpTheme(brightness).extension<EpPalette>()!;
      for (final variant in EpPillVariant.values) {
        for (final enabled in [true, false]) {
          await _pump(
            tester,
            EpPill(
              label: 'Join show',
              variant: variant,
              onPressed: enabled ? () {} : null,
            ),
            brightness: brightness,
          );
          final material = _pillMaterial(tester);
          final expected = !enabled
              ? Colors.transparent
              : switch (variant) {
                  EpPillVariant.primary => palette.accent,
                  EpPillVariant.ink => palette.ink,
                  _ => Colors.transparent,
                };
          expect(material.color, expected);
          final flags = tester
              .getSemantics(find.byType(EpPill))
              .flagsCollection;
          expect(flags.isButton, isTrue);
          expect(flags.isEnabled, enabled ? Tristate.isTrue : Tristate.isFalse);
          if (!enabled) {
            expect(
              (material.shape! as StadiumBorder).side.color,
              palette.outline,
            );
            expect(
              tester.widget<Text>(find.text('JOIN SHOW')).style!.color,
              palette.contentDisabled,
            );
          }
        }
      }
      await _pump(
        tester,
        EpPill(label: 'Selected', selected: true, onPressed: () {}),
        brightness: brightness,
      );
      expect(_pillMaterial(tester).color, palette.ink);
    }
  });

  testWidgets('accent outline pill keeps the accent outline when selected', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final palette = buildEpTheme(brightness).extension<EpPalette>()!;
      for (final selected in [false, true]) {
        await _pump(
          tester,
          EpPill(
            label: 'Needs setup',
            icon: Icons.bolt,
            variant: EpPillVariant.accentOutline,
            selected: selected,
            onPressed: () {},
          ),
          brightness: brightness,
        );
        final material = _pillMaterial(tester);
        expect(
          material.color,
          selected ? palette.accent.withValues(alpha: .18) : Colors.transparent,
        );
        final side = (material.shape! as StadiumBorder).side;
        expect(side.color, palette.accent);
        expect(side.width, 1);
        expect(
          tester.widget<Text>(find.text('NEEDS SETUP')).style!.color,
          palette.accent,
        );
        expect(tester.widget<Icon>(find.byType(Icon)).color, palette.accent);
      }
      await _pump(
        tester,
        const EpPill(
          label: 'Needs setup',
          variant: EpPillVariant.accentOutline,
        ),
        brightness: brightness,
      );
      final disabled = _pillMaterial(tester);
      expect(disabled.color, Colors.transparent);
      expect((disabled.shape! as StadiumBorder).side.color, palette.outline);
      expect(
        tester.widget<Text>(find.text('NEEDS SETUP')).style!.color,
        palette.contentDisabled,
      );
    }
  });

  testWidgets('status pill tones colour the label only', (tester) async {
    for (final brightness in Brightness.values) {
      final palette = buildEpTheme(brightness).extension<EpPalette>()!;
      for (final tone in EpStatusPillTone.values) {
        await _pump(
          tester,
          StatusPill(label: 'Attention', tone: tone),
          brightness: brightness,
        );
        final expected = switch (tone) {
          EpStatusPillTone.success => palette.success,
          EpStatusPillTone.selected => palette.accent,
          EpStatusPillTone.warning => palette.ink,
          EpStatusPillTone.attention => palette.attention,
          EpStatusPillTone.neutral => palette.muted,
        };
        expect(
          tester.widget<Text>(find.text('ATTENTION')).style!.color,
          expected,
        );
        final decoration =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(StatusPill),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(decoration.border!.top.color, palette.line);
      }
    }
  });

  testWidgets('tab callbacks and selected semantics', (tester) async {
    var selected = 0;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => EpSegmentTabs(
          labels: const ['Upcoming', 'Past'],
          selected: selected,
          onSelect: (index) => setState(() => selected = index),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text('UPCOMING')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    await tester.tap(find.text('PAST'));
    await tester.pump();
    expect(selected, 1);
    final flags = tester.getSemantics(find.text('PAST')).flagsCollection;
    expect(flags.isSelected, Tristate.isTrue);
    expect(flags.isButton, isTrue);
    expect(flags.isInMutuallyExclusiveGroup, isTrue);
  });

  testWidgets('fixed tabs scale a long label down instead of wrapping', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 220,
        child: EpSegmentTabs(
          labels: const ['Going', 'Applications and invitations'],
          selected: 0,
          onSelect: (_) {},
        ),
      ),
    );

    final short = find.text('GOING');
    final long = find.text('APPLICATIONS AND INVITATIONS');
    for (final label in [short, long]) {
      expect(tester.widget<Text>(label).maxLines, 1);
      final paragraph = _paragraph(tester, label);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.textSize.height, paragraph.size.height);
      expect(
        find.ancestor(of: label, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    }
    final natural = _paragraph(tester, long).size;
    final rendered = tester.getRect(long);
    expect(rendered.height, lessThan(natural.height));
    expect(rendered.width, lessThan(natural.width));
    expect(
      rendered.width / natural.width,
      closeTo(rendered.height / natural.height, 1e-9),
    );
    expect(rendered.right, lessThanOrEqualTo(220));
    expect(tester.getRect(short).right, lessThanOrEqualTo(rendered.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrollable tabs keep labels on one line at natural size', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 220,
        child: EpSegmentTabs(
          labels: const ['Going', 'Applications and invitations'],
          selected: 0,
          onSelect: (_) {},
          scrollable: true,
        ),
      ),
    );

    final long = find.text('APPLICATIONS AND INVITATIONS');
    expect(tester.widget<Text>(long).maxLines, 1);
    final paragraph = _paragraph(tester, long);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getRect(long).size, paragraph.size);
    expect(find.byType(FittedBox), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('segmented control callbacks and labels', (tester) async {
    var selected = 0;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => EpSegmentedControl(
          segments: const [
            EpSegment(
              key: Key('seg-a'),
              icon: Icons.map,
              label: 'Map',
              semanticLabel: 'Map view',
            ),
            EpSegment(
              key: Key('seg-b'),
              icon: Icons.list,
              label: 'List',
              semanticLabel: 'List view',
            ),
          ],
          selected: selected,
          onSelect: (index) => setState(() => selected = index),
        ),
      ),
    );
    expect(find.text('MAP'), findsOneWidget);
    expect(find.text('LIST'), findsOneWidget);
    await tester.tap(find.byKey(const Key('seg-b')));
    await tester.pump();
    expect(selected, 1);
    expect(
      tester
          .getSemantics(find.byKey(const Key('seg-b')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('icon pill badge is optional', (tester) async {
    await _pump(
      tester,
      const EpIconPill(
        icon: Icons.add,
        semanticLabel: 'Add',
        badge: '3',
        badgeKey: Key('badge'),
      ),
    );
    expect(find.byKey(const Key('badge')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await _pump(
      tester,
      const EpIconPill(icon: Icons.add, semanticLabel: 'Add'),
    );
    expect(find.byKey(const Key('badge')), findsNothing);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('pill leading widget replaces icon slot', (tester) async {
    await _pump(
      tester,
      const EpPill(
        leading: SizedBox(key: Key('lead'), width: 14, height: 14),
        label: 'Near me',
      ),
    );
    expect(find.byKey(const Key('lead')), findsOneWidget);
    expect(find.text('NEAR ME'), findsOneWidget);
  });

  testWidgets('readiness colors and semantics', (tester) async {
    await _pump(tester, const EpReadinessBar(done: 2, total: 4));
    final palette = tester.element(find.byType(EpReadinessBar)).epColors;
    expect(find.bySemanticsLabel('2 of 4 complete'), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      final segment = find.byKey(ValueKey('readiness-segment-$index'));
      expect(
        tester.widget<Container>(segment).color,
        index < 2 ? palette.accent : palette.panel,
      );
      expect(tester.getSize(segment).height, 3);
    }
  });

  testWidgets('gig and checklist actions stay interactive', (tester) async {
    var gigTapped = false;
    var actionTapped = false;
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EpGigRow(
            date: DateTime(2026, 9, 11),
            title: 'Riptide Release Show',
            onTap: () => gigTapped = true,
          ),
          EpChecklistRow(
            done: false,
            label: 'Add a photo',
            actionLabel: 'Upload',
            onAction: () => actionTapped = true,
          ),
        ],
      ),
    );
    await tester.tap(find.text('RIPTIDE RELEASE SHOW'));
    await tester.tap(find.text('UPLOAD'));
    expect(gigTapped, isTrue);
    expect(actionTapped, isTrue);
  });

  testWidgets('entity row without leading starts title at row edge', (
    tester,
  ) async {
    await _pump(tester, const EpEntityRow(leading: null, title: 'Band'));

    expect(tester.getTopLeft(find.text('BAND')).dx, 0);
  });

  testWidgets('plain field forwards input', (tester) async {
    String? changed;
    await _pump(
      tester,
      EpUnderlineField(onChanged: (value) => changed = value),
    );
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'fan@example.com');
    expect(changed, 'fan@example.com');
  });

  testWidgets('remaining primitives render in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      for (final widget in <Widget>[
        EpIconPill(icon: Icons.add, semanticLabel: 'Add', onPressed: () {}),
        const EpHairline(indent: 4, endIndent: 4),
        const EpPanel(height: 80, striped: true, child: Text('Panel')),
        const EpPoster(title: 'Music', eyebrow: 'Live', footer: 'Doors 8'),
        const EpBottomCta(child: EpPill(label: 'Join', expand: true)),
        const EpEntityRow(
          leading: EpAvatarTile(initials: 'RP'),
          title: 'Band',
        ),
        const EpBadge(label: 'Verified', variant: EpBadgeVariant.secondary),
        const EpFactGrid(
          cells: [
            EpFactCell(label: 'Venue', value: 'The hall', sub: 'Downtown'),
            EpFactCell(label: 'Doors', value: 'Eight tonight', display: false),
          ],
        ),
        const EpChecklistRow(done: true, label: 'Profile complete'),
        const EpMenuRow(icon: Icons.add, label: 'Menu', trailingText: 'Edit'),
        const EpSectionHeader(label: 'This week', action: 'See all'),
      ]) {
        await _pump(tester, widget, brightness: brightness);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('narrow layouts and enlarged text fit', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (width, scale) in [(360.0, 1.5), (320.0, 1.0)]) {
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EpStatGrid(
            stats: [
              EpStat('128', 'Shows played'),
              EpStat('36', 'New followers'),
              EpStat('12', 'Upcoming gigs'),
            ],
          ),
          EpGigRow(
            date: DateTime(2026, 9, 11),
            title: 'Riptide Release Show with the entire local music community',
            meta: 'Friday · doors at eight · downtown',
            sub: 'A night of independent music',
            onTap: () {},
          ),
        ],
      );
      await _pump(
        tester,
        SizedBox(width: width, child: content),
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('12')).dy,
        greaterThan(tester.getTopLeft(find.text('128')).dy),
      );
    }
  });

  testWidgets('badge tones colour the label only', (tester) async {
    for (final brightness in Brightness.values) {
      final palette = buildEpTheme(brightness).extension<EpPalette>()!;
      for (final tone in [null, ...EpBadgeTone.values]) {
        await _pump(
          tester,
          EpBadge(label: 'Attention', tone: tone),
          brightness: brightness,
        );
        final expected = switch (tone) {
          null => palette.ink,
          EpBadgeTone.success => palette.success,
          EpBadgeTone.selected => palette.accent,
          EpBadgeTone.warning => palette.ink,
          EpBadgeTone.attention => palette.attention,
          EpBadgeTone.neutral => palette.muted,
        };
        expect(
          tester.widget<Text>(find.text('ATTENTION')).style!.color,
          expected,
        );
        expect(find.bySemanticsLabel('Attention'), findsOneWidget);
        final decoration =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(EpBadge),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(decoration.border!.top.color, palette.line);
      }
    }
  });

  testWidgets('dot draws a circle with optional fill and ring', (tester) async {
    await _pump(tester, const EpDot());
    final ring = tester.widget<Container>(find.byType(Container));
    final ringDecoration = ring.decoration! as BoxDecoration;
    expect(ringDecoration.shape, BoxShape.circle);
    expect(ringDecoration.color, isNull);
    expect(ringDecoration.border, isNull);
    expect(tester.getSize(find.byType(EpDot)), const Size(14, 14));

    await _pump(
      tester,
      const EpDot(
        size: 10,
        fill: Colors.red,
        border: Colors.blue,
        borderWidth: 2,
      ),
    );
    final filled = tester.widget<Container>(find.byType(Container));
    final filledDecoration = filled.decoration! as BoxDecoration;
    expect(filledDecoration.shape, BoxShape.circle);
    expect(filledDecoration.color, Colors.red);
    expect(filledDecoration.border!.top.color, Colors.blue);
    expect(filledDecoration.border!.top.width, 2);
    expect(tester.getSize(find.byType(EpDot)), const Size(10, 10));
  });

  testWidgets('section header count, trailing and form spacing', (
    tester,
  ) async {
    await _pump(
      tester,
      const SizedBox(
        width: 360,
        child: EpSectionHeader(
          label: 'Shows',
          count: 3,
          trailing: SizedBox(key: Key('trail'), width: 20, height: 20),
        ),
      ),
    );
    expect(find.text('SHOWS · 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Shows · 3'), findsOneWidget);
    expect(find.byKey(const Key('trail')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('trail'))).left,
      greaterThanOrEqualTo(tester.getRect(find.text('SHOWS · 3')).right + 8),
    );
    expect(find.byType(TextButton), findsNothing);
    expect(
      tester.widget<EpSectionHeader>(find.byType(EpSectionHeader)).padding,
      const EdgeInsets.only(top: 24, bottom: 4),
    );

    await _pump(
      tester,
      const SizedBox(
        width: 360,
        child: EpSectionHeader.form(label: 'Details', action: 'Edit'),
      ),
    );
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('EDIT'), findsOneWidget);
    expect(
      tester.widget<EpSectionHeader>(find.byType(EpSectionHeader)).padding,
      const EdgeInsets.only(top: EpLayout.formSectionGap, bottom: 4),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu row forwards its padding to the row base', (tester) async {
    await _pump(tester, const EpMenuRow(icon: Icons.add, label: 'Menu'));
    expect(
      tester.widget<EpRow>(find.byType(EpRow)).padding,
      const EdgeInsets.symmetric(vertical: 16),
    );

    await _pump(
      tester,
      const EpMenuRow(
        icon: Icons.add,
        label: 'Menu',
        padding: EdgeInsets.symmetric(vertical: 4),
      ),
    );
    expect(
      tester.widget<EpRow>(find.byType(EpRow)).padding,
      const EdgeInsets.symmetric(vertical: 4),
    );
    final flags = tester.getSemantics(find.byType(EpRow)).flagsCollection;
    expect(flags.isButton, isTrue);
  });

  testWidgets('stat grid dividers, no-wrap and fitted labels', (tester) async {
    const stats = [
      EpStat('128', 'Shows played'),
      EpStat('36', 'New followers'),
      EpStat('12', 'Upcoming gigs'),
    ];

    await _pump(
      tester,
      const SizedBox(width: 320, child: EpStatGrid(stats: stats, wrap: false)),
    );
    expect(find.byType(LayoutBuilder), findsNothing);
    expect(find.byType(IntrinsicHeight), findsNothing);
    expect(
      tester.getTopLeft(find.text('12')).dy,
      tester.getTopLeft(find.text('128')).dy,
    );
    expect(tester.takeException(), isNull);

    await _pump(
      tester,
      const SizedBox(
        width: 360,
        child: EpStatGrid(stats: stats, dividers: true, fitLabels: true),
      ),
    );
    final palette = tester.element(find.byType(EpStatGrid)).epColors;
    expect(find.byType(IntrinsicHeight), findsOneWidget);
    final dividers = find.descendant(
      of: find.byType(EpStatGrid),
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == palette.border,
      ),
    );
    expect(dividers, findsNWidgets(stats.length - 1));
    for (final divider in dividers.evaluate()) {
      final rect = tester.getRect(find.byWidget(divider.widget));
      expect(rect.width, 1);
      expect(rect.height, greaterThan(0));
    }
    for (final stat in stats) {
      expect(
        find.ancestor(
          of: find.text(stat.label.toUpperCase()),
          matching: find.byType(FittedBox),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('fact cell note replaces value and sub', (tester) async {
    await _pump(
      tester,
      const EpFactCell(
        label: 'Venue',
        value: 'The hall',
        sub: 'Downtown',
        note: 'To be confirmed',
      ),
    );
    expect(find.text('VENUE'), findsOneWidget);
    expect(find.text('TO BE CONFIRMED'), findsOneWidget);
    expect(find.text('THE HALL'), findsNothing);
    expect(find.text('Downtown'), findsNothing);
    final palette = tester.element(find.byType(EpFactCell)).epColors;
    expect(
      tester.widget<Text>(find.text('TO BE CONFIRMED')).style!.color,
      palette.muted,
    );
  });
}
