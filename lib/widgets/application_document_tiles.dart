import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Shared verification-document tiles for the application forms
/// (organization and host). Screens supply their own keys and copy.

class ApplicationDocumentTile extends StatelessWidget {
  const ApplicationDocumentTile({
    super.key,
    required this.document,
    required this.enabled,
    required this.onRemove,
    required this.removeKey,
  });

  final ApplicationDocument document;
  final bool enabled;
  final VoidCallback onRemove;
  final Key removeKey;

  bool get _isImage {
    if (document.contentType?.startsWith('image/') == true) return true;
    final path = Uri.tryParse(document.url ?? '')?.path.toLowerCase() ?? '';
    return RegExp(r'\.(jpe?g|png|gif|webp|heic)$').hasMatch(path);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: context.epColors.surface,
      child: Icon(
        _isImage ? Icons.image_outlined : Icons.description_outlined,
        color: context.epColors.contentSecondary,
        size: 30,
      ),
    );
    return SizedBox.square(
      dimension: 92,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: _isImage
                  ? EpNetworkImage(
                      url: document.url,
                      fallback: fallback,
                      cacheWidth: 92,
                      cacheHeight: 92,
                    )
                  : fallback,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filled(
              key: removeKey,
              tooltip: 'Remove document',
              onPressed: enabled ? onRemove : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              icon: const Icon(Icons.close, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class AddApplicationDocumentTile extends StatelessWidget {
  const AddApplicationDocumentTile({
    super.key,
    required this.tileKey,
    required this.enabled,
    required this.onTap,
    required this.title,
    required this.caption,
  });

  final Key tileKey;
  final bool enabled;
  final VoidCallback onTap;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      key: tileKey,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  Icons.add_a_photo_outlined,
                  color: enabled
                      ? context.epColors.accent
                      : context.epColors.contentDisabled,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        caption,
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
