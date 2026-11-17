import 'package:flutter/material.dart';

import 'media_swipe.dart';

class ImageInteractionController extends ChangeNotifier {
  ImageInteractionController({
    required this.horizontal,
    required this.onMove,
    required this.onDismiss,
  });

  final bool horizontal;
  final ValueChanged<int> onMove;
  final VoidCallback onDismiss;
  final transform = TransformationController();
  Offset dismissOffset = Offset.zero;
  Offset _distance = Offset.zero;
  bool _startedZoomed = false;
  bool _multiplePointers = false;
  bool get zoomed => transform.value.getMaxScaleOnAxis() > 1.02;

  void start(ScaleStartDetails details) {
    _startedZoomed = zoomed;
    _multiplePointers = details.pointerCount > 1;
    _distance = Offset.zero;
  }

  void update(ScaleUpdateDetails details) {
    _multiplePointers |= details.pointerCount > 1 || details.scale != 1;
    if (_startedZoomed || _multiplePointers) return;
    _distance += details.focalPointDelta;
    final across = horizontal ? _distance.dy : _distance.dx;
    final along = horizontal ? _distance.dx : _distance.dy;
    if (across.abs() <= along.abs()) return;
    dismissOffset = horizontal ? Offset(0, across) : Offset(across, 0);
    notifyListeners();
  }

  void end(ScaleEndDetails details) {
    if (!_startedZoomed && !_multiplePointers) _finishSwipe(details);
    dismissOffset = Offset.zero;
    notifyListeners();
  }

  void _finishSwipe(ScaleEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final along = horizontal ? _distance.dx : _distance.dy;
    final across = horizontal ? _distance.dy : _distance.dx;
    final speed = horizontal ? velocity.dx : velocity.dy;
    if (along.abs() >= across.abs()) {
      final offset = swipeOffset(along, speed);
      if (offset != 0) onMove(offset);
    } else if (swipeOffset(across, horizontal ? velocity.dy : velocity.dx) !=
        0) {
      onDismiss();
    }
  }

  void doubleTap(Offset point) {
    if (zoomed) {
      transform.value = Matrix4.identity();
    } else {
      transform.value = Matrix4.identity()
        ..setEntry(0, 0, 2.5)
        ..setEntry(1, 1, 2.5)
        ..setEntry(0, 3, -point.dx * 1.5)
        ..setEntry(1, 3, -point.dy * 1.5);
    }
  }

  void reset() {
    transform.value = Matrix4.identity();
    dismissOffset = Offset.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }
}
