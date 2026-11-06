import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// A controller with no native decoder, used to exercise real widget gestures.
class TestVideoController extends VideoPlayerController {
  final List<Duration> seeks = [];
  final List<double> speeds = [];

  TestVideoController({
    bool playing = true,
    double speed = 1,
    Size size = const Size(1920, 1080),
  }) : super.networkUrl(Uri.parse('https://example.com/test.mp4')) {
    value = VideoPlayerValue(
      duration: const Duration(minutes: 10),
      position: const Duration(seconds: 60),
      size: size,
      isInitialized: true,
      isPlaying: playing,
      playbackSpeed: speed,
    );
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    speeds.add(speed);
    value = value.copyWith(playbackSpeed: speed);
  }
}
