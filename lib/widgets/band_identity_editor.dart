import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../genres.dart';
import '../theme.dart';
import 'common.dart';

/// The public band-profile header, with optional editing controls layered over
/// the exact same presentation for create/edit workflows.
class BandIdentityHeader extends StatelessWidget {
  const BandIdentityHeader({
    super.key,
    required this.name,
    required this.area,
    required this.initials,
    required this.color,
    this.avatarUrl,
    this.bannerUrl,
    this.avatarBytes,
    this.bannerBytes,
    this.onAvatarTap,
    this.onBannerTap,
    this.avatarBusy = false,
    this.bannerBusy = false,
  });

  final String name;
  final String area;
  final String initials;
  final Color color;
  final String? avatarUrl;
  final String? bannerUrl;
  final Uint8List? avatarBytes;
  final Uint8List? bannerBytes;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBannerTap;
  final bool avatarBusy;
  final bool bannerBusy;

  bool get _editable => onAvatarTap != null || onBannerTap != null;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final displayName = name.trim().isEmpty ? 'Your band name' : name.trim();
    final displayArea = area.trim().isEmpty
        ? 'Set your home base'
        : area.trim();
    final avatarLabel = avatarBytes != null || avatarUrl != null
        ? 'Change profile image'
        : 'Add profile image';
    final bannerLabel = bannerBytes != null || bannerUrl != null
        ? 'Change header image'
        : 'Add header image';

    return Semantics(
      container: true,
      label: _editable ? 'Band profile header preview' : null,
      child: Container(
        key: const ValueKey('band-identity-header'),
        height: 188 + (textScale - 1).clamp(0, 1) * 80,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.epColors.border),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ArtworkImage(
              bytes: bannerBytes,
              url: bannerUrl,
              fit: BoxFit.cover,
              fallback: ColoredBox(color: color),
            ),
            const DecoratedBox(
              key: ValueKey('band-profile-banner-scrim'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xA8000000), Color(0xBD000000)],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 24, 104, _editable ? 54 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'BAND · ${displayArea.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epChipLabel.copyWith(
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epDisplay.copyWith(
                      color: Colors.white,
                      fontSize: 29,
                      height: 1.02,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (onBannerTap != null)
              Positioned.fill(
                child: Semantics(
                  button: true,
                  enabled: !bannerBusy,
                  label: bannerLabel,
                  excludeSemantics: true,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('band-header-image-control'),
                      onTap: bannerBusy ? null : onBannerTap,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 22,
              right: 18,
              child: Semantics(
                button: onAvatarTap != null,
                enabled: onAvatarTap != null && !avatarBusy,
                label: onAvatarTap == null
                    ? '$displayName profile image'
                    : avatarLabel,
                image: onAvatarTap == null,
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('band-profile-image-control'),
                    onTap: avatarBusy ? null : onAvatarTap,
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            key: const ValueKey('band-profile-avatar-frame'),
                            width: 66,
                            height: 66,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .35),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .86),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _ArtworkImage(
                                    bytes: avatarBytes,
                                    url: avatarUrl,
                                    fit: BoxFit.cover,
                                    fallback: ColoredBox(
                                      color: color,
                                      child: Center(
                                        child: Text(
                                          initials,
                                          style: Theme.of(context)
                                              .textTheme
                                              .epDisplay
                                              .copyWith(
                                                color: Colors.white,
                                                fontSize: 18,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (onAvatarTap != null)
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Container(
                                        width: 26,
                                        height: 26,
                                        color: Colors.black87,
                                        child: avatarBusy
                                            ? const Padding(
                                                padding: EdgeInsets.all(6),
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : Icon(
                                                Icons.photo_camera_outlined,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (onAvatarTap != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              'PROFILE IMAGE',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.epChipLabel
                                  .copyWith(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onBannerTap != null)
              Positioned(
                left: 14,
                bottom: 12,
                child: IgnorePointer(
                  child: _EditLabel(
                    label: bannerBusy ? 'UPLOADING HEADER…' : 'HEADER IMAGE',
                    busy: bannerBusy,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BandIdentityTextField extends StatelessWidget {
  const BandIdentityTextField({
    super.key,
    this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.required = false,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final Key? fieldKey;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool required;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      style: Theme.of(context).textTheme.epDisplay.copyWith(
        fontSize: minLines > 1 ? 18 : 21,
        height: 1.25,
      ),
      decoration: epInputDecoration(context, hint).copyWith(
        labelText: required ? '$label · REQUIRED' : label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      ),
    );
  }
}

class BandGenreEditor extends StatelessWidget {
  const BandGenreEditor({
    super.key,
    required this.genres,
    required this.onToggle,
    required this.customController,
    required this.addingCustomGenre,
    required this.onShowCustomGenre,
    required this.onAddCustomGenre,
    this.enabled = true,
  });

  final List<String> genres;
  final ValueChanged<String> onToggle;
  final TextEditingController customController;
  final bool addingCustomGenre;
  final VoidCallback onShowCustomGenre;
  final VoidCallback onAddCustomGenre;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('band-genres-field'),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.epColors.surface,
        border: Border.all(color: context.epColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'GENRES · REQUIRED',
            style: Theme.of(context).textTheme.epChipLabel.copyWith(
              color: genres.isEmpty
                  ? context.epColors.warning
                  : context.epColors.contentSecondary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final genre in {...kGenres, ...genres})
                EpChip(
                  label: genre,
                  active: genres.contains(genre),
                  onTap: enabled ? () => onToggle(genre) : null,
                ),
              EpChip(
                key: const ValueKey('show-custom-genre'),
                label: '+ ADD',
                active: false,
                ghost: true,
                semanticLabel: 'Add custom genre',
                onTap: enabled ? onShowCustomGenre : null,
              ),
            ],
          ),
          if (addingCustomGenre) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('edit-custom-genre'),
                    controller: customController,
                    enabled: enabled,
                    autofocus: true,
                    onSubmitted: (_) => onAddCustomGenre(),
                    style: Theme.of(context).textTheme.epBody,
                    decoration: epInputDecoration(context, 'Another genre'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: enabled ? onAddCustomGenre : null,
                  child: Text('ADD'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 7),
          Text(
            '${genres.length} of 3 selected',
            style: Theme.of(context).textTheme.epCaption,
          ),
        ],
      ),
    );
  }
}

class _EditLabel extends StatelessWidget {
  const _EditLabel({required this.label, required this.busy});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .78),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            Icon(Icons.photo_camera_outlined, size: 17, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.epChipLabel.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ArtworkImage extends StatelessWidget {
  const _ArtworkImage({
    required this.bytes,
    required this.url,
    required this.fit,
    required this.fallback,
  });

  final Uint8List? bytes;
  final String? url;
  final BoxFit fit;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : null;
        final logicalHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : null;

        if (bytes case final imageBytes?) {
          final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
          return Image.memory(
            imageBytes,
            fit: fit,
            cacheWidth: logicalWidth == null
                ? null
                : (logicalWidth * devicePixelRatio).round(),
            cacheHeight: logicalHeight == null
                ? null
                : (logicalHeight * devicePixelRatio).round(),
            errorBuilder: (_, _, _) => fallback,
          );
        }
        return EpNetworkImage(
          url: url,
          fit: fit,
          fallback: fallback,
          cacheWidth: logicalWidth?.round(),
          cacheHeight: logicalHeight?.round(),
        );
      },
    );
  }
}
