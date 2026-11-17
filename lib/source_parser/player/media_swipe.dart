import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

int swipeOffset(double distance, double velocity) {
  if (distance.abs() >= 60) return distance < 0 ? 1 : -1;
  if (distance.abs() >= 12 && velocity.abs() >= 700) {
    return velocity < 0 ? 1 : -1;
  }
  return 0;
}

/// Uses a separate vertical recognizer so seeking and long press can win
/// their own gestures on a ready video surface.
class MediaVerticalSwipe extends StatefulWidget {
  const MediaVerticalSwipe({
    super.key,
    required this.child,
    required this.onMove,
  });

  final Widget child;
  final ValueChanged<int>? onMove;

  @override
  State<MediaVerticalSwipe> createState() => _MediaVerticalSwipeState();
}

class _MediaVerticalSwipeState extends State<MediaVerticalSwipe> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    supportedDevices: const {
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
    },
    onVerticalDragStart: widget.onMove == null ? null : (_) => _distance = 0,
    onVerticalDragUpdate: widget.onMove == null
        ? null
        : (details) => _distance += details.delta.dy,
    onVerticalDragEnd: widget.onMove == null ? null : _end,
    child: widget.child,
  );

  void _end(DragEndDetails details) {
    final offset = swipeOffset(_distance, details.primaryVelocity ?? 0);
    if (offset != 0) widget.onMove?.call(offset);
  }
}
