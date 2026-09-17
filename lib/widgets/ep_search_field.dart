import 'package:flutter/material.dart';

import '../theme.dart';

/// The shared search field: a 44px-tall hairline box that thickens and
/// switches to the accent colour while its text field has focus, with a
/// leading search glyph and a trailing clear button that appears once the
/// controller holds text.
///
/// [radius] is 0 for the square grammar and [EpLayout.pillRadius] for the pill
/// variant; the box otherwise paints identically.
class EpSearchField extends StatelessWidget {
  const EpSearchField({
    super.key,
    required this.fieldKey,
    required this.clearKey,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    this.onSubmitted,
    this.radius = 0,
  });

  final Key fieldKey;
  final Key clearKey;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<String>? onSubmitted;
  final double radius;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    child: Builder(
      builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: radius == 0 ? null : BorderRadius.circular(radius),
            border: Border.all(
              color: focused ? context.epColors.accent : context.epColors.line,
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 16, color: context.epColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: TextInputAction.search,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(context).textTheme.epInput,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: Theme.of(
                      context,
                    ).textTheme.epInput.copyWith(color: context.epColors.muted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: clearKey,
                        tooltip: 'Clear search',
                        onPressed: onClear,
                        color: context.epColors.muted,
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
