import 'dart:io';

import 'package:flutter/material.dart';

import '../downloaded_file_store.dart';
import 'image_interaction_controller.dart';

class ZoomableLocalImage extends StatefulWidget {
  const ZoomableLocalImage({
    super.key,
    required this.file,
    required this.horizontal,
    required this.active,
    required this.onMove,
    required this.onDismiss,
  });

  final DownloadedFile file;
  final bool horizontal;
  final bool active;
  final ValueChanged<int> onMove;
  final VoidCallback onDismiss;

  @override
  State<ZoomableLocalImage> createState() => _ZoomableLocalImageState();
}

class _ZoomableLocalImageState extends State<ZoomableLocalImage> {
  late final ImageInteractionController _gestures;
  Offset _doubleTapPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _gestures = ImageInteractionController(
      horizontal: widget.horizontal,
      onMove: (offset) {
        if (widget.active) widget.onMove(offset);
      },
      onDismiss: () {
        if (widget.active) widget.onDismiss();
      },
    );
  }

  @override
  void didUpdateWidget(covariant ZoomableLocalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) _gestures.reset();
  }

  @override
  void dispose() {
    _gestures.dispose();
    super.dispose();
  }

  Widget _image() => Image.file(
    File(widget.file.path),
    fit: BoxFit.contain,
    errorBuilder: (_, error, stack) => const Center(
      child: Text(
        '无法读取图片，文件可能已被移动或格式不受支持。\n可滑动查看其他图片。',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _gestures,
    builder: (_, _) => AnimatedContainer(
      duration: _gestures.dismissOffset == Offset.zero
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(
        _gestures.dismissOffset.dx,
        _gestures.dismissOffset.dy,
        0,
      ),
      child: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapPoint = details.localPosition,
        onDoubleTap: () => _gestures.doubleTap(_doubleTapPoint),
        child: InteractiveViewer(
          transformationController: _gestures.transform,
          minScale: 1,
          maxScale: 5,
          onInteractionStart: _gestures.start,
          onInteractionUpdate: _gestures.update,
          onInteractionEnd: _gestures.end,
          child: SizedBox.expand(child: _image()),
        ),
      ),
    ),
  );
}
