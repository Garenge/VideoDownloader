import 'package:flutter/material.dart';

import '../downloaded_file_actions.dart';
import '../downloaded_file_store.dart';
import 'image_preview_toolbar.dart';
import 'media_file_queue.dart';
import 'zoomable_local_image.dart';

class LocalImagePage extends StatefulWidget {
  const LocalImagePage({super.key, required this.file, this.files = const []});
  final DownloadedFile file;
  final List<DownloadedFile> files;

  @override
  State<LocalImagePage> createState() => _LocalImagePageState();
}

class _LocalImagePageState extends State<LocalImagePage> {
  late final MediaFileQueue _queue;
  late PageController _pages;
  bool _horizontal = true;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _queue = MediaFileQueue(
      widget.file,
      widget.files.where((file) => file.isImage).toList(),
    );
    _pages = PageController(initialPage: _queue.index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Future<void> _move(int offset) async {
    if (_moving) return;
    if (!_queue.move(offset)) {
      _message(offset < 0 ? '已经是第一张图片' : '已经是最后一张图片');
      return;
    }
    _moving = true;
    setState(() {});
    try {
      await _pages.animateToPage(
        _queue.index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } finally {
      _moving = false;
    }
  }

  void _changeAxis(bool horizontal) {
    if (_moving || horizontal == _horizontal) return;
    final previous = _pages;
    setState(() {
      _horizontal = horizontal;
      _pages = PageController(initialPage: _queue.index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    _message(horizontal ? '已切换为左右滑动' : '已切换为上下滑动');
  }

  Future<void> _share() async {
    try {
      await DownloadedFileActions.share(_queue.current);
    } on Object catch (error) {
      debugPrint('local_image_page.dart#_share: 图片分享失败 error=$error');
      if (mounted) _message('无法分享图片：$error');
    }
  }

  Widget _pager() => PageView.builder(
    key: ValueKey(_horizontal),
    controller: _pages,
    scrollDirection: _horizontal ? Axis.horizontal : Axis.vertical,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: _queue.files.length,
    itemBuilder: (_, index) => ZoomableLocalImage(
      key: ValueKey('${_horizontal}_${_queue.files[index].path}'),
      file: _queue.files[index],
      horizontal: _horizontal,
      active: index == _queue.index,
      onMove: _move,
      onDismiss: () {
        if (!_moving) Navigator.of(context).pop();
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Column(
      children: [
        ImagePreviewToolbar(
          title: _queue.current.name,
          position: _queue.positionLabel,
          horizontal: _horizontal,
          onAxis: _changeAxis,
          onShare: _share,
        ),
        Expanded(child: _pager()),
      ],
    ),
  );
}
