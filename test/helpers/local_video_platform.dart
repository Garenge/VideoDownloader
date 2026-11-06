import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
// The player exposes its test platform through this transitive dependency.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Exercises real video controllers without a native decoder.
class LocalVideoPlatform extends VideoPlayerPlatform {
  int _nextId = 0;
  final disposed = <int>[];
  final playing = <int>{};
  final sources = <DataSource>[];
  bool failInitialization = false;
  bool failCreation = false;
  final Map<int, Duration> _positions = {};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (failCreation) {
      throw PlatformException(code: 'create_failed', message: '无法创建播放器');
    }
    sources.add(options.dataSource);
    return ++_nextId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => failInitialization
      ? Stream.error(PlatformException(code: 'decode_failed', message: '无法解码'))
      : Stream.value(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(minutes: 10),
            size: const Size(1280, 720),
          ),
        );

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    playing.remove(playerId);
    _positions.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    playing.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    playing.remove(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;
}
