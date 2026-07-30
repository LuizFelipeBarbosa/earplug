import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../models.dart';
import '../services/media_upload_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _adminGateMessage = 'Only band admins can post media.';

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
      color: Ep.bg,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Ep.whiteA(.09))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleIconButton(onTap: app.back),
                    const SizedBox(width: 10),
                    Text(
                      'BAND MEDIA',
                      style: epText(
                        size: 12,
                        weight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: Ep.inkA(.5),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Ep.whiteA(.16)),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${items.length} ITEMS',
                    style: epText(
                      size: 10,
                      weight: FontWeight.w800,
                      letterSpacing: .7,
                      color: Ep.inkA(.6),
                    ),
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
                        label: '+ CLIP',
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
                const SectionLabel('BAND PHOTO'),
                const SizedBox(height: 8),
                _HeroStrip(
                  photos: photos,
                  isAdmin: isAdmin,
                  onTap: isAdmin
                      ? () => _showHeroSheet(context, media, bandId)
                      : () => app.say(_adminGateMessage),
                ),
                const SizedBox(height: 18),
                const SectionLabel('ORDER · PINNED PLAYS FIRST'),
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
                        PlayTriangle(size: 18, color: Ep.inkA(.3)),
                        const SizedBox(height: 12),
                        Text('NOTHING POSTED YET', style: epDisplay(size: 15)),
                        const SizedBox(height: 7),
                        Text(
                          'One clip and a couple of photos is the whole job — '
                          'fans decide from the pinned clip.',
                          textAlign: TextAlign.center,
                          style: epText(
                            size: 11.5,
                            color: Ep.inkA(.45),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        EpButton(
                          '+ POST YOUR FIRST CLIP',
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
                            color: Ep.inkA(.7),
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
    final slot = DashedBox(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(icon, size: 23, color: Ep.link),
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
              color: Ep.inkA(.4),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: enabled ? slot : Opacity(opacity: .4, child: slot),
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
      borderColor: failed ? Ep.required : Ep.blue.withValues(alpha: .4),
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
                          color: const Color(0xFF1A1A20),
                          child: Center(
                            child: PlayTriangle(size: 11, color: Ep.whiteA(.8)),
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
                          color: Ep.required,
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
                          color: Ep.link,
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
                _TextAction(
                  label: 'RETRY',
                  color: Ep.link,
                  onTap: () => media.retryUpload(upload.id),
                ),
                const SizedBox(width: 18),
                _TextAction(
                  label: 'DISCARD',
                  color: Ep.inkA(.55),
                  onTap: () => media.dismissUpload(upload.id),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 11),
            LinearProgressIndicator(
              minHeight: 2,
              color: Ep.blue,
              backgroundColor: Ep.whiteA(.08),
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
                    color: Ep.inkA(.35),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SET A BAND PHOTO',
                    style: epText(
                      size: 12,
                      weight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Replaces the initials tile everywhere.',
                    style: epText(size: 10.5, color: Ep.inkA(.45)),
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
                      color: Ep.bg.withValues(alpha: .82),
                      border: Border.all(color: Ep.whiteA(.25)),
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

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: isAdmin ? 1 : .7,
        child: AspectRatio(aspectRatio: 16 / 9, child: child),
      ),
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
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Ep.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: item.pinned ? Ep.blue.withValues(alpha: .55) : Ep.whiteA(.1),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 52,
              height: 36,
              child: item.isVideo
                  ? ColoredBox(
                      color: const Color(0xFF1A1A20),
                      child: Stack(
                        children: [
                          Center(
                            child: PlayTriangle(size: 9, color: Ep.whiteA(.8)),
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
                      ),
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
                  style: epText(size: 12.5, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  item.isVideo ? 'CLIP · ${item.lenLabel}' : 'PHOTO',
                  style: epText(size: 10.5, color: Ep.inkA(.5)),
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(width: 7),
            if (item.isVideo) ...[
              _PinButton(
                pinned: item.pinned,
                onTap: () => media.pin(bandId, item.id),
              ),
              const SizedBox(width: 5),
            ],
            _ArrowButton(
              label: '↑',
              onTap: () => media.move(bandId, item.id, 'up'),
            ),
            const SizedBox(width: 5),
            _ArrowButton(
              label: '↓',
              onTap: () => media.move(bandId, item.id, 'down'),
            ),
            const SizedBox(width: 5),
            _DeleteButton(
              key: ValueKey('delete-${item.id}'),
              onTap: () => _showDeleteSheet(context, media, bandId, item),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: pinned ? Ep.blue : null,
          border: pinned ? null : Border.all(color: Ep.whiteA(.18)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          pinned ? 'PINNED ★' : 'PIN',
          style: epText(
            size: 8.5,
            weight: FontWeight.w900,
            letterSpacing: .4,
            color: pinned ? Colors.white : Ep.inkA(.7),
          ),
        ),
      ),
    );
  }
}

// Deliberately duplicated from the old edit-screen control for now.
class _ArrowButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ArrowButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Ep.whiteA(.18)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label, style: epText(size: 12, color: Ep.inkA(.7))),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DeleteButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Ep.whiteA(.18)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          '✕',
          style: epText(
            size: 10.5,
            weight: FontWeight.w900,
            color: Ep.inkA(.62),
          ),
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
      color: Ep.card,
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
                  color: Ep.inkA(.45),
                ),
              ),
            ),
    );
    final url = item.url;
    if (url == null) return placeholder;

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TextAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          label,
          style: epText(
            size: 10.5,
            weight: FontWeight.w900,
            letterSpacing: .7,
            color: color,
          ),
        ),
      ),
    );
  }
}

Future<void> _openMediaSheet(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .6),
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: builder,
  );
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
        color: Ep.card,
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
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, size: 18, color: Ep.inkA(.5)),
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
  _openMediaSheet(
    context,
    (sheetContext) => _MediaSheet(
      title: 'Choose band photo',
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
                  return GestureDetector(
                    onTap: () async {
                      await media.setHero(bandId, photo.id);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
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
            GestureDetector(
              onTap: () async {
                await media.clearHero(bandId);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: Ep.whiteA(.2)),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  'USE INITIALS INSTEAD',
                  style: epText(
                    size: 11,
                    weight: FontWeight.w900,
                    letterSpacing: .7,
                    color: Ep.inkA(.7),
                  ),
                ),
              ),
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
  _openMediaSheet(
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
            style: epText(size: 12, color: Ep.inkA(.58), height: 1.4),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              await media.remove(bandId, item.id);
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFFFF6B6B).withValues(alpha: .65),
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                'DELETE',
                style: epText(
                  size: 11.5,
                  weight: FontWeight.w900,
                  letterSpacing: .8,
                  color: const Color(0xFFFF7A7A),
                ),
              ),
            ),
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
