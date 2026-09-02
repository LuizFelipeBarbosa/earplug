import 'dart:async';

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
import '../widgets/sheets.dart';
import '../widgets/video_thumbnail.dart';

const _adminGateMessage = 'Only band admins can post media.';
const _uploadActionPadding = EdgeInsets.symmetric(vertical: 3);

class BandMediaScreen extends StatelessWidget {
  const BandMediaScreen({super.key, required this.bandId});

  final String bandId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final media = context.watch<BandMediaController>();
    final items = media.mediaFor(bandId);
    final videos = media.videosFor(bandId);
    final photos = media.photosFor(bandId);
    final uploads = media.uploadsFor(bandId);
    final loadError = media.loadErrorFor(bandId);
    final loading = media.isLoading(bandId) && items.isEmpty;
    final isAdmin = app.isAdminOf(bandId);

    void explainAdminGate() => app.say(_adminGateMessage);

    final listRows = <_MediaListRow>[
      _MediaWidgetRow(
        Text(
          'Upload clips and gallery photos, then choose what fans see first.',
          style: Theme.of(context).textTheme.epCaption,
        ),
      ),
      const _MediaWidgetRow(SizedBox(height: 14)),
      _MediaWidgetRow(
        _UploadActions(
          enabled: isAdmin,
          onVideo: isAdmin
              ? () => media.pickAndUploadVideo(bandId)
              : explainAdminGate,
          onPhotos: isAdmin
              ? () => media.pickAndUploadPhotos(bandId)
              : explainAdminGate,
        ),
      ),
      if (uploads.isNotEmpty) ...[
        _MediaWidgetRow(SectionBar(label: 'Uploads', count: uploads.length)),
        for (final upload in uploads) _MediaUploadRow(upload),
      ],
      if (loadError != null) ...[
        const _MediaWidgetRow(SizedBox(height: 18)),
        _MediaWidgetRow(
          _LoadFailure(
            message: loadError,
            onRetry: () => media.refresh(bandId),
          ),
        ),
      ] else if (loading) ...[
        const _MediaWidgetRow(SizedBox(height: 18)),
        const _MediaWidgetRow(_LoadingMedia()),
      ],
      _MediaWidgetRow(
        SectionBar(label: 'This is what we sound like', count: videos.length),
      ),
      _MediaWidgetRow(
        Text(
          'The featured clip plays first on the public profile. Use each clip menu to feature, reorder, or remove it.',
          style: Theme.of(context).textTheme.epCaption,
        ),
      ),
      const _MediaWidgetRow(SizedBox(height: 10)),
      if (!loading && videos.isEmpty)
        _MediaWidgetRow(
          _EmptyMediaState(
            icon: Icons.videocam_outlined,
            title: 'NO VIDEOS YET',
            message: 'Upload a music clip to give fans a clear first listen.',
            actionLabel: isAdmin ? 'UPLOAD A MUSIC CLIP' : null,
            onAction: isAdmin ? () => media.pickAndUploadVideo(bandId) : null,
          ),
        )
      else
        for (final (index, video) in videos.indexed)
          _MediaVideoRow(video, index),
      _MediaWidgetRow(
        SectionBar(label: 'Gallery photos', count: photos.length),
      ),
      _MediaWidgetRow(
        Text(
          'These photos appear in the public gallery in the order shown.',
          style: Theme.of(context).textTheme.epCaption,
        ),
      ),
      const _MediaWidgetRow(SizedBox(height: 10)),
    ];

    return ColoredBox(
      color: context.epColors.background,
      child: Column(
        children: [
          _MediaHeader(itemCount: items.length, onBack: app.back),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth - 32 < 350 ? 2 : 3;
                final bottomPadding = 40 + MediaQuery.paddingOf(context).bottom;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final row = listRows[index];
                          return switch (row) {
                            _MediaWidgetRow(:final child) => child,
                            _MediaUploadRow(:final upload) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _UploadTile(upload: upload, media: media),
                            ),
                            _MediaVideoRow(:final video, :final position) =>
                              Padding(
                                padding: const EdgeInsets.only(bottom: 9),
                                child: _VideoManageCard(
                                  item: video,
                                  position: position,
                                  total: videos.length,
                                  isAdmin: isAdmin,
                                  onManage: () => _showMediaActions(
                                    context,
                                    media: media,
                                    bandId: bandId,
                                    item: video,
                                    position: position,
                                    total: videos.length,
                                  ),
                                ),
                              ),
                          };
                        }, childCount: listRows.length),
                      ),
                    ),
                    if (!loading && photos.isEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
                        sliver: SliverToBoxAdapter(
                          child: _EmptyMediaState(
                            icon: Icons.photo_library_outlined,
                            title: 'NO GALLERY PHOTOS YET',
                            message:
                                'Add show, rehearsal, or behind-the-scenes photos for fans.',
                            actionLabel: isAdmin ? 'UPLOAD PHOTOS' : null,
                            onAction: isAdmin
                                ? () => media.pickAndUploadPhotos(bandId)
                                : null,
                          ),
                        ),
                      )
                    else if (photos.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
                        sliver: SliverGrid.builder(
                          itemCount: photos.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 9,
                                crossAxisSpacing: 9,
                                childAspectRatio: .78,
                              ),
                          itemBuilder: (context, index) => _PhotoManageTile(
                            item: photos[index],
                            position: index,
                            total: photos.length,
                            isAdmin: isAdmin,
                            onManage: () => _showMediaActions(
                              context,
                              media: media,
                              bandId: bandId,
                              item: photos[index],
                              position: index,
                              total: photos.length,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverToBoxAdapter(
                        child: SizedBox(height: bottomPadding),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _MediaListRow {
  const _MediaListRow();
}

class _MediaWidgetRow extends _MediaListRow {
  const _MediaWidgetRow(this.child);

  final Widget child;
}

class _MediaUploadRow extends _MediaListRow {
  const _MediaUploadRow(this.upload);

  final MediaUpload upload;
}

class _MediaVideoRow extends _MediaListRow {
  const _MediaVideoRow(this.video, this.position);

  final BandMedia video;
  final int position;
}

class _MediaHeader extends StatelessWidget {
  const _MediaHeader({required this.itemCount, required this.onBack});

  final int itemCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.epColors.border)),
      ),
      child: Row(
        children: [
          CircleIconButton(onTap: onBack),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'BAND MEDIA',
              style: Theme.of(context).textTheme.epPageHeading,
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
            tone: EpStatusPillTone.neutral,
          ),
        ],
      ),
    );
  }
}

