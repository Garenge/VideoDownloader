import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../download_queue_controller.dart';

class IosYouTubeStreamPlan {
  const IosYouTubeStreamPlan(this.video, [this.audio]);

  final StreamInfo video;
  final StreamInfo? audio;

  int get totalBytes => video.size.totalBytes + (audio?.size.totalBytes ?? 0);

  static IosYouTubeStreamPlan select(StreamManifest manifest) {
    final muxed = _bestMp4(manifest.muxed);
    if (muxed != null) return IosYouTubeStreamPlan(muxed);
    final video = _bestMp4(manifest.videoOnly);
    final audio = _bestMp4(manifest.audioOnly);
    if (video == null || audio == null) {
      throw const DownloadException(
        '该视频没有可供 iOS 下载的 MP4 音视频流。HLS、WebM 和受保护内容暂不支持。',
      );
    }
    return IosYouTubeStreamPlan(video, audio);
  }

  static StreamInfo? _bestMp4(Iterable<StreamInfo> streams) {
    final candidates = streams.where(_isCompatible).toList()
      ..sort(
        (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
      );
    return candidates.firstOrNull;
  }

  static bool _isCompatible(StreamInfo stream) {
    if (stream.container.name != 'mp4') return false;
    if (stream is VideoStreamInfo && !stream.videoCodec.startsWith('avc1')) {
      return false;
    }
    if (stream is AudioStreamInfo && !stream.audioCodec.startsWith('mp4a')) {
      return false;
    }
    return true;
  }
}
