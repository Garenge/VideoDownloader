import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_enqueue_result.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/download_queue_store.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  late _QueueFixture fixture;
  setUp(() async {
    fixture = _QueueFixture(
      await Directory.systemTemp.createTemp('queue_merge_'),
    );
  });
  tearDown(() => fixture.dispose());

  test('downloading a failed resource retries the same task and ID', () async {
    fixture.respond = (_) async => http.Response(
      fixture.requests == 1 ? 'server error' : 'video',
      fixture.requests == 1 ? 500 : 200,
    );
    final queue = fixture.controller();
    final failed = (await queue.enqueue(_resource))!;
    await _waitUntil(() => failed.status == DownloadStatus.failed);
    final originalId = failed.id;
    final result = await queue.enqueueWithResult(_resource);
    _expectReused(result, failed, originalId);
    expect(failed.errorMessage, isNull);
    await _waitUntil(() => queue.history.length == 1);
    expect(fixture.requests, 2);
    expect(queue.tasks.single, same(failed));
    expect(await File(failed.filePath!).readAsString(), 'video');
  });

  test('pending and downloading resources keep their existing tasks', () async {
    final blocked = fixture.blockFirstRequest();
    final queue = fixture.controller();
    final active = (await queue.enqueue(_resource))!;
    await _waitUntil(() => fixture.requests == 1);
    final pending = (await queue.enqueue(_otherResource))!;
    final activeResult = await queue.enqueueWithResult(_resource);
    final pendingResult = await queue.enqueueWithResult(_otherResource);
    expect(activeResult.action, DownloadEnqueueAction.existing);
    expect(pendingResult.action, DownloadEnqueueAction.existing);
    expect(activeResult.task, same(active));
    expect(pendingResult.task, same(pending));
    expect(activeResult.queued, isFalse);
    expect(pendingResult.queued, isFalse);
    expect(fixture.requests, 1);
    expect(queue.tasks, hasLength(2));
    blocked.complete(http.Response('video', 200));
    await _waitUntil(() => queue.history.length == 2);
    expect(fixture.requests, 2);
  });

  test(
    'a canceled pending resource rejoins the queue as the same task',
    () async {
      final blocked = fixture.blockFirstRequest();
      final queue = fixture.controller();
      await queue.enqueue(_resource);
      await _waitUntil(() => fixture.requests == 1);
      final canceled = (await queue.enqueue(_otherResource))!;
      queue.cancel(canceled);
      expect(canceled.status, DownloadStatus.canceled);
      final result = await queue.enqueueWithResult(_otherResource);
      _expectReused(result, canceled, canceled.id);
      expect(canceled.status, DownloadStatus.pending);
      expect(queue.tasks, hasLength(2));
      blocked.complete(http.Response('video', 200));
      await _waitUntil(() => queue.history.length == 2);
      expect(fixture.requests, 2);
    },
  );

  test('simultaneous clicks create one task and one request', () async {
    final blocked = fixture.blockFirstRequest();
    final queue = fixture.controller();
    final results = await Future.wait([
      queue.enqueueWithResult(_resource),
      queue.enqueueWithResult(_resource),
    ]);
    expect(results.map((result) => result.action), [
      DownloadEnqueueAction.created,
      DownloadEnqueueAction.existing,
    ]);
    expect(results.first.queued, isTrue);
    expect(results.first.task, same(results.last.task));
    expect(queue.tasks, hasLength(1));
    await _waitUntil(() => fixture.requests == 1);
    blocked.complete(http.Response('video', 200));
    await _waitUntil(() => queue.history.length == 1);
    expect(fixture.requests, 1);
  });

  for (final status in [DownloadStatus.failed, DownloadStatus.canceled]) {
    test('restored ${status.name} task is reused after startup', () async {
      await fixture.store.save([
        DownloadTask(id: 'original', resource: _resource, fileName: 'video.mp4')
          ..status = status,
      ]);
      final queue = fixture.controller();
      final result = await queue.enqueueWithResult(_resource);
      expect(result.action, DownloadEnqueueAction.retried);
      expect(result.task!.id, 'original');
      expect(queue.tasks, hasLength(1));
      await _waitUntil(() => queue.history.length == 1);
      expect(fixture.requests, 1);
    });
  }
}

void _expectReused(
  DownloadEnqueueResult result,
  DownloadTask original,
  String originalId,
) {
  expect(result.action, DownloadEnqueueAction.retried);
  expect(result.queued, isTrue);
  expect(result.task, same(original));
  expect(result.task!.id, originalId);
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Queue did not reach the expected state');
}

class _QueueFixture {
  _QueueFixture(this.directory);
  final Directory directory;
  DownloadQueueController? _controller;
  int requests = 0;
  Future<http.Response> Function(http.Request) respond = (_) async =>
      http.Response('video', 200);

  DownloadQueueStore get store => DownloadQueueStore(
    fileResolver: () async => File('${directory.path}/queue.json'),
  );

  DownloadQueueController controller() => _controller = DownloadQueueController(
    useIoHttpClientForDirectDownloads: false,
    client: MockClient((request) {
      requests++;
      return respond(request);
    }),
    downloadDirectoryResolver: () async => directory,
    downloadQueueStore: store,
    downloadHistoryStore: DownloadHistoryStore(
      fileResolver: () async => File('${directory.path}/history.json'),
    ),
  );

  Completer<http.Response> blockFirstRequest() {
    final blocked = Completer<http.Response>();
    respond = (_) async =>
        requests == 1 ? blocked.future : http.Response('video', 200);
    return blocked;
  }

  Future<void> dispose() async {
    _controller?.dispose();
    await _controller?.flushQueue();
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

const _otherResource = SourceResource(
  title: 'other',
  url: 'https://example.com/other.mp4',
  type: SourceResourceType.video,
  platform: SourcePlatform.other,
  host: 'example.com',
  sizeHint: '',
);
