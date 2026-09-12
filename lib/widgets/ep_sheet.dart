import 'package:flutter/material.dart';

import '../theme.dart';

/// The one way EarPlug presents a bottom sheet: transparent background so the
/// sheet draws its own shell, a heavy scrim, and a phone-width cap on tablets.
Future<void> showEpSheet(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: context.epColors.background.withValues(alpha: 0),
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .6),
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: EpLayout.isDesktop(context) ? 560 : 600,
    ),
    builder: builder,
  );
}
