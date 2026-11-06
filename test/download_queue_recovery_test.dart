import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/download_queue_store.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

const resource = SourceResource(
  title: 'video',
  url: 'https://example.com/video.mp4',
  type: SourceResourceType.video,
  platform: SourcePlatform.other,
  host: 'example.com',
  sizeHint: '',
);

void main() {
  late Directory directory;
  late DownloadQueueStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('queue-recovery-');
    store = DownloadQueueStore(
      fileResolver: () async => File('${directory.path}/queue.json'),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'atomic snapshots restore resource, destination and all task states',
    () async {
      final tasks = DownloadStatus.values
          .map(
            (status) =>
                DownloadTask(
                    id: status.name,
                    resource: resource,
                    fileName: 'video.mp4',
                  )
                  ..status = status
                  ..directoryPath = directory.path
                  ..receivedBytes = 3
                  ..totalBytes = 6
                  ..progress = 0.5,
          )
          .toList();
      await store.save(tasks);
      final restored = await store.load();
      expect(restored, hasLength(tasks.length));
      expect(restored.map((task) => task.status), [
        DownloadStatus.pending,
        DownloadStatus.pending,
        DownloadStatus.completed,
        DownloadStatus.failed,
        DownloadStatus.canceled,
      ]);
      expect(restored.every((task) => task.progress == 0.5), isTrue);
      expect(restored.first.resource.url, resource.url);
      expect(restored.first.directoryPath, directory.path);
      expect(await File('${directory.path}/queue.json.tmp').exists(), isFalse);
    },
  );

  test(
    'relaunch restores and resumes using actual bytes, not stale saved progress',
    () async {
      final output = File('${directory.path}/video.mp4');
      await File('${output.path}.part').writeAsString('abc');
      await store.save([
        DownloadTask(id: 'old', resource: resource, fileName: 'video.mp4')
          ..status = DownloadStatus.downloading
          ..filePath = output.path
          ..directoryPath = directory.path
          ..receivedBytes = 5
          ..totalBytes = 6
          ..progress = 0.8,
      ]);
      final controller = DownloadQueueController(
        downloadQueueStore: store,
        downloadDirectoryResolver: () async =>
            throw StateError('must use saved directory'),
        downloadHistoryStore: DownloadHistoryStore(
          fileResolver: () async => File('${directory.path}/history.json'),
        ),
        useIoHttpClientForDirectDownloads: false,
        client: MockClient((request) async {
          expect(request.headers['Range'], 'bytes=3-');
          return http.Response(
            'def',
            206,
            headers: {'content-range': 'bytes 3-5/6'},
          );
        }),
      );
      await controller.ready;
      await waitForCompletion(controller);
      await controller.flushQueue();
      expect(controller.tasks.single.id, 'old');
      expect(controller.tasks.single.progress, 1);
      expect(await output.readAsString(), 'abcdef');
      expect(await File('${output.path}.part').exists(), isFalse);
      expect((await store.load()).single.status, DownloadStatus.completed);
      controller.dispose();
      await controller.flushQueue();
    },
  );

  test(
    'newly enqueued tasks survive queue initialization and are persisted',
    () async {
      final controller = DownloadQueueController(
        downloadQueueStore: store,
        downloadDirectoryResolver: () async => directory,
        downloadHistoryStore: DownloadHistoryStore(
          fileResolver: () async => File('${directory.path}/history.json'),
        ),
        useIoHttpClientForDirectDownloads: false,
        client: MockClient((_) async => http.Response('video', 200)),
      );
      controller.enqueue(resource);
      await controller.ready;
      await waitForCompletion(controller);
      await controller.flushQueue();
      expect((await store.load()).single.status, DownloadStatus.completed);
      controller.dispose();
      await controller.flushQueue();
    },
  );
}

Future<void> waitForCompletion(DownloadQueueController controller) async {
  for (var i = 0; i < 200; i++) {
    if (controller.tasks.isNotEmpty &&
        controller.tasks.every(
          (task) => task.status == DownloadStatus.completed,
        ) &&
        controller.history.isNotEmpty)
      return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Recovered queue did not complete: ${controller.tasks.map((task) => task.errorMessage)}',
  );
}
