import 'dart:ui' show Tristate;

import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
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

Material _pillMaterial(WidgetTester tester) => tester.widget<Material>(
  find.descendant(of: find.byType(EpPill), matching: find.byType(Material)),
);

void main() {
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
}
