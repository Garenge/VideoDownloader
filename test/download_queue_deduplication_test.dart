import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/download_queue_store.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  late _Downloads downloads;
  setUp(() async {
    downloads = _Downloads(await Directory.systemTemp.createTemp('dedupe_'));
  });
  tearDown(() => downloads.dispose());

  test('completed resource does not create a task or request again', () async {
    final controller = downloads.controller();
    final task = (await controller.enqueue(_resource))!;
    await _waitForHistory(controller);
    expect(
      controller.history.single.resourceIdentity,
      _resource.downloadIdentity,
    );
    expect(await controller.enqueue(_resource), isNull);
    expect(controller.tasks.single, same(task));
    expect(downloads.requests, 1);
  });

  test('clearing completed tasks still skips downloaded resources', () async {
    final controller = downloads.controller();
    await controller.enqueue(_resource);
    await _waitForHistory(controller);
    controller.clearFinishedTasks();
    expect(await controller.enqueue(_resource), isNull);
    expect(controller.tasks, isEmpty);
    expect(downloads.requests, 1);
  });

  test('completed queue entry works without download history', () async {
    final controller = downloads.controller();
    await controller.enqueue(_resource);
    await _waitForHistory(controller);
    await controller.clearHistory();
    expect(await controller.enqueue(_resource), isNull);
    expect(controller.tasks, hasLength(1));
    expect(downloads.requests, 1);
  });

  test('missing completed file allows another download', () async {
    final controller = downloads.controller();
    final task = (await controller.enqueue(_resource))!;
    await _waitForHistory(controller);
    await File(task.filePath!).delete();
    final previousCompletion = controller.history.single.completedAt;
    final replacement = await controller.enqueue(_resource);
    expect(replacement, isNotNull);
    await _waitForHistory(controller, after: previousCompletion);
    expect(controller.tasks, hasLength(2));
    expect(downloads.requests, 2);
  });

  test('enqueue waits for persisted history during startup', () async {
    await downloads.seedHistory(_resource.url);
    final controller = downloads.controller();
    expect(await controller.enqueue(_resource), isNull);
    expect(controller.tasks, isEmpty);
    expect(downloads.requests, 0);
  });

  test('same title with a different URL can still download', () async {
    await downloads.seedHistory('https://example.com/other.mp4');
    final controller = downloads.controller();
    expect(await controller.enqueue(_resource), isNotNull);
    await _waitForHistory(controller);
    expect(downloads.requests, 1);
  });

  test('legacy history recognizes alternate YouTube video links', () async {
    await downloads.seedHistory('https://youtu.be/video-id');
    final controller = downloads.controller();
    expect(await controller.enqueue(_youtube), isNull);
    expect(controller.tasks, isEmpty);
  });

  test('persisted identity supports explicit YouTube IDs', () async {
    await downloads.seedHistory(
      'https://example.com/old-signed-url',
      identity: _youtube.downloadIdentity,
    );
    final controller = downloads.controller();
    expect(await controller.enqueue(_youtube), isNull);
    expect(controller.tasks, isEmpty);
  });
}

Future<void> _waitForHistory(
  DownloadQueueController controller, {
  DateTime? after,
}) async {
  for (var i = 0; i < 200; i++) {
    if (controller.history.isNotEmpty &&
        (after == null ||
            controller.history.first.completedAt.isAfter(after)) &&
        controller.tasks.every(
          (task) => task.status == DownloadStatus.completed,
        )) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Download did not complete with history');
}

class _Downloads {
  _Downloads(this.directory);
  final Directory directory;
  final List<DownloadQueueController> _controllers = [];
  int requests = 0;

  DownloadHistoryStore get historyStore => DownloadHistoryStore(
    fileResolver: () async => File('${directory.path}/history.json'),
  );

  DownloadQueueController controller() {
    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        requests++;
        return http.Response('video', 200, request: request);
      }),
      downloadDirectoryResolver: () async => directory,
      downloadHistoryStore: historyStore,
      downloadQueueStore: DownloadQueueStore(
        fileResolver: () async => File('${directory.path}/queue.json'),
      ),
    );
    _controllers.add(controller);
    return controller;
  }

  Future<void> seedHistory(String url, {String? identity}) async {
    final file = await File(
      '${directory.path}/existing.mp4',
    ).writeAsString('video');
    await historyStore.add(
      DownloadHistoryRecord(
        fileName: 'video.mp4',
        filePath: file.path,
        sourceUrl: url,
        completedAt: DateTime.now(),
        resourceIdentity: identity,
      ),
    );
  }

  Future<void> dispose() async {
    for (final controller in _controllers) {
      controller.dispose();
      await controller.flushQueue();
    }
    await directory.delete(recursive: true);
  }
}

const _resource = SourceResource(
  title: 'video',
  url: 'https://example.com/video.mp4',
  type: SourceResourceType.video,
  platform: SourcePlatform.other,
  host: 'example.com',
  sizeHint: '',
);

const _youtube = SourceResource(
  title: 'a different title',
  url: 'https://www.youtube.com/watch?v=video-id',
  youtubeVideoId: 'video-id',
  type: SourceResourceType.video,
  platform: SourcePlatform.youtube,
  host: 'www.youtube.com',
  sizeHint: '',
);
