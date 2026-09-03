import 'package:flutter/material.dart';

/// Hosts [child] in a phone-sized scaffold at 1.5x text scale, the size most
/// accessibility layout regressions show up at first.
Widget scaledScreen(Widget child, {Size size = const Size(402, 900)}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: const TextScaler.linear(1.5)),
    child: Scaffold(body: child),
  );
}
