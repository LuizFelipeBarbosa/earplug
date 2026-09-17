import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A gutter-aligned horizontal rail of fixed-width children.
class EpCarousel extends StatelessWidget {
  const EpCarousel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemExtent,
    required this.height,
    this.gap = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
    this.wrapWhenScaled = false,
    this.semanticsLabel,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemExtent;
  final double height;
  final double gap;
  final EdgeInsetsGeometry padding;
  final bool wrapWhenScaled;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final useWrap =
        wrapWhenScaled && MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final content = useWrap
        ? Padding(
            padding: padding,
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var index = 0; index < itemCount; index++)
                  SizedBox(
                    width: itemExtent,
                    child: itemBuilder(context, index),
                  ),
              ],
            ),
          )
        : SizedBox(
            height: height,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                },
                scrollbars: false,
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: padding,
                itemCount: itemCount,
                itemBuilder: (context, index) => SizedBox(
                  width: itemExtent,
                  child: itemBuilder(context, index),
                ),
                separatorBuilder: (context, index) => SizedBox(width: gap),
              ),
            ),
          );

    return semanticsLabel == null
        ? content
        : Semantics(container: true, label: semanticsLabel, child: content);
  }
}
