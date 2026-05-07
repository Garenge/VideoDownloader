import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test('marks m3u8 resources as HLS with ffmpeg and mp4 hints', () {
    const resource = SourceResource(
      title: 'Playlist',
      url: 'https://example.com/video/master.m3u8',
      type: SourceResourceType.video,
      platform: SourcePlatform.other,
      host: 'example.com',
      sizeHint: 'application/vnd.apple.mpegurl',
    );

    expect(resource.isM3u8Playlist, isTrue);
    expect(resource.likelyHlsManifest, isTrue);
    expect(resource.requiresFfmpegPostProcess, isTrue);
    expect(
      resource.workflowHints,
      containsAll(['HLS 播放列表', '需要 ffmpeg', '推荐导出 MP4']),
    );
  });

  test('marks mpd resources as dash manifest with ffmpeg hint', () {
    const resource = SourceResource(
      title: 'Manifest',
      url: 'https://example.com/video/stream.mpd',
      type: SourceResourceType.video,
      platform: SourcePlatform.other,
      host: 'example.com',
      sizeHint: 'application/dash+xml',
    );

    expect(resource.isDashManifest, isTrue);
    expect(resource.requiresFfmpegPostProcess, isTrue);
    expect(resource.workflowHints, containsAll(['DASH 清单', '需要 ffmpeg']));
  });
}
