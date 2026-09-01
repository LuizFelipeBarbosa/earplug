import 'package:flutter/material.dart';

enum EpLogoVariant { full, compact }

/// The EarPlug lockup for entry surfaces and the ear mark for compact headers.
class EpLogo extends StatelessWidget {
  const EpLogo.full({
    super.key,
    this.width = 240,
    this.height,
    this.semanticLabel = 'EarPlug',
  }) : variant = EpLogoVariant.full;

  const EpLogo.compact({
    super.key,
    this.width,
    this.height = 48,
    this.semanticLabel = 'EarPlug',
  }) : variant = EpLogoVariant.compact;

  final EpLogoVariant variant;
  final double? width;
  final double? height;
  final String semanticLabel;

  String get _assetName => switch (variant) {
    EpLogoVariant.full => 'assets/images/listen_local_bw.png',
    EpLogoVariant.compact => 'assets/images/earplug_mark.png',
  };

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      _assetName,
      width: width,
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final visibleImage = Theme.of(context).brightness == Brightness.light
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              -1,
              0,
              0,
              0,
              255,
              0,
              -1,
              0,
              0,
              255,
              0,
              0,
              -1,
              0,
              255,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: image,
          )
        : image;

    return Semantics(image: true, label: semanticLabel, child: visibleImage);
  }
}
