import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_settings.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test('downloads resource into queue directory', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('video bytes', 200, request: request);
      }),
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_resource);
    await _waitForStatus(task, DownloadStatus.completed, maxAttempts: 200);

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
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('download bytes', 200, request: request);
      }),
      downloadDirectoryResolver: () async => defaultDirectory,
      downloadHistoryStore: await _createHistoryStore(defaultDirectory),
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
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('open bytes', 200, request: request);
      }),
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
      folderOpener: (path) async {
        openedPath = path;
      },
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_resource);
    await _waitForStatus(task, DownloadStatus.completed);
    await controller.openDownloadedFolder(task);

    expect(openedPath, task.filePath);
  });

  test('retry reruns a failed task', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_retry_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    var attempt = 0;
    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        attempt += 1;
        if (attempt == 1) {
          return http.Response('server error', 500, request: request);
        }
        return http.Response('retry ok', 200, request: request);
      }),
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_resource);
    await _waitForStatus(task, DownloadStatus.failed);
    expect(task.errorMessage, isNotNull);

    controller.retry(task);
    await _waitForStatus(task, DownloadStatus.completed);

    expect(task.filePath, isNotNull);
    expect(await File(task.filePath!).readAsString(), 'retry ok');
    expect(controller.history, hasLength(1));
  });

  test('falls back to yt-dlp when youtube explode path fails', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_ytdlp_fallback_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('upstream failure', 500, request: request);
      }),
      processStarter: (executable, arguments) async {
        expect(executable, 'yt-dlp');
        final output = File('${tempDirectory.path}/fallback.mp4');
        await output.writeAsString('from yt-dlp');
        return _startNoopProcess();
      },
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_youtubeResource);
    await _waitForStatus(task, DownloadStatus.completed);

    expect(task.filePath, isNotNull);
    expect(task.fileName, 'fallback.mp4');
    expect(await File(task.filePath!).readAsString(), 'from yt-dlp');
    expect(controller.history, hasLength(1));
  });

  test('tracks yt-dlp fallback progress output', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_ytdlp_progress_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final progressSamples = <double>[];
    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('upstream failure', 500, request: request);
      }),
      processStarter: (executable, arguments) async {
        expect(executable, 'yt-dlp');
        expect(arguments, contains('--progress'));
        expect(arguments, contains('--newline'));
        expect(arguments, contains('--color'));
        expect(arguments, isNot(contains('--cookies-from-browser')));
        final output = File('${tempDirectory.path}/fallback-progress.mp4');
        return _startProgressProcess(output);
      },
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    controller.addListener(() {
      for (final task in controller.tasks) {
        final progress = task.progress;
        if (task.status == DownloadStatus.downloading &&
            progress > 0 &&
            progress < 1) {
          progressSamples.add(progress);
        }
      }
    });
    addTearDown(controller.dispose);

    final task = controller.enqueue(_youtubeResource);
    await _waitForStatus(task, DownloadStatus.completed);

    expect(progressSamples, isNotEmpty);
    expect(progressSamples.any((progress) => progress >= 0.5), isTrue);
    expect(await File(task.filePath!).readAsString(), 'from yt-dlp');
  });

  test('does not invoke yt-dlp when fallback is disabled', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_ytdlp_disabled_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    var called = false;
    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('upstream failure', 500, request: request);
      }),
      processRunner: (executable, arguments) async {
        called = true;
        return ProcessResult(0, 0, 'ok', '');
      },
      downloadSettings: const DownloadSettings(
        enableYtDlpFallback: false,
        ytDlpConcurrency: 8,
        ytDlpRetries: 10,
        ytDlpFragmentRetries: 50,
      ),
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_youtubeResource);
    await _waitForStatus(task, DownloadStatus.failed, maxAttempts: 200);

    expect(called, isFalse);
    expect(task.errorMessage, isNotNull);
  });

  test('youtube engine does not close shared http client', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_client_lifecycle_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final spyClient = _SpyHttpClient();
    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: spyClient,
      ownClient: false,
      downloadSettings: const DownloadSettings(
        enableYtDlpFallback: false,
        ytDlpConcurrency: 8,
        ytDlpRetries: 10,
        ytDlpFragmentRetries: 50,
      ),
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_youtubeResource);
    await _waitForStatus(task, DownloadStatus.failed, maxAttempts: 200);

    expect(spyClient.closed, isFalse);
  });

  test('records and clears completed download history', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_history_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final historyStore = DownloadHistoryStore(
      fileResolver: () async => File('${tempDirectory.path}/history.json'),
    );
    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('history bytes', 200, request: request);
      }),
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: historyStore,
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_resource);
    await _waitForStatus(task, DownloadStatus.completed);

    expect(controller.history, hasLength(1));
    expect(controller.history.single.fileName, 'sample.mp4');
    expect(controller.history.single.filePath, task.filePath);
    expect(await historyStore.load(), hasLength(1));

    await controller.clearHistory();

    expect(controller.history, isEmpty);
    expect(await historyStore.load(), isEmpty);
  });
}

Future<void> _waitForStatus(
  DownloadTask task,
  DownloadStatus status, {
  int maxAttempts = 30,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
    if (task.status == status) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  fail('waitForStatus: expected $status, got ${task.status}');
}

Future<DownloadHistoryStore> _createHistoryStore(Directory directory) async {
  return DownloadHistoryStore(
    fileResolver: () async => File('${directory.path}/history.json'),
  );
}

Future<Process> _startNoopProcess() {
  if (Platform.isWindows) {
    return Process.start('cmd', ['/c', 'exit', '0']);
  }
  return Process.start('sh', ['-c', 'exit 0']);
}

Future<Process> _startProgressProcess(File output) {
  if (Platform.isWindows) {
    return Process.start('cmd', [
      '/c',
      [
        'echo [download] 10.0% of 4.00MiB at 1.00MiB/s ETA 00:03',
        'echo [download] 55.0% of 4.00MiB at 1.00MiB/s ETA 00:02',
        'echo from yt-dlp> "${output.path}"',
        'echo after_move:${output.path}',
      ].join(' & '),
    ]);
  }

  final escapedPath = output.path.replaceAll("'", "'\\''");
  return Process.start('sh', [
    '-c',
    [
      "echo '[download] 10.0% of 4.00MiB at 1.00MiB/s ETA 00:03'",
      "echo '[download] 55.0% of 4.00MiB at 1.00MiB/s ETA 00:02'",
      "printf 'from yt-dlp' > '$escapedPath'",
      "echo 'after_move:$escapedPath'",
    ].join('; '),
  ]);
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

const _youtubeResource = SourceResource(
  title: 'YouTube Video',
  url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  type: SourceResourceType.video,
  platform: SourcePlatform.youtube,
  host: 'www.youtube.com',
  sizeHint: 'youtube_explode',
  youtubeVideoId: 'invalid_video_id',
);

class _SpyHttpClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('send should not be called in this test');
  }

  @override
  void close() {
    closed = true;
  }
}
