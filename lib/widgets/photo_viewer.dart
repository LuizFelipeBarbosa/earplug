import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

Future<void> showPhotoViewer(
  BuildContext context,
  List<BandMedia> photos,
  int initialIndex,
) async {
  if (photos.isEmpty) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _PhotoViewerModal(photos: photos, initialIndex: initialIndex),
    ),
  );
}

class _PhotoViewerModal extends StatefulWidget {
  final List<BandMedia> photos;
  final int initialIndex;

  const _PhotoViewerModal({required this.photos, required this.initialIndex});

  @override
  State<_PhotoViewerModal> createState() => _PhotoViewerModalState();
}

class _PhotoViewerModalState extends State<_PhotoViewerModal> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                child: Center(
                  child: EpNetworkImage(
                    url: widget.photos[index].url,
                    fit: BoxFit.contain,
                    fallback: const ColoredBox(color: Ep.surface),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CircleIconButton(
                  icon: Icons.close,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (
                    var index = 0;
                    index < widget.photos.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(width: 6),
                    Container(
                      width: 4,
                      height: 4,
                      color: index == _currentIndex
                          ? Ep.contentPrimary
                          : Ep.contentDisabled,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
