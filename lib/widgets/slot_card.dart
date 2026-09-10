import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import 'form_bits.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(tag, required: state == SlotState.needed),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
          child: Row(
            children: [
              Expanded(
                child: Text(value == 'REQUIRED' ? sub : sentenceCase(value)),
              ),
              const Icon(Icons.expand_more),
            ],
          ),
        ),
        if (sub.isNotEmpty && value != 'REQUIRED')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(sub, style: Theme.of(context).textTheme.epCaption),
          ),
      ],
    );
  }
}
