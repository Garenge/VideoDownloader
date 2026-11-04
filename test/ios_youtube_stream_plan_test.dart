import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/ios/ios_youtube_stream_plan.dart';

void main() {
  test('chooses compatible muxed MP4 over unsupported higher bitrate', () {
    final mp4 = MuxedStreamInfo.fromJson(_json(18, bitrate: 100));
    final av1 = MuxedStreamInfo.fromJson(
      _json(22, bitrate: 1000, videoCodec: 'av01.0.08M.08'),
    );
    final plan = IosYouTubeStreamPlan.select(StreamManifest([av1, mp4]));
    expect(plan.video, same(mp4));
    expect(plan.audio, isNull);
  });

  test('requires and pairs separate H264 video and AAC audio', () {
    final video = VideoOnlyStreamInfo.fromJson(_json(137));
    final audio = AudioOnlyStreamInfo.fromJson(_json(140));
    final plan = IosYouTubeStreamPlan.select(StreamManifest([video, audio]));
    expect(plan.video, same(video));
    expect(plan.audio, same(audio));
    expect(plan.totalBytes, 200);
    expect(
      () => IosYouTubeStreamPlan.select(StreamManifest([video])),
      throwsA(isA<DownloadException>()),
    );
  });

  test(
    'never labels video-only or unsupported formats as a complete video',
    () {
      final webm = VideoOnlyStreamInfo.fromJson({
        ..._json(248),
        'container': {'name': 'webm'},
      });
      final audio = AudioOnlyStreamInfo.fromJson(_json(140));
      for (final streams in [
        [webm, audio],
        [audio],
        <StreamInfo>[],
      ]) {
        expect(
          () => IosYouTubeStreamPlan.select(StreamManifest(streams)),
          throwsA(isA<DownloadException>()),
        );
      }
    },
  );
}

Map<String, dynamic> _json(
  int tag, {
  int bitrate = 100,
  String videoCodec = 'avc1.640028',
}) => {
  'videoId': {'value': 'dQw4w9WgXcQ'},
  'tag': tag,
  'url': 'https://example.com/$tag',
  'container': {'name': 'mp4'},
  'size': {'totalBytes': 100},
  'bitrate': {'bitsPerSecond': bitrate},
  'audioCodec': 'mp4a.40.2',
  'videoCodec': videoCodec,
  'qualityLabel': '1080p',
  'videoQuality': 'high1080',
  'videoResolution': {'width': 1920, 'height': 1080},
  'framerate': {'framesPerSecond': 30},
  'codec': 'video/mp4',
  'fragments': <dynamic>[],
};