class _UploadActions extends StatelessWidget {
  const _UploadActions({
    required this.enabled,
    required this.onVideo,
    required this.onPhotos,
  });

  final bool enabled;
  final VoidCallback onVideo;
  final VoidCallback onPhotos;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 330 || scale > 1.3;
        final video = _UploadAction(
          icon: Icons.videocam_outlined,
          label: 'UPLOAD VIDEO',
          detail: 'MP4 · 25 MB MAX',
          enabled: enabled,
          onTap: onVideo,
        );
        final photos = _UploadAction(
          icon: Icons.add_photo_alternate_outlined,
          label: 'UPLOAD PHOTOS',
          detail: 'UP TO 10 · 8 MB EACH',
          enabled: enabled,
          onTap: onPhotos,
        );
        if (stacked) {
          return Column(children: [video, const SizedBox(height: 9), photos]);
        }
        return Row(
          children: [
            Expanded(child: video),
            const SizedBox(width: 9),
            Expanded(child: photos),
          ],
        );
      },
    );
  }
}

class _UploadAction extends StatelessWidget {
  const _UploadAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? context.epColors.contentPrimary
        : context.epColors.contentDisabled;
    return EpCard(
      variant: enabled ? EpCardVariant.raised : EpCardVariant.disabled,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: enabled
                  ? context.epColors.selected
                  : context.epColors.surfaceDisabled,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              color: enabled
                  ? context.epColors.accent
                  : context.epColors.contentDisabled,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.epLabel.copyWith(color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(
                    context,
                  ).textTheme.epMeta.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({required this.upload, required this.media});

  final MediaUpload upload;
  final BandMediaController media;

  @override
  Widget build(BuildContext context) {
    final failed = upload.phase == MediaUploadPhase.failed;
    return EpCard(
      borderColor: failed
          ? context.epColors.destructive
          : context.epColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: upload.preview != null
                      ? Image.memory(
                          upload.preview!,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (54 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                        )
                      : ColoredBox(
                          color: context.epColors.surfaceRaised,
                          child: Center(
                            child: PlayTriangle(
                              size: 11,
                              color: context.epColors.contentPrimary,
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
                      style: Theme.of(
                        context,
                      ).textTheme.epBody.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    StatusPill(
                      label: failed
                          ? 'Upload failed'
                          : _phaseLabel(upload.phase),
                      tone: failed
                          ? EpStatusPillTone.warning
                          : EpStatusPillTone.selected,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: 10),
            Text(
              upload.error ?? 'Upload failed.',
              style: Theme.of(context).textTheme.epCaption.copyWith(
                color: context.epColors.destructive,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextAction(
                  'RETRY',
                  color: context.epColors.accent,
                  padding: _uploadActionPadding,
                  onTap: () => media.retryUpload(upload.id),
                ),
                const SizedBox(width: 18),
                TextAction(
                  'DISCARD',
                  color: context.epColors.contentSecondary,
                  padding: _uploadActionPadding,
                  onTap: () => media.dismissUpload(upload.id),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 11),
            LinearProgressIndicator(
              minHeight: 3,
              color: context.epColors.accent,
              backgroundColor: context.epColors.surfaceDisabled,
            ),
          ],
        ],
      ),
    );
  }
}

class _VideoManageCard extends StatelessWidget {
  const _VideoManageCard({
    required this.item,
    required this.position,
    required this.total,
    required this.isAdmin,
    required this.onManage,
  });

  final BandMedia item;
  final int position;
  final int total;
  final bool isAdmin;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final processing = item.url == null || item.url!.isEmpty;
    final details = [
      'CLIP ${position + 1} OF $total',
      if (item.lenLabel.isNotEmpty) item.lenLabel,
      if (item.viewsLabel.isNotEmpty) item.viewsLabel,
    ];
    return EpCard(
      key: ValueKey('video-media-${item.id}'),
      variant: item.pinned ? EpCardVariant.selected : EpCardVariant.raised,
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 118,
              height: 78,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BandVideoThumbnail(
                    media: item,
                    fallback: ColoredBox(color: context.epColors.surfaceRaised),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  const Center(
                    child: PlayTriangle(size: 11, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.epBody.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    if (item.pinned)
                      const StatusPill(
                        label: 'Featured first',
                        tone: EpStatusPillTone.selected,
                      ),
                    StatusPill(
                      label: processing ? 'Processing' : 'Ready',
                      tone: processing
                          ? EpStatusPillTone.warning
                          : EpStatusPillTone.success,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  details.join(' · '),
                  style: Theme.of(context).textTheme.epMeta,
                ),
              ],
            ),
          ),
          if (isAdmin)
            IconButton(
              key: ValueKey('media-actions-${item.id}'),
              tooltip: 'Manage ${item.title}',
              onPressed: onManage,
              icon: Icon(Icons.more_horiz),
            ),
        ],
      ),
    );
  }
}

class _PhotoManageTile extends StatelessWidget {
  const _PhotoManageTile({
    required this.item,
    required this.position,
    required this.total,
    required this.isAdmin,
    required this.onManage,
  });

  final BandMedia item;
  final int position;
  final int total;
  final bool isAdmin;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final processing = item.url == null || item.url!.isEmpty;
    return EpCard(
      key: ValueKey('photo-media-${item.id}'),
      variant: EpCardVariant.raised,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                  child: _PhotoSurface(
                    item: item,
                    placeholderLabel: 'PHOTO ${position + 1}',
                  ),
                ),
                if (processing)
                  const Positioned(
                    left: 7,
                    top: 7,
                    child: StatusPill(
                      label: 'Processing',
                      tone: EpStatusPillTone.warning,
                    ),
                  ),
                if (isAdmin)
                  Positioned(
                    right: 3,
                    top: 3,
                    child: IconButton.filled(
                      key: ValueKey('media-actions-${item.id}'),
                      tooltip: 'Manage ${item.title}',
                      onPressed: onManage,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: .72),
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(Icons.more_horiz),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.epCaption.copyWith(
                    color: context.epColors.contentPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'PHOTO ${position + 1} OF $total',
                  style: Theme.of(context).textTheme.epMeta,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoSurface extends StatelessWidget {
  const _PhotoSurface({required this.item, this.placeholderLabel});

  final BandMedia item;
  final String? placeholderLabel;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: context.epColors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_outlined, color: context.epColors.contentDisabled),
            if (placeholderLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                placeholderLabel!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.epMeta,
              ),
            ],
          ],
        ),
      ),
    );
    return EpNetworkImage(
      url: item.url,
      fit: BoxFit.cover,
      fallback: placeholder,
    );
  }
}

