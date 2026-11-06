import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'playback_controls.dart';

class VideoPlayerSurface extends StatefulWidget {
  final VideoPlayerController? controller;
  final String title;
  final bool loading;
  final String? error;
  final bool fullscreen;
  final bool active;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  const VideoPlayerSurface({
    super.key,
    required this.controller,
    required this.title,
    required this.onToggleFullscreen,
    this.loading = false,
    this.error,
    this.fullscreen = false,
    this.active = true,
    this.onRetry,
    this.onBack,
  });

  @override
  State<VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<VideoPlayerSurface>
    with WidgetsBindingObserver {
  Timer? _hideTimer;
  bool _visible = true;
  bool _menuOpen = false;
  bool _seeking = false;
  bool _resumeAfterSeek = false;
  bool _fastForward = false;
  bool _wasPlaying = false;
  bool _foreground = true;
  int _seekGeneration = 0;
  double _originalSpeed = 1;
  double _dragDistance = 0;
  Duration _dragStart = Duration.zero;
  Duration? _preview;

  VideoPlayerController? get _controller => widget.controller;
  bool get _ready =>
      _controller?.value.isInitialized == true &&
      !widget.loading &&
      widget.error == null &&
      _controller?.value.hasError == false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller?.addListener(_onValueChanged);
    _wasPlaying = _controller?.value.isPlaying ?? false;
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != _controller) {
      _seekGeneration++;
      oldWidget.controller?.removeListener(_onValueChanged);
      _controller?.addListener(_onValueChanged);
      _preview = null;
      _seeking = false;
      _fastForward = false;
      _visible = true;
      _wasPlaying = _controller?.value.isPlaying ?? false;
      _scheduleHide();
    }
    if (oldWidget.active && !widget.active) _cancelInteraction();
    if (!oldWidget.active && widget.active) _scheduleHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _controller?.removeListener(_onValueChanged);
    _resumeAfterSeek = false;
    _restoreSpeed();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!widget.active || state == AppLifecycleState.resumed) return;
    _resumeAfterSeek = false;
    _cancelInteraction();
    _run((controller) => controller.pause());
  }

  Future<void> _run(
    Future<void> Function(VideoPlayerController controller) action,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await action(controller);
    } catch (error, stack) {
      debugPrint('video_player_surface.dart#_run: 播放控制失败 error=$error\n$stack');
    }
  }

  void _onValueChanged() {
    if (!mounted || !widget.active) return;
    final playing = _controller?.value.isPlaying ?? false;
    if (playing != _wasPlaying) {
      _wasPlaying = playing;
      if (!playing && !_seeking) {
        _restoreSpeed();
        _visible = true;
      }
      _scheduleHide();
    }
    setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_ready ||
        !widget.active ||
        _seeking ||
        _fastForward ||
        _menuOpen ||
        _controller?.value.isPlaying != true) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggleControls() {
    setState(() => _visible = !_visible);
    _scheduleHide();
  }

  Future<void> _playPause() async {
    await _run((controller) async {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await _play(controller);
      }
    });
    _scheduleHide();
  }

  Future<void> _play(VideoPlayerController controller) => controller.play();

  Future<void> _selectSpeed(double speed) async {
    await _run((c) => c.setPlaybackSpeed(speed));
  }

  void _startSeek() {
    if (!_ready || _seeking) return;
    _hideTimer?.cancel();
    _seekGeneration++;
    _resumeAfterSeek = _controller!.value.isPlaying;
    setState(() {
      _seeking = true;
      _preview = _controller!.value.position;
    });
    _run((controller) => controller.pause());
  }

  void _previewSeek(Duration position) {
    if (!_seeking) return;
    final total = _controller!.value.duration.inMilliseconds;
    setState(
      () => _preview = Duration(
        milliseconds: position.inMilliseconds.clamp(0, total),
      ),
    );
  }

  Future<void> _endSeek(Duration position) async {
    if (!_seeking) return;
    final controller = _controller;
    final generation = _seekGeneration;
    final resume = _resumeAfterSeek;
    await _run((c) async {
      await c.seekTo(position);
      if (mounted &&
          c == _controller &&
          widget.active &&
          _foreground &&
          generation == _seekGeneration &&
          resume) {
        await _play(c);
      }
    });
    if (!mounted ||
        controller != _controller ||
        generation != _seekGeneration) {
      return;
    }
    setState(() {
      _seeking = false;
      _preview = null;
      _visible = true;
    });
    _scheduleHide();
  }

  void _cancelSeek() {
    if (!_seeking) return;
    _seekGeneration++;
    final resume = _resumeAfterSeek;
    setState(() {
      _seeking = false;
      _preview = null;
    });
    if (resume && widget.active && _foreground) _run((c) => _play(c));
    _scheduleHide();
  }

  void _startFastForward() {
    if (!_ready ||
        _seeking ||
        _fastForward ||
        !widget.active ||
        _controller!.value.isPlaying == false) {
      return;
    }
    _originalSpeed = _controller!.value.playbackSpeed;
    _hideTimer?.cancel();
    setState(() => _fastForward = true);
    _enterFastForward();
  }

  Future<void> _enterFastForward() async {
    await _run((c) => c.setPlaybackSpeed(2));
    if (!mounted || !_fastForward || _controller?.value.playbackSpeed != 2) {
      return;
    }
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      try {
        await HapticFeedback.lightImpact();
      } catch (error, stack) {
        debugPrint(
          'video_player_surface.dart#_enterFastForward: 触感反馈失败 error=$error\n$stack',
        );
      }
    }
  }

  void _restoreSpeed() {
    if (!_fastForward) return;
    _fastForward = false;
    _run((c) => c.setPlaybackSpeed(_originalSpeed));
  }

  void _endFastForward() {
    _restoreSpeed();
    if (mounted) setState(() {});
    _scheduleHide();
  }

  void _cancelInteraction() {
    _cancelSeek();
    _endFastForward();
  }

  void _dragUpdate(DragUpdateDetails details, double width) {
    if (!_seeking || width <= 0) return;
    _dragDistance += details.delta.dx;
    // One screen moves at most two minutes, even for a long video.
    final span = _controller!.value.duration.inMilliseconds.clamp(0, 120000);
    _previewSeek(
      _dragStart +
          Duration(milliseconds: (_dragDistance / width * span).round()),
    );
  }

  Widget _buildGestureLayer(double width) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTap: widget.onToggleFullscreen,
      onLongPressStart: (_) => _startFastForward(),
      onLongPressEnd: (_) => _endFastForward(),
      onLongPressCancel: _endFastForward,
      onHorizontalDragStart: (_) {
        _dragStart = _controller!.value.position;
        _dragDistance = 0;
        _startSeek();
      },
      onHorizontalDragUpdate: (details) => _dragUpdate(details, width),
      onHorizontalDragEnd: (_) => _endSeek(_preview ?? _dragStart),
      onHorizontalDragCancel: _cancelSeek,
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              tooltip: '返回',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    final error = widget.error ?? _controller?.value.errorDescription;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.orange, size: 32),
              const SizedBox(height: 8),
              Text(
                error,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (widget.onRetry != null)
                TextButton(onPressed: widget.onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(color: Colors.orange));
  }

  Widget _buildMessage(
    String message, {
    Alignment alignment = Alignment.center,
  }) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(VideoPlayerValue value) {
    return PlaybackControls(
      value: value,
      preview: _preview,
      fullscreen: widget.fullscreen,
      onPlayPause: _playPause,
      onToggleFullscreen: widget.onToggleFullscreen,
      onSeekStart: _startSeek,
      onSeekPreview: _previewSeek,
      onSeekEnd: _endSeek,
      onSpeed: _selectSpeed,
      onMenu: (open) {
        _menuOpen = open;
        _scheduleHide();
      },
    );
  }

  List<Widget> _buildPlayback(VideoPlayerValue value, double width) {
    final aspectRatio = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
    return [
      Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: VideoPlayer(_controller!),
        ),
      ),
      Positioned.fill(child: _buildGestureLayer(width)),
      if (!_visible)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(
            minHeight: 2,
            value: value.duration.inMilliseconds > 0
                ? (value.position.inMilliseconds /
                          value.duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                : 0,
            color: Colors.orange,
            backgroundColor: Colors.white24,
          ),
        ),
      if (_visible && !_fastForward) ...[
        Positioned(bottom: 0, left: 0, right: 0, child: _buildControls(value)),
        if (widget.fullscreen || widget.onBack != null)
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),
      ],
      if (value.isBuffering && !_seeking && !_fastForward)
        const Center(
          child: IgnorePointer(
            child: CircularProgressIndicator(color: Colors.orange),
          ),
        ),
      if (_seeking && _preview != null)
        _buildMessage(
          '${formatPlaybackTime(_preview!)} / '
          '${formatPlaybackTime(value.duration)}\n松开跳转',
        ),
      if (_fastForward)
        SafeArea(
          minimum: const EdgeInsets.all(12),
          child: _buildMessage('2.0x 快进中', alignment: Alignment.bottomRight),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.white, fontSize: 12),
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Listener(
              onPointerCancel: (_) => _cancelInteraction(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_ready)
                    ..._buildPlayback(_controller!.value, constraints.maxWidth)
                  else ...[
                    _buildStatus(),
                    if (widget.onBack != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildHeader(),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
