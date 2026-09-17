import 'package:flutter/material.dart';

import '../theme.dart';

/// Completion states shared by the editing slots of a form.
enum SlotState { done, needed }

/// Tappable hairline row chrome; the child owns any completion indicator.
class SlotShell extends StatelessWidget {
  final SlotState state;
  final Widget child;
  final VoidCallback? onTap;

  const SlotShell({
    super.key,
    required this.state,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: onTap != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.epColors.line)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
