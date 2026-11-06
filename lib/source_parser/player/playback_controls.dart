import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

String formatPlaybackTime(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 1 << 31);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$remainder'
      : '$minutes:$remainder';
}

class PlaybackControls extends StatelessWidget {
  final VideoPlayerValue value;
  final Duration? preview;
  final bool fullscreen;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onSeekStart;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeekEnd;
  final ValueChanged<double> onSpeed;
  final ValueChanged<bool> onMenu;

  const PlaybackControls({
    super.key,
    required this.value,
    required this.preview,
    required this.fullscreen,
    required this.onPlayPause,
    required this.onToggleFullscreen,
    required this.onSeekStart,
    required this.onSeekPreview,
    required this.onSeekEnd,
    required this.onSpeed,
    required this.onMenu,
  });

  Widget _button(IconData icon, String label, VoidCallback? action) {
    return IconButton(
      tooltip: label,
      onPressed: action,
      icon: Icon(icon),
      color: Colors.white,
      disabledColor: Colors.white24,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildProgress() {
    final total = value.duration.inMilliseconds.toDouble();
    final position = (preview ?? value.position).inMilliseconds.toDouble();
    final buffered = value.buffered.isEmpty
        ? 0.0
        : value.buffered.last.end.inMilliseconds.toDouble();
    Duration at(double milliseconds) =>
        Duration(milliseconds: milliseconds.round());
    return Slider(
      value: position.clamp(0, total > 0 ? total : 1),
      secondaryTrackValue: buffered.clamp(0, total > 0 ? total : 1),
      max: total > 0 ? total : 1,
      activeColor: Colors.orange,
      inactiveColor: Colors.white24,
      secondaryActiveColor: Colors.white54,
      label: formatPlaybackTime(preview ?? value.position),
      onChangeStart: total > 0 ? (_) => onSeekStart() : null,
      onChanged: total > 0 ? (v) => onSeekPreview(at(v)) : null,
      onChangeEnd: total > 0 ? (v) => onSeekEnd(at(v)) : null,
    );
  }

  Widget _buildSpeedMenu() {
    return PopupMenuButton<double>(
      tooltip: '播放速度',
      color: const Color(0xFF292929),
      initialValue: value.playbackSpeed,
      onOpened: () => onMenu(true),
      onCanceled: () => onMenu(false),
      onSelected: (speed) {
        onSpeed(speed);
        onMenu(false);
      },
      itemBuilder: (_) => [
        for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0])
          PopupMenuItem(
            value: speed,
            child: Text(
              '${speed}x',
              style: TextStyle(
                color: speed == value.playbackSpeed
                    ? Colors.orange
                    : Colors.white,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Text(
          '${value.playbackSpeed}x',
          style: const TextStyle(color: Colors.orange),
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        _button(
          value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          value.isPlaying ? '暂停' : '播放',
          onPlayPause,
        ),
        const Spacer(),
        _buildSpeedMenu(),
        _button(
          fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          fullscreen ? '退出全屏' : '全屏',
          onToggleFullscreen,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProgress(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatPlaybackTime(preview ?? value.position)),
                  Text(formatPlaybackTime(value.duration)),
                ],
              ),
              _buildButtons(),
            ],
          ),
        ),
      ),
    );
  }
}
