import 'package:flutter/material.dart';

import '../money.dart';
import '../theme.dart';

class MoneyText extends StatelessWidget {
  const MoneyText(this.money, {super.key, this.style, this.signed = false});

  final Money money;
  final TextStyle? style;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final label = signed && money.amountMinor > 0
        ? '+${money.label}'
        : money.label;
    final baseStyle = style ?? const TextStyle();
    final effectiveStyle = baseStyle.copyWith(
      color:
          style?.color ?? (money.isNegative ? context.epColors.warning : null),
      fontFeatures: [
        ...?baseStyle.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
    );

    return Text(label, style: effectiveStyle);
  }
}
