import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test('downloads resource into queue directory', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final controller = DownloadQueueController(
      client: MockClient((request) async {
        return http.Response('video bytes', 200, request: request);
      }),
      downloadDirectoryResolver: () async => tempDirectory,
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_resource);
    await _waitForStatus(task, DownloadStatus.completed);

    expect(task.progress, 1);
    expect(task.filePath, isNotNull);
    expect(await File(task.filePath!).readAsString(), 'video bytes');
  });
}

Future<void> _waitForStatus(DownloadTask task, DownloadStatus status) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    if (task.status == status) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  fail('waitForStatus: expected $status, got ${task.status}');
}

const _resource = SourceResource(
  title: 'Sample Video',
  url: 'https://example.com/sample.mp4',
  type: SourceResourceType.video,
  platform: SourcePlatform.other,
  host: 'example.com',
  sizeHint: 'MP4',
);
