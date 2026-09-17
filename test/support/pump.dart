import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts [child] in a bare [Scaffold] body.
///
/// The [MediaQuery] wrapper is emitted only when [media] is passed, so sites
/// that never wrapped keep the window MediaQuery (and any view padding the
/// test installed on it). [alignment] wins over [center]; with neither the
/// child fills the body.
Widget epScreen(
  Widget child, {
  MediaQueryData? media,
  AlignmentGeometry? alignment,
  bool center = false,
}) {
  final inner = alignment != null
      ? Align(alignment: alignment, child: child)
      : center
      ? Center(child: child)
      : child;
  return Scaffold(
    body: media == null ? inner : MediaQuery(data: media, child: inner),
  );
}

/// A [MaterialApp] on the EarPlug theme with theme animations disabled,
/// hosting [child] via [epScreen].
///
/// With [mediaOutsideScaffold] the [media] wraps the whole screen (including
/// the scaffold) instead of only the body.
Widget epApp(
  Widget child, {
  Brightness brightness = Brightness.dark,
  MediaQueryData? media,
  bool mediaOutsideScaffold = false,
  AlignmentGeometry? alignment,
  bool center = false,
}) => MaterialApp(
  theme: buildEpTheme(brightness),
  themeAnimationDuration: Duration.zero,
  home: mediaOutsideScaffold && media != null
      ? MediaQuery(
          data: media,
          child: epScreen(child, alignment: alignment, center: center),
        )
      : epScreen(child, media: media, alignment: alignment, center: center),
);

/// Pumps [epApp] hosting [child]; see [epApp] for the parameters.
Future<void> pumpEp(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  MediaQueryData? media,
  bool mediaOutsideScaffold = false,
  AlignmentGeometry? alignment,
  bool center = false,
}) => tester.pumpWidget(
  epApp(
    child,
    brightness: brightness,
    media: media,
    mediaOutsideScaffold: mediaOutsideScaffold,
    alignment: alignment,
    center: center,
  ),
);
