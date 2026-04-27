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

  test('uses selected directory and can reset to default directory', () async {
    final defaultDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_default_',
    );
    final selectedDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_selected_',
    );
    addTearDown(() => defaultDirectory.delete(recursive: true));
    addTearDown(() => selectedDirectory.delete(recursive: true));

    final controller = DownloadQueueController(
      client: MockClient((request) async {
        return http.Response('download bytes', 200, request: request);
      }),
      downloadDirectoryResolver: () async => defaultDirectory,
    );
    addTearDown(controller.dispose);

    controller.setDownloadDirectory(selectedDirectory.path);
    final selectedTask = controller.enqueue(_resource);
    await _waitForStatus(selectedTask, DownloadStatus.completed);

    expect(selectedTask.filePath, startsWith(selectedDirectory.path));

    controller.resetDownloadDirectory();
    final defaultTask = controller.enqueue(_secondResource);
    await _waitForStatus(defaultTask, DownloadStatus.completed);

    expect(defaultTask.filePath, startsWith(defaultDirectory.path));
    expect(controller.selectedDirectoryPath, isNull);
  });

  test('opens completed download folder', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_open_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    String? openedPath;
    final controller = DownloadQueueController(
      client: MockClient((request) async {
        return http.Response('open bytes', 200, request: request);
      }),
      downloadDirectoryResolver: () async => tempDirectory,
      folderOpener: (path) async {
        openedPath = path;
      },
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_resource);
    await _waitForStatus(task, DownloadStatus.completed);
    await controller.openDownloadedFolder(task);

    expect(openedPath, tempDirectory.path);
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

const _secondResource = SourceResource(
  title: 'Second Video',
  url: 'https://example.com/second.mp4',
  type: SourceResourceType.video,
  platform: SourcePlatform.other,
  host: 'example.com',
  sizeHint: 'MP4',
);
