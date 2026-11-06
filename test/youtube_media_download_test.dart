import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/ios/ios_download_operation.dart';
import 'package:videodownloader/source_parser/ios/youtube_media_download.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test(
    'YouTube media requests missing bytes and skips completed formats',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'youtube-resume-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final info = MuxedStreamInfo.fromJson(_streamJson());
      final partial = YoutubeMediaDownload.mediaFile(directory, info);
      await partial.writeAsString('abc');
      var requests = 0;
      final transport = YoutubeHttpClient(
        MockClient((request) async {
          requests++;
          expect(request.url.queryParameters['range'], startsWith('3-'));
          return http.Response('def', 206, request: request);
        }),
      );
      final youtube = YoutubeExplode(httpClient: transport);
      addTearDown(youtube.close);
      final task = DownloadTask(
        id: 'youtube',
        fileName: 'video.mp4',
        resource: const SourceResource(
          title: 'video',
          url: 'https://example.com/watch',
          type: SourceResourceType.video,
          platform: SourcePlatform.youtube,
          host: 'example.com',
          sizeHint: '',
          youtubeVideoId: 'dQw4w9WgXcQ',
        ),
      )..totalBytes = 6;
      final operation = IosDownloadOperation(
        task: task,
        isCanceled: () => false,
        onProgress: () {},
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await YoutubeMediaDownload.save(
          transport: transport,
          youtube: youtube,
          info: info,
          workspace: directory,
          operation: operation,
        );
      }
      expect(await partial.readAsString(), 'abcdef');
      expect(task.receivedBytes, 6);
      expect(task.progress, 1);
      expect(requests, 1);
    },
  );
}

Map<String, dynamic> _streamJson() => {
  'videoId': {'value': 'dQw4w9WgXcQ'},
  'tag': 18,
  'url': 'https://example.com/18',
  'container': {'name': 'mp4'},
  'size': {'totalBytes': 6},
  'bitrate': {'bitsPerSecond': 100},
  'audioCodec': 'mp4a.40.2',
  'videoCodec': 'avc1.640028',
  'qualityLabel': '1080p',
  'videoQuality': 'high1080',
  'videoResolution': {'width': 1920, 'height': 1080},
  'framerate': {'framesPerSecond': 30},
  'codec': 'video/mp4',
  'fragments': <dynamic>[],
};
