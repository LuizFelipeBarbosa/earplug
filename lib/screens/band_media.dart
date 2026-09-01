import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../models.dart';
import '../services/media_upload_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/video_thumbnail.dart';

const _adminGateMessage = 'Only band admins can post media.';

/// Retry/discard sit inline in a tight failed-upload row, so they get less
/// breathing room than a TextAction under a form step.
const _uploadActionPadding = EdgeInsets.symmetric(vertical: 3);

class BandMediaScreen extends StatelessWidget {
  final String bandId;

  const BandMediaScreen({super.key, required this.bandId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final media = context.watch<BandMediaController>();
    final items = media.mediaFor(bandId);
    final uploads = media.uploadsFor(bandId);
    final photos = media.photosFor(bandId);
    final loadError = media.loadErrorFor(bandId);
    final isAdmin = app.isAdminOf(bandId);
    final gatedVideoUpload = isAdmin
        ? () => media.pickAndUploadVideo(bandId)
        : () => app.say(_adminGateMessage);

    return ColoredBox(
      color: Ep.background,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ep.border)),
            ),
            child: Row(
              children: [
                CircleIconButton(onTap: app.back),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'BAND MEDIA',
                    style: epText(
                      size: 12,
                      weight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: Ep.contentSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Ep.surface,
                    border: Border.all(color: Ep.border),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${items.length} ITEMS',
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                40 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _UploadSlot(
                        icon: Icons.videocam_outlined,
                        label: '+ MUSIC CLIP',
                        sub: 'MP4 · 25 MB MAX',
                        enabled: isAdmin,
                        onTap: gatedVideoUpload,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _UploadSlot(
                        icon: Icons.add_photo_alternate_outlined,
                        label: '+ PHOTOS',
                        sub: 'UP TO 10 · 8 MB EACH',
                        enabled: isAdmin,
                        onTap: isAdmin
                            ? () => media.pickAndUploadPhotos(bandId)
                            : () => app.say(_adminGateMessage),
                      ),
                    ),
                  ],
                ),
                if (uploads.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const SectionLabel('UPLOADING'),
                  const SizedBox(height: 8),
                  for (final upload in uploads) ...[
                    _UploadTile(upload: upload, media: media),
                    const SizedBox(height: 8),
                  ],
                ],
                const SizedBox(height: 18),
                const SectionLabel('PROFILE BANNER'),
                const SizedBox(height: 8),
                _HeroStrip(
                  photos: photos,
                  isAdmin: isAdmin,
                  onTap: isAdmin
                      ? () => _showHeroSheet(context, media, bandId)
                      : () => app.say(_adminGateMessage),
                ),
                const SizedBox(height: 18),
                const SectionLabel('ORDER · PINNED MUSIC CLIP PLAYS FIRST'),
                const SizedBox(height: 8),
                for (final item in items) ...[
                  _MediaRow(
                    item: item,
                    isAdmin: isAdmin,
                    media: media,
                    bandId: bandId,
                  ),
                  const SizedBox(height: 8),
                ],
                if (items.isEmpty && uploads.isEmpty) ...[
                  const SizedBox(height: 4),
                  DashedBox(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 34,
                    ),
                    child: Column(
                      children: [
                        const PlayTriangle(size: 18, color: Ep.contentDisabled),
                        const SizedBox(height: 12),
                        Text('NOTHING POSTED YET', style: epDisplay(size: 15)),
                        const SizedBox(height: 7),
                        Text(
                          'Start with one music clip and a couple of photos. '
                          'Fans hear the pinned clip first.',
                          textAlign: TextAlign.center,
                          style: epText(
                            size: 11.5,
                            color: Ep.contentDisabled,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        EpButton(
                          '+ POST YOUR FIRST MUSIC CLIP',
                          onTap: gatedVideoUpload,
                        ),
                      ],
                    ),
                  ),
                ],
                if (loadError != null) ...[
                  const SizedBox(height: 16),
                  EpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loadError,
                          style: epText(
                            size: 11.5,
                            color: Ep.contentSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        EpButton('RETRY', onTap: () => media.refresh(bandId)),
                      ],
                    ),
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

class _UploadSlot extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool enabled;
  final VoidCallback onTap;

  const _UploadSlot({
    required this.icon,
    required this.label,
    required this.sub,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EpCard(
      variant: enabled ? EpCardVariant.standard : EpCardVariant.disabled,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(icon, size: 23, color: enabled ? Ep.accent : Ep.contentDisabled),
          const SizedBox(height: 7),
          Text(
            label,
            style: epText(size: 12, weight: FontWeight.w900, letterSpacing: .7),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: epText(
              size: 9,
              weight: FontWeight.w800,
              letterSpacing: .5,
              color: enabled ? Ep.contentSecondary : Ep.contentDisabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final MediaUpload upload;
  final BandMediaController media;

  const _UploadTile({required this.upload, required this.media});

  @override
  Widget build(BuildContext context) {
    final failed = upload.phase == MediaUploadPhase.failed;
    return EpCard(
      borderColor: failed ? Ep.destructive : Ep.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: upload.preview != null
                      ? Image.memory(upload.preview!, fit: BoxFit.cover)
                      : ColoredBox(
                          color: Ep.surfaceRaised,
                          child: Center(
                            child: const PlayTriangle(
                              size: 11,
                              color: Ep.contentPrimary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      upload.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: epText(size: 12.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    if (failed)
                      Text(
                        upload.error ?? 'Upload failed.',
                        style: epText(
                          size: 10.5,
                          color: Ep.destructive,
                          height: 1.35,
                        ),
                      )
                    else
                      Text(
                        _phaseLabel(upload.phase),
                        style: epText(
                          size: 10,
                          weight: FontWeight.w900,
                          letterSpacing: .8,
                          color: Ep.accent,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: 11),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextAction(
                  'RETRY',
                  color: Ep.accent,
                  size: 10.5,
                  letterSpacing: .7,
                  padding: _uploadActionPadding,
                  onTap: () => media.retryUpload(upload.id),
                ),
                const SizedBox(width: 18),
                TextAction(
                  'DISCARD',
                  color: Ep.contentSecondary,
                  size: 10.5,
                  letterSpacing: .7,
                  padding: _uploadActionPadding,
                  onTap: () => media.dismissUpload(upload.id),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 11),
            LinearProgressIndicator(
              minHeight: 2,
              color: Ep.brand,
              backgroundColor: Ep.surfaceDisabled,
            ),
          ],
        ],
      ),
    );
  }

  String _phaseLabel(MediaUploadPhase phase) => switch (phase) {
    MediaUploadPhase.preparing => 'PREPARING…',
    MediaUploadPhase.uploading => 'UPLOADING…',
    MediaUploadPhase.saving => 'SAVING…',
    MediaUploadPhase.done => 'DONE',
    MediaUploadPhase.failed => 'UPLOAD FAILED',
  };
}

class _HeroStrip extends StatelessWidget {
  final List<BandMedia> photos;
  final bool isAdmin;
  final VoidCallback onTap;

  const _HeroStrip({
    required this.photos,
    required this.isAdmin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    BandMedia? hero;
    for (final photo in photos) {
      if (photo.isHero) {
        hero = photo;
        break;
      }
    }

    final child = hero == null
        ? DashedBox(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 25,
                    color: Ep.contentDisabled,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SET A PROFILE BANNER',
                    style: epText(
                      size: 12,
                      weight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Used behind your public header and on band tiles.',
                    style: epText(size: 10.5, color: Ep.contentDisabled),
                  ),
                ],
              ),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _PhotoSurface(item: hero, placeholderLabel: 'PHOTO SET'),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Ep.background.withValues(alpha: .82),
                      border: Border.all(color: Ep.border),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'CHANGE',
                      style: epText(
                        size: 9.5,
                        weight: FontWeight.w900,
                        letterSpacing: .7,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );

    return EpCard(
      key: const ValueKey('profile-banner-picker'),
      variant: isAdmin ? EpCardVariant.standard : EpCardVariant.disabled,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: AspectRatio(aspectRatio: 16 / 9, child: child),
    );
  }
}

class _MediaRow extends StatelessWidget {
  final BandMedia item;
  final bool isAdmin;
  final BandMediaController media;
  final String bandId;

  const _MediaRow({
    required this.item,
    required this.isAdmin,
    required this.media,
    required this.bandId,
  });

  @override
  Widget build(BuildContext context) {
    return EpCard(
      variant: item.pinned ? EpCardVariant.selected : EpCardVariant.standard,
      padding: const EdgeInsets.all(9),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 52,
                  height: 48,
                  child: item.isVideo
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            BandVideoThumbnail(
                              media: item,
                              fallback: const ColoredBox(
                                color: Ep.surfaceRaised,
                              ),
                            ),
                            Center(
                              child: PlayTriangle(
                                size: 9,
                                color: Ep.contentPrimary,
                              ),
                            ),
                            if (item.lenLabel.isNotEmpty)
                              Positioned(
                                right: 3,
                                bottom: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .68),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    item.lenLabel,
                                    style: epText(
                                      size: 7.5,
                                      weight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : _PhotoSurface(item: item),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.epBody.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.isVideo ? 'MUSIC CLIP · ${item.lenLabel}' : 'PHOTO',
                      style: Theme.of(context).textTheme.epCaption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isAdmin) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                if (item.isVideo)
                  _PinButton(
                    pinned: item.pinned,
                    onTap: () => media.pin(bandId, item.id),
                  ),
                _GlyphButton.arrow(
                  glyph: '↑',
                  tooltip: 'Move up',
                  onTap: () => media.move(bandId, item.id, 'up'),
                ),
                _GlyphButton.arrow(
                  glyph: '↓',
                  tooltip: 'Move down',
                  onTap: () => media.move(bandId, item.id, 'down'),
                ),
                _GlyphButton.delete(
                  key: ValueKey('delete-${item.id}'),
                  onTap: () => _showDeleteSheet(context, media, bandId, item),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PinButton extends StatelessWidget {
  final bool pinned;
  final VoidCallback onTap;

  const _PinButton({required this.pinned, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return pinned
        ? Semantics(
            button: true,
            enabled: false,
            hint: 'This is the featured clip. Pin another clip to replace it.',
            child: const FilledButton(onPressed: null, child: Text('PINNED ★')),
          )
        : OutlinedButton(onPressed: onTap, child: const Text('PIN'));
  }
}

/// Square icon-ish control in the admin row of a media tile: reorder arrows
/// and the delete cross.
class _GlyphButton extends StatelessWidget {
  final String glyph;
  final String tooltip;
  final VoidCallback onTap;

  const _GlyphButton.arrow({
    required this.glyph,
    required this.tooltip,
    required this.onTap,
  });

  const _GlyphButton.delete({super.key, required this.onTap})
    : glyph = '\u2715',
      tooltip = 'Delete';

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Text(
        glyph,
        style: Theme.of(context).textTheme.epLabel.copyWith(
          color: tooltip == 'Delete' ? Ep.destructive : Ep.contentSecondary,
        ),
      ),
    );
  }
}

class _PhotoSurface extends StatelessWidget {
  final BandMedia item;
  final String? placeholderLabel;

  const _PhotoSurface({required this.item, this.placeholderLabel});

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Ep.surface,
      child: placeholderLabel == null
          ? const SizedBox.expand()
          : Center(
              child: Text(
                placeholderLabel!,
                textAlign: TextAlign.center,
                style: epText(
                  size: 9.5,
                  weight: FontWeight.w900,
                  letterSpacing: .7,
                  color: Ep.contentDisabled,
                ),
              ),
            ),
    );
    final url = item.url;
    if (url == null) return placeholder;

    return EpNetworkImage(url: url, fit: BoxFit.cover, fallback: placeholder);
  }
}

class _MediaSheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _MediaSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      decoration: const BoxDecoration(
        color: Ep.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(title.toUpperCase(), style: epDisplay(size: 15)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            child: child,
          ),
        ],
      ),
    );
  }
}

void _showHeroSheet(
  BuildContext context,
  BandMediaController media,
  String bandId,
) {
  showEpSheet(
    context,
    (sheetContext) => _MediaSheet(
      title: 'Choose profile banner',
      child: SizedBox(
        height: math.min(MediaQuery.sizeOf(sheetContext).height * .58, 460),
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                itemCount: media.photosFor(bandId).length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final photo = media.photosFor(bandId)[index];
                  return Material(
                    color: Ep.surface,
                    borderRadius: BorderRadius.circular(9),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        await media.setHero(bandId, photo.id);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                      child: _PhotoSurface(
                        item: photo,
                        placeholderLabel: photo.title,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            EpButton(
              'USE INITIALS INSTEAD',
              kind: EpButtonKind.ghost,
              onTap: () async {
                await media.clearHero(bandId);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void _showDeleteSheet(
  BuildContext context,
  BandMediaController media,
  String bandId,
  BandMedia item,
) {
  showEpSheet(
    context,
    (sheetContext) => _MediaSheet(
      title: 'Delete media?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: epText(size: 12, color: Ep.contentSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Ep.destructive),
            onPressed: () async {
              await media.remove(bandId, item.id);
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
            },
            child: const Text('DELETE'),
          ),
          const SizedBox(height: 9),
          EpButton(
            'KEEP',
            kind: EpButtonKind.ghost,
            onTap: () => Navigator.pop(sheetContext),
          ),
        ],
      ),
    ),
  );
}
