import 'package:flutter/material.dart';

enum _EpLogoVariant { full, compact }

/// The EarPlug wordmark (ear mark followed by the name) and the bare ear mark
/// for compact headers. The wordmark ships in both inks; the mark is inverted
/// for light surfaces.
class EpLogo extends StatelessWidget {
  const EpLogo.full({
    super.key,
    this.width = 240,
    this.height,
    this.semanticLabel = 'EarPlug',
  }) : _variant = _EpLogoVariant.full;

  const EpLogo.compact({
    super.key,
    this.width,
    this.height = 28,
    this.semanticLabel = 'EarPlug',
  }) : _variant = _EpLogoVariant.compact;

  final _EpLogoVariant _variant;
  final double? width;
  final double? height;
  final String semanticLabel;

  String _assetName(Brightness brightness) => switch (_variant) {
    _EpLogoVariant.full =>
      brightness == Brightness.dark
          ? 'assets/images/earplug_wordmark_white.png'
          : 'assets/images/earplug_wordmark_black.png',
    _EpLogoVariant.compact => 'assets/images/earplug_mark.png',
  };

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final image = Image.asset(
      _assetName(brightness),
      width: width,
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final invertForLight =
        _variant == _EpLogoVariant.compact && brightness == Brightness.light;
    final visibleImage = invertForLight
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
