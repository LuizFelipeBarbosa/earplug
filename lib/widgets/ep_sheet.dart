import 'package:flutter/material.dart';

/// The one way EarPlug presents a bottom sheet: transparent background so the
/// sheet draws its own shell, a heavy scrim, and a phone-width cap on tablets.
Future<void> showEpSheet(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .6),
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: builder,
  );
}
