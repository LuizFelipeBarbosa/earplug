import 'dart:ui' show PointerDeviceKind;

import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

Future<void> _pump(WidgetTester tester, Widget child, {double scale = 1}) =>
    pumpEp(
      tester,
      child,
      media: MediaQueryData(textScaler: TextScaler.linear(scale)),
      alignment: Alignment.topLeft,
    );

Widget _item(int index) =>
    Container(key: ValueKey('carousel-item-$index'), color: Colors.red);

EpCarousel _carousel({
  bool wrapWhenScaled = false,
  int itemCount = 4,
  double itemExtent = 80,
  String? semanticsLabel,
}) => EpCarousel(
  itemCount: itemCount,
  itemExtent: itemExtent,
  height: 48,
  wrapWhenScaled: wrapWhenScaled,
  semanticsLabel: semanticsLabel,
  itemBuilder: (context, index) => _item(index),
);

void main() {
  testWidgets(
    'lays children out horizontally with gutter padding and item extent',
    (tester) async {
      await _pump(
        tester,
        SizedBox(
          key: const Key('carousel-host'),
          width: 320,
          child: _carousel(),
        ),
      );

      final hostLeft = tester
          .getTopLeft(find.byKey(const Key('carousel-host')))
          .dx;
      final item = find.byKey(const ValueKey('carousel-item-0'));
      expect(tester.getTopLeft(item).dx - hostLeft, EpLayout.gutter);
      expect(tester.getSize(item).width, 80);
    },
  );

  testWidgets('scrolls with a mouse drag', (tester) async {
    await _pump(
      tester,
      SizedBox(
        key: const Key('carousel-host'),
        width: 300,
        child: _carousel(itemCount: 10, itemExtent: 240),
      ),
    );

    final item = find.byKey(const ValueKey('carousel-item-0'));
    final before = tester.getTopLeft(item).dx;
    await tester.drag(
      find.byType(ListView),
      const Offset(-200, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final after = tester.getTopLeft(item).dx;
    expect(after, lessThan(before));
  });

  testWidgets('wraps into rows at text scale 1.5 when wrapWhenScaled is true', (
    tester,
  ) async {
    await _pump(tester, _carousel(wrapWhenScaled: true), scale: 1.5);

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets(
    'keeps scrolling at text scale 1.5 when wrapWhenScaled is false',
    (tester) async {
      await _pump(tester, _carousel(), scale: 1.5);

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(Wrap), findsNothing);
    },
  );

  testWidgets('exposes the semantics container label', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _carousel(semanticsLabel: 'Featured shows'));

    expect(find.bySemanticsLabel('Featured shows'), findsOneWidget);
    semantics.dispose();
  });
}
