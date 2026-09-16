import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../models.dart';
import '../services/media_upload_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/sheets.dart';
import '../widgets/video_thumbnail.dart';

const _adminGateMessage = 'Only band admins can post media.';

enum _MediaFilter { all, videos, photos }

class BandMediaScreen extends StatefulWidget {
  const BandMediaScreen({super.key, required this.bandId});

  final String bandId;

  @override
  State<BandMediaScreen> createState() => _BandMediaScreenState();
}

class _BandMediaScreenState extends State<BandMediaScreen> {
  _MediaFilter _filter = _MediaFilter.all;
  List<BandMedia> _items = const [];

  @override
  void didUpdateWidget(covariant BandMediaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bandId != widget.bandId) {
      _filter = _MediaFilter.all;
      _items = const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final media = context.watch<BandMediaController>();
    final bandId = widget.bandId;
    final loadError = media.loadErrorFor(bandId);
    // Preserve the last view on failure: mediaFor retries an uncached load,
    // so calling it again here would bypass the explicit Retry action.
    if (loadError == null) _items = media.mediaFor(bandId);
    final loading = media.isLoading(bandId) && _items.isEmpty;
    final visible = _items
        .where(
          (item) => switch (_filter) {
            _MediaFilter.all => true,
            _MediaFilter.videos => item.isVideo,
            _MediaFilter.photos => !item.isVideo,
          },
        )
        .toList();
    final uploads = media.uploadsFor(bandId);
    final featuredId = _items.isEmpty ? null : media.pinnedVideoFor(bandId)?.id;
    final isAdmin = app.isAdminOf(bandId);
    void explainAdminGate() => app.say(_adminGateMessage);

    return ColoredBox(
      color: context.epColors.background,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          EpLayout.gutter,
          EpLayout.isDesktop(context) ? 0 : headerTopPad(context),
          EpLayout.gutter,
          tabBarClearance + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                EpIconPill(
                  key: const ValueKey('band-media-back'),
                  icon: Icons.arrow_back,
                  semanticLabel: 'Back',
                  onPressed: app.back,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'MEDIA',
                    style: Theme.of(context).textTheme.epPageHeading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            EpMonoText(
              'Tap a tile to manage. Hold and drag to reorder.',
              key: const ValueKey('band-media-hint'),
              color: context.epColors.contentSecondary,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in _MediaFilter.values)
                  EpPill(
                    key: ValueKey('band-media-filter-${filter.name}'),
                    label: filter.name.toUpperCase(),
                    variant: EpPillVariant.outline,
                    selected: _filter == filter,
                    onPressed: () => setState(() => _filter = filter),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (loadError != null) ...[
              Text(loadError, style: Theme.of(context).textTheme.epCaption),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: EpPill(
                  key: const ValueKey('band-media-retry'),
                  label: 'RETRY',
                  onPressed: () => unawaited(media.refresh(bandId)),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (loading)
              const EpMonoText('LOADING…')
            else
              GridView.builder(
                key: const ValueKey('band-media-grid'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1,
                ),
                itemCount: 1 + uploads.length + visible.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Semantics(
                      button: true,
                      label: 'Add media',
                      child: InkWell(
                        key: const ValueKey('band-media-add'),
                        onTap: () => showEpActionSheet(
                          context,
                          header: 'Add',
                          items: [
                            EpActionSheetItem(
                              label: 'Video',
                              icon: Icons.videocam_outlined,
                              onPressed: isAdmin
                                  ? () => unawaited(
                                      media.pickAndUploadVideo(bandId),
                                    )
                                  : explainAdminGate,
                            ),
                            EpActionSheetItem(
                              label: 'Photos',
                              icon: Icons.photo_outlined,
                              onPressed: isAdmin
                                  ? () => unawaited(
                                      media.pickAndUploadPhotos(bandId),
                                    )
                                  : explainAdminGate,
                            ),
                          ],
                        ),
                        child: DashedBox(
                          color: context.epColors.border,
                          radius: EpLayout.cardRadius,
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add,
                                color: context.epColors.contentPrimary,
                              ),
                              const SizedBox(height: 6),
                              const EpMonoText('ADD'),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (index <= uploads.length) {
                    final upload = uploads[index - 1];
                    return _UploadTile(
                      key: ValueKey('band-media-upload-${upload.id}'),
                      upload: upload,
                      onRetry: isAdmin
                          ? () => unawaited(media.retryUpload(upload.id))
                          : explainAdminGate,
                      onDiscard: isAdmin
                          ? () => media.dismissUpload(upload.id)
                          : explainAdminGate,
                    );
                  }
                  final item = visible[index - uploads.length - 1];
                  return _MediaTile(
                    key: ValueKey(
                      '${item.isVideo ? 'video' : 'photo'}-media-${item.id}',
                    ),
                    item: item,
                    featured: featuredId == item.id,
                    isAdmin: isAdmin,
                    onLongPress: explainAdminGate,
                    onTap: () => _showMediaSheet(context, media, bandId, item),
                    onDrop: (id) {
                      final toIndex = media
                          .mediaFor(bandId)
                          .indexWhere((m) => m.id == item.id);
                      if (toIndex >= 0) {
                        unawaited(media.reorder(bandId, id, toIndex));
                      }
                    },
                  );
                },
              ),
            const SizedBox(height: 16),
            EpMonoText(
              'Videos up to 25 MB · photos up to 8 MB',
              key: const ValueKey('band-media-caption'),
              color: context.epColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    super.key,
    required this.item,
    required this.featured,
    required this.isAdmin,
    required this.onTap,
    required this.onLongPress,
    required this.onDrop,
  });

  final BandMedia item;
  final bool featured;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    final surface = _MediaTileSurface(item: item, featured: featured);
    final tile = Semantics(
      button: true,
      label: 'Manage ${item.title}',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: isAdmin ? null : onLongPress,
        child: surface,
      ),
    );
    if (!isAdmin) return tile;

    return LayoutBuilder(
      builder: (context, constraints) => DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != item.id,
        onAcceptWithDetails: (details) => onDrop(details.data),
        builder: (context, candidates, rejected) => LongPressDraggable<String>(
          data: item.id,
          feedback: Material(
            type: MaterialType.transparency,
            child: Transform.scale(
              scale: .9,
              child: Opacity(
                opacity: .75,
                child: SizedBox.square(
                  dimension: constraints.maxWidth,
                  child: surface,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .3, child: surface),
          child: tile,
        ),
      ),
    );
  }
}

class _MediaTileSurface extends StatelessWidget {
  const _MediaTileSurface({required this.item, required this.featured});

  final BandMedia item;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final processing = item.url == null || item.url!.isEmpty;
    final colors = context.epColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(EpLayout.cardRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _MediaThumbnail(item: item),
          if (item.isVideo) ...[
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                key: ValueKey('band-media-play-${item.id}'),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.background.withValues(alpha: .6),
                ),
                child: Icon(
                  Icons.play_arrow,
                  size: 18,
                  color: colors.contentPrimary,
                ),
              ),
            ),
            if (featured)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  key: ValueKey('band-media-featured-${item.id}'),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent,
                  ),
                  child: Icon(Icons.star, size: 16, color: colors.onAccent),
                ),
              ),
          ],
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.isVideo && item.lengthSec != null)
                  Container(
                    key: ValueKey('band-media-duration-${item.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.background.withValues(alpha: .6),
                      borderRadius: BorderRadius.circular(EpLayout.pillRadius),
                    ),
                    child: EpMonoText(
                      item.lenLabel,
                      size: 9,
                      color: colors.contentPrimary,
                    ),
                  ),
                if (processing) ...[
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(
                          EpLayout.cardRadius,
                        ),
                      ),
                      child: const EpMonoText('PROCESSING', size: 9),
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

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    super.key,
    required this.upload,
    required this.onRetry,
    required this.onDiscard,
  });

  final MediaUpload upload;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final failed = upload.phase == MediaUploadPhase.failed;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: context.epColors.surface,
        borderRadius: BorderRadius.circular(EpLayout.cardRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!failed) ...[
            LinearProgressIndicator(
              minHeight: 2,
              color: context.epColors.accent,
            ),
            const SizedBox(height: 8),
          ],
          EpMonoText(_phaseLabel(upload.phase), size: 9),
          if (failed) ...[
            const SizedBox(height: 3),
            Expanded(
              child: Text(
                upload.error ?? 'Upload failed.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.epCaption.copyWith(
                  fontSize: 9,
                  color: context.epColors.contentSecondary,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  EpPill(
                    key: ValueKey('band-media-upload-retry-${upload.id}'),
                    label: 'RETRY',
                    onPressed: onRetry,
                  ),
                  const SizedBox(width: 4),
                  EpPill(
                    key: ValueKey('band-media-upload-discard-${upload.id}'),
                    label: 'DISCARD',
                    onPressed: onDiscard,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaThumbnail extends StatelessWidget {
  const _MediaThumbnail({required this.item});

  final BandMedia item;

  @override
  Widget build(BuildContext context) => item.isVideo
      ? BandVideoThumbnail(
          media: item,
          fallback: ColoredBox(color: context.epColors.surface),
        )
      : _PhotoSurface(item: item);
}

class _PhotoSurface extends StatelessWidget {
  const _PhotoSurface({required this.item});

  final BandMedia item;

  @override
  Widget build(BuildContext context) => EpNetworkImage(
    url: item.url,
    fit: BoxFit.cover,
    fallback: ColoredBox(
      color: context.epColors.surface,
      child: Center(
        child: Icon(
          Icons.photo_outlined,
          color: context.epColors.contentDisabled,
        ),
      ),
    ),
  );
}

void _showMediaSheet(
  BuildContext context,
  BandMediaController media,
  String bandId,
  BandMedia item,
) {
  final app = context.read<AppState>();
  final isAdmin = app.isAdminOf(bandId);
  final siblings = item.isVideo
      ? media.videosFor(bandId)
      : media.photosFor(bandId);
  final position = siblings.indexWhere((m) => m.id == item.id) + 1;
  final processing = item.url == null || item.url!.isEmpty;
  final status =
      '${processing ? 'Processing' : 'Ready'} · ${item.isVideo ? 'clip' : 'photo'} $position of ${siblings.length}';

  unawaited(
    showEpSheet(context, (sheetContext) {
      void act(VoidCallback action) {
        Navigator.pop(sheetContext);
        if (app.isAdminOf(bandId)) {
          action();
        } else {
          app.say(_adminGateMessage);
        }
      }

      final colors = sheetContext.epColors;
      return EpSheetShell(
        key: const ValueKey('band-media-sheet'),
        padding: const EdgeInsets.all(EpLayout.gutter),
        topRadius: EpLayout.cardRadius,
        mainAxisSize: MainAxisSize.min,
        maxHeightFactor: .9,
        scrollable: true,
        header: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(EpLayout.cardRadius),
              child: SizedBox.square(
                dimension: 56,
                child: _MediaThumbnail(item: item),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(
                      sheetContext,
                    ).textTheme.epBody.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EpMonoText(
                        '●',
                        color: processing ? colors.muted : colors.success,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: EpMonoText(
                          status,
                          key: const ValueKey('band-media-sheet-status'),
                          keepCase: true,
                          color: colors.contentSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        children: [
          const SizedBox(height: 16),
          Opacity(
            opacity: isAdmin ? 1 : .5,
            child: Column(
              children: [
                if (item.isVideo && !item.pinned)
                  EpMenuRow(
                    key: const ValueKey('band-media-action-feature'),
                    icon: Icons.star_outline,
                    label: 'Set as featured',
                    onTap: () =>
                        act(() => unawaited(media.pin(bandId, item.id))),
                  ),
                if (media.mediaFor(bandId).indexWhere((m) => m.id == item.id) >
                    0)
                  EpMenuRow(
                    key: const ValueKey('band-media-action-front'),
                    icon: Icons.vertical_align_top,
                    label: 'Move to front',
                    onTap: () => act(
                      () => unawaited(media.moveToFront(bandId, item.id)),
                    ),
                  ),
                EpMenuRow(
                  key: const ValueKey('band-media-action-replace'),
                  icon: Icons.swap_horiz,
                  label: item.isVideo ? 'Replace video' : 'Replace photo',
                  onTap: () =>
                      act(() => unawaited(media.replace(bandId, item.id))),
                ),
                const EpHairline(),
                // EpMenuRow reads its icon and label colors from the palette.
                Theme(
                  data: Theme.of(sheetContext).copyWith(
                    extensions: [
                      ...Theme.of(sheetContext).extensions.values.where(
                        (extension) => extension is! EpPalette,
                      ),
                      colors.copyWith(
                        contentPrimary: colors.destructive,
                        contentSecondary: colors.destructive,
                      ),
                    ],
                  ),
                  child: EpMenuRow(
                    key: const ValueKey('band-media-action-remove'),
                    icon: Icons.delete_outline,
                    label: 'Remove',
                    onTap: () => act(
                      () => _showDeleteSheet(context, media, bandId, item),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }),
  );
}

class _ConfirmRemoveSheet extends StatelessWidget {
  const _ConfirmRemoveSheet({required this.item, required this.onDelete});

  final BandMedia item;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return EpSheetShell(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      backgroundColor: context.epColors.raised,
      borderColor: context.epColors.border,
      topRadius: EpLayout.cardRadius,
      handleColor: context.epColors.mute,
      handleBottomSpacing: 14,
      mainAxisSize: MainAxisSize.min,
      header: Text(
        'REMOVE ${item.isVideo ? 'VIDEO' : 'PHOTO'}?',
        style: Theme.of(context).textTheme.epSectionHeading,
      ),
      children: [
        const SizedBox(height: 8),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: context.epColors.destructive,
          ),
          onPressed: () async {
            await onDelete();
            if (!context.mounted) return;
            Navigator.pop(context);
          },
          child: Text('DELETE'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('KEEP'),
        ),
      ],
    );
  }
}

void _showDeleteSheet(
  BuildContext context,
  BandMediaController media,
  String bandId,
  BandMedia item,
) {
  showEpSheet(
    context,
    (_) => _ConfirmRemoveSheet(
      item: item,
      onDelete: () => media.remove(bandId, item.id),
    ),
  );
}

String _phaseLabel(MediaUploadPhase phase) => switch (phase) {
  MediaUploadPhase.preparing => 'Preparing',
  MediaUploadPhase.uploading => 'Uploading',
  MediaUploadPhase.saving => 'Saving',
  MediaUploadPhase.done => 'Done',
  MediaUploadPhase.failed => 'Upload failed',
};
