import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/download_queue_store.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test(
    'native HTTP resumes actual partial bytes after controller recreation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'native-relaunch-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        final response = request.response;
        response.bufferOutput = false;
        response.headers.set(HttpHeaders.etagHeader, '"video-v1"');
        if (++requests == 1) {
          response.contentLength = 6;
          response.add('abc'.codeUnits);
          await response.flush();
        } else {
          expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=3-');
          expect(
            request.headers.value(HttpHeaders.ifRangeHeader),
            '"video-v1"',
          );
          response.statusCode = 206;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 3-5/6');
          response.contentLength = 3;
          response.add('def'.codeUnits);
          await response.close();
        }
      });
      final store = DownloadQueueStore(
        fileResolver: () async => File('${directory.path}/queue.json'),
      );
      DownloadQueueController controller() => DownloadQueueController(
        downloadQueueStore: store,
        downloadDirectoryResolver: () async => directory,
        downloadHistoryStore: DownloadHistoryStore(
          fileResolver: () async => File('${directory.path}/history.json'),
        ),
      );
      final first = controller();
      final task = first.enqueue(
        SourceResource(
          title: 'video',
          url: 'http://127.0.0.1:${server.port}/video.mp4',
          type: SourceResourceType.video,
          platform: SourcePlatform.other,
          host: '127.0.0.1',
          sizeHint: '',
        ),
      );
      await _waitFor(
        () async {
          final path = task.filePath;
          if (path == null || task.receivedBytes != 3) return false;
          final partial = File('$path.part');
          return await partial.exists() && await partial.length() == 3;
        },
        details: () =>
            'requests=$requests received=${task.receivedBytes} ${task.logText}',
      );
      first.dispose();
      await first.flushQueue();
      final second = controller();
      addTearDown(() async {
        second.dispose();
        await second.flushQueue();
      });
      await second.ready;
      await _waitFor(() async => second.history.isNotEmpty);
      final recovered = second.tasks.single;
      expect(recovered.id, task.id);
      expect(recovered.status, DownloadStatus.completed);
      expect(await File(recovered.filePath!).readAsString(), 'abcdef');
      expect(requests, 2);
    },
  );
}

Future<void> _waitFor(
  Future<bool> Function() condition, {
  String Function()? details,
}) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Native transfer did not reach the expected state: ${details?.call()}');
}
