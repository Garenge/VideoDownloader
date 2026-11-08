import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';

void main() {
  test(
    'parsed X photo downloads original PNG with correct filename and bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'x_photo_download_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
      );
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://pbs.twimg.com/media/photo.png?name=orig',
        );
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final parser = SourceParserService(
        useNativeDownloads: true,
        xSessionResolver: (_) async => [
          'https://pbs.twimg.com/media/photo?format=png&name=small',
        ],
        client: client,
      );
      final controller = DownloadQueueController(
        useIoHttpClientForDirectDownloads: false,
        client: client,
        downloadDirectoryResolver: () async => directory,
        downloadHistoryStore: DownloadHistoryStore(
          fileResolver: () async => File('${directory.path}/history.json'),
        ),
      );
      addTearDown(controller.dispose);
      final result = await parser.parse('https://x.com/demo/status/123');
      final task = (await controller.enqueue(result.resources.single))!;
      await waitForDownload(controller, task);
      expect(task.status, DownloadStatus.completed, reason: task.errorMessage);
      expect(task.fileName, 'photo.png');
      expect(await File(task.filePath!).readAsBytes(), png);
    },
  );
}

Future<void> waitForDownload(
  DownloadQueueController controller,
  DownloadTask task,
) async {
  final done = Completer<void>();
  void check() {
    if ([
          DownloadStatus.completed,
          DownloadStatus.failed,
        ].contains(task.status) &&
        !done.isCompleted) {
      done.complete();
    }
  }

  controller.addListener(check);
  try {
    check();
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    controller.removeListener(check);
  }
}
