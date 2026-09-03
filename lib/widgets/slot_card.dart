import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Card outline states shared by the editing slots of a form.
enum SlotState { done, needed }

/// The tappable card around a slot: a plain card once done, a dashed volt
/// outline while the slot still needs input.
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
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
    if (state != SlotState.needed) {
      return EpCard(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        onTap: onTap,
        child: content,
      );
    }

    final radius = BorderRadius.circular(12);
    return Semantics(
      container: true,
      button: onTap != null,
      child: Material(
        color: context.epColors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: DashedBox(
            color: context.epColors.volt,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// The small tracked-out label at the top of a slot.
class SlotTag extends StatelessWidget {
  final String text;
  final Color color;

  const SlotTag(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: epText(
        size: 11,
        weight: FontWeight.w900,
        letterSpacing: 1.2,
        color: color,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SlotTag(
                  tag,
                  state == SlotState.needed
                      ? context.epColors.warning
                      : context.epColors.contentSecondary,
                ),
              ),
              if (state == SlotState.done)
                Icon(Icons.check, size: 17, color: context.epColors.success),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: epText(
              size: 13,
              weight: FontWeight.w800,
              color: state == SlotState.needed
                  ? context.epColors.warning
                  : context.epColors.contentPrimary,
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: epText(size: 11, color: context.epColors.contentDisabled),
            ),
          ],
        ],
      ),
    );
  }
}
