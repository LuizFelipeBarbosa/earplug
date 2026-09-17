import 'package:flutter/material.dart';

import 'pump.dart';

/// Hosts [child] in a phone-sized scaffold at 1.5x text scale, the size most
/// accessibility layout regressions show up at first.
Widget scaledScreen(Widget child, {Size size = const Size(402, 900)}) =>
    epScreen(
      child,
      media: MediaQueryData(
        size: size,
        textScaler: const TextScaler.linear(1.5),
      ),
    );
