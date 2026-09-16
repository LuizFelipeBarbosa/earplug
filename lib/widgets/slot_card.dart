import 'package:flutter/material.dart';

import '../theme.dart';
import 'ep_text.dart';

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

/// One editing slot: tag, headline value and a caption, coloured by [state].
class SlotCard extends StatelessWidget {
  final String tag;
  final String value;
  final String sub;
  final SlotState state;
  final VoidCallback onTap;

  const SlotCard({
    super.key,
    required this.tag,
    required this.value,
    required this.sub,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SlotShell(
      state: state,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state == SlotState.done)
            Icon(Icons.check, size: 16, color: context.epColors.accent)
          else
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.epColors.accent),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state == SlotState.needed)
                  EpEyebrow.accent('$tag · required')
                else
                  EpEyebrow(tag),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.epBody.copyWith(
                    color: state == SlotState.needed
                        ? context.epColors.muted
                        : context.epColors.ink,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
