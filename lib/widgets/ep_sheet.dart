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

/// A two-button confirmation dialog. Resolves true only when the user taps
/// [confirmLabel]; KEEP and the barrier both resolve false.
Future<bool> epConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String keepLabel = 'KEEP',
  String confirmLabel = 'CONFIRM',
  Key? keepKey,
  Key? confirmKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          key: keepKey,
          onPressed: () => Navigator.pop(context, false),
          child: Text(keepLabel),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
