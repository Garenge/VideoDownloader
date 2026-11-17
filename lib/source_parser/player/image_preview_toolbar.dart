import 'package:flutter/material.dart';

class ImagePreviewToolbar extends StatelessWidget {
  const ImagePreviewToolbar({
    super.key,
    required this.title,
    required this.position,
    required this.horizontal,
    required this.onAxis,
    required this.onShare,
  });

  final String title;
  final String position;
  final bool horizontal;
  final ValueChanged<bool> onAxis;
  final VoidCallback onShare;

  Widget _directionMenu() => PopupMenuButton<bool>(
    tooltip: '图片切换方式',
    initialValue: horizontal,
    onSelected: onAxis,
    icon: const Icon(Icons.swipe, color: Colors.white),
    itemBuilder: (_) => [
      CheckedPopupMenuItem(
        value: true,
        checked: horizontal,
        child: const Text('左右滑动切换'),
      ),
      CheckedPopupMenuItem(
        value: false,
        checked: !horizontal,
        child: const Text('上下滑动切换'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ColoredBox(
      color: Colors.black87,
      child: Row(
        children: [
          const BackButton(color: Colors.white),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                Text(position, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          _directionMenu(),
          IconButton(
            tooltip: '分享或用系统应用打开',
            onPressed: onShare,
            icon: const Icon(Icons.ios_share, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}