class _EmptyMediaState extends StatelessWidget {
  const _EmptyMediaState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          Icon(icon, color: context.epColors.contentDisabled),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.epSectionHeading),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.epCaption,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            TextAction(
              actionLabel!,
              onTap: onAction,
              color: context.epColors.accent,
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingMedia extends StatelessWidget {
  const _LoadingMedia();

  @override
  Widget build(BuildContext context) {
    return EpCard(
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('LOADING MEDIA…', style: Theme.of(context).textTheme.epLabel),
        ],
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EpCard(
      borderColor: context.epColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusPill(
            label: 'Media unavailable',
            tone: EpStatusPillTone.warning,
          ),
          const SizedBox(height: 9),
          Text(message, style: Theme.of(context).textTheme.epCaption),
          const SizedBox(height: 10),
          TextAction('RETRY', onTap: onRetry, color: context.epColors.accent),
        ],
      ),
    );
  }
}

void _showMediaActions(
  BuildContext context, {
  required BandMediaController media,
  required String bandId,
  required BandMedia item,
  required int position,
  required int total,
}) {
  final kindLabel = item.isVideo ? 'video' : 'photo';
  unawaited(
    showEpActionSheet(
      context,
      header: item.title,
      items: [
        if (item.isVideo && !item.pinned)
          EpActionSheetItem(
            label: 'Feature first',
            icon: Icons.push_pin_outlined,
            onPressed: () => unawaited(media.pin(bandId, item.id)),
          ),
        if (position > 0)
          EpActionSheetItem(
            label: 'Move earlier',
            icon: Icons.arrow_upward,
            onPressed: () =>
                unawaited(media.moveWithinKind(bandId, item.id, 'up')),
          ),
        if (position < total - 1)
          EpActionSheetItem(
            label: 'Move later',
            icon: Icons.arrow_downward,
            onPressed: () =>
                unawaited(media.moveWithinKind(bandId, item.id, 'down')),
          ),
        EpActionSheetItem(
          label: 'Remove $kindLabel…',
          icon: Icons.delete_outline,
          destructive: true,
          onPressed: () => _showDeleteSheet(context, media, bandId, item),
        ),
      ],
    ),
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
      topRadius: 16,
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
