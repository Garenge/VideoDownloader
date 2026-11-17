import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../downloaded_file_actions.dart';
import '../downloaded_file_store.dart';
import 'video_player_surface.dart';
import 'media_file_queue.dart';
import 'media_swipe.dart';

class LocalVideoPage extends StatefulWidget {
  const LocalVideoPage({super.key, required this.file, this.files = const []});

  final DownloadedFile file;
  final List<DownloadedFile> files;

  @override
  State<LocalVideoPage> createState() => _LocalVideoPageState();
}

class _LocalVideoPageState extends State<LocalVideoPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;
  bool _fullscreen = false;
  bool _changingScreen = false;
  bool _foreground = true;
  int _generation = 0;
  late final MediaFileQueue _queue;
  bool _switching = false;
  DownloadedFile get _file => _queue.current;

  @override
  void initState() {
    super.initState();
    _queue = MediaFileQueue(
      widget.file,
      widget.files.where((file) => file.isVideo).toList(),
    );
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _controller?.dispose();
    if (_fullscreen || _changingScreen) _setScreenMode(false);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final previous = _controller;
    setState(() {
      _controller = null;
      _error = null;
      _loading = true;
    });
    if (previous != null) await _release(previous);
    VideoPlayerController? candidate;
    try {
      final file = File(_file.path);
      if (!await file.exists()) {
        throw const FileSystemException('文件已被移动或删除');
      }
      candidate = VideoPlayerController.file(
        file,
        // The surface owns background pausing; disable the plugin's auto-resume.
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
      );
      await candidate.initialize();
      if (!mounted || generation != _generation) {
        await candidate.dispose();
        return;
      }
      setState(() {
        _controller = candidate;
        _loading = false;
      });
      if (_foreground) await candidate.play();
    } on Object catch (error) {
      // A failed native creation may leave the plugin's disposal waiting.
      // Keep the error and retry UI available while cleanup runs.
      if (candidate != null) unawaited(_release(candidate));
      debugPrint('local_video_page.dart#_load: 视频加载失败 error=$error');
      if (!mounted || generation != _generation) return;
      setState(() {
        _controller = null;
        _loading = false;
        _error = '无法播放此视频，请重试或用系统应用打开。';
      });
    }
  }

  Future<void> _move(int offset) async {
    if (_switching || _loading || _changingScreen) return;
    if (!_queue.move(offset)) {
      _showMessage(offset < 0 ? '已经是第一个视频' : '已经是最后一个视频');
      return;
    }
    _switching = true;
    _showMessage(offset > 0 ? '下一个视频' : '上一个视频');
    try {
      await _load();
      if (mounted && _fullscreen) await _setScreenMode(true);
    } finally {
      _switching = false;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Future<void> _release(VideoPlayerController controller) async {
    try {
      try {
        await controller.pause();
      } finally {
        await controller.dispose();
      }
    } on Object catch (error) {
      debugPrint('local_video_page.dart#_release: 播放资源释放失败 error=$error');
    }
  }

  Future<void> _setScreenMode(bool fullscreen) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await SystemChrome.setPreferredOrientations(
        fullscreen
            ? (_controller?.value.aspectRatio ?? 1) >= 1
                  ? [
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]
                  : [DeviceOrientation.portraitUp]
            : [],
      );
      await SystemChrome.setEnabledSystemUIMode(
        fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } on Object catch (error) {
      debugPrint('local_video_page.dart#_setScreenMode: 屏幕切换失败 error=$error');
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_changingScreen) return;
    _changingScreen = true;
    final fullscreen = !_fullscreen;
    setState(() => _fullscreen = fullscreen);
    try {
      await _setScreenMode(fullscreen);
      if (!mounted) await _setScreenMode(false);
    } finally {
      _changingScreen = false;
    }
  }

  void _back() {
    if (_fullscreen) {
      _toggleFullscreen();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openExternally() async {
    try {
      await _controller?.pause();
      if (_fullscreen) await _toggleFullscreen();
      await DownloadedFileActions.open(_file);
    } on Object catch (error) {
      debugPrint('local_video_page.dart#_openExternally: 系统打开失败 error=$error');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开文件：$error')));
    }
  }

  Widget _buildHeader() => SafeArea(
    bottom: false,
    child: Row(
      children: [
        BackButton(color: Colors.white, onPressed: _back),
        Expanded(
          child: Text(
            '${_file.name} · ${_queue.positionLabel}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        IconButton(
          tooltip: '用系统应用打开',
          onPressed: _openExternally,
          icon: const Icon(Icons.open_in_new, color: Colors.white),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_fullscreen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _fullscreen) _toggleFullscreen();
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          if (!_fullscreen) _buildHeader(),
          Expanded(
            child: MediaVerticalSwipe(
              onMove: _move,
              child: VideoPlayerSurface(
                controller: _controller,
                title: '${_file.name} · ${_queue.positionLabel}',
                loading: _loading,
                error: _error,
                fullscreen: _fullscreen,
                onRetry: _load,
                onBack: _fullscreen ? _back : null,
                onToggleFullscreen: _toggleFullscreen,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
