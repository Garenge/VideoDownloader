import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_settings.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test(
    'removing active and pending tasks cancels them and advances remaining queue',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'queue_cancel_remove_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final blocked = Completer<http.Response>();
      final controller = DownloadQueueController(
        useIoHttpClientForDirectDownloads: false,
        client: MockClient(
          (request) async => request.url == Uri.parse(_resource.url)
              ? blocked.future
              : http.Response('video', 200, request: request),
        ),
        downloadDirectoryResolver: () async => directory,
        downloadHistoryStore: await _createHistoryStore(directory),
      );
      addTearDown(controller.dispose);
      final active = controller.enqueue(_resource);
      await _waitForStatus(active, DownloadStatus.downloading);
      final pending = controller.enqueue(_secondResource);
      controller.clearFinishedTasks();
      expect(controller.tasks, hasLength(2));
      controller.removeTask(pending);
      controller.removeTask(active);
      blocked.complete(http.Response('canceled', 200));
      await _waitForStatus(active, DownloadStatus.canceled);
      expect(controller.tasks, isEmpty);
      expect(pending.status, DownloadStatus.canceled);
      final next = controller.enqueue(_secondResource);
      await _waitForStatus(next, DownloadStatus.completed);
      expect(await File(next.filePath!).readAsString(), 'video');
      controller.clearFinishedTasks();
      expect(controller.tasks, isEmpty);
    },
  );

  test(
    'removing completed queue entries keeps files and history until file deletion',
    () async {
      final directory = await Directory.systemTemp.createTemp('queue_removal_');
      addTearDown(() => directory.delete(recursive: true));
      final controller = DownloadQueueController(
        useIoHttpClientForDirectDownloads: false,
        client: MockClient(
          (request) async => http.Response('video', 200, request: request),
        ),
        downloadDirectoryResolver: () async => directory,
        downloadHistoryStore: await _createHistoryStore(directory),
      );
      addTearDown(controller.dispose);
      final task = controller.enqueue(_resource);
      await _waitForStatus(task, DownloadStatus.completed);
      for (var i = 0; controller.history.isEmpty && i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      controller.removeTask(task);
      expect(controller.tasks, isEmpty);
      expect(await File(task.filePath!).exists(), isTrue);
      expect(controller.history, hasLength(1));
      expect(controller.activeFilePaths, isEmpty);
      await controller.removeFileRecords(task.filePath!);
      expect(controller.history, isEmpty);
    },
  );

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

  test('opens history item containing folder', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_history_open_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final file = File('${tempDirectory.path}/nested/sample.mp4');
    await file.parent.create(recursive: true);
    await file.writeAsString('history bytes');

    String? openedPath;
    final controller = DownloadQueueController(
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
      folderOpener: (path) async {
        openedPath = path;
      },
    );
    addTearDown(controller.dispose);

    await controller.openHistoryFolder(
      DownloadHistoryRecord(
        fileName: 'sample.mp4',
        filePath: file.path,
        sourceUrl: _resource.url,
        completedAt: DateTime.now(),
      ),
    );

    expect(openedPath, file.path);
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

  test('fails when downloaded file is empty', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_empty_http_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('', 200, request: request);
      }),
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_resource);
    await _waitForStatus(task, DownloadStatus.failed);

    expect(task.errorMessage, contains('下载结果为空文件，已判定为失败'));
    expect(controller.history, isEmpty);
    expect(task.filePath, isNotNull);
    expect(await File(task.filePath!).exists(), isFalse);
  });

  test('downloads youtube via yt-dlp isolated workspace', () async {
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
        final output = File(_ytDlpOutputPath(arguments));
        await output.parent.create(recursive: true);
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
    expect(task.fileName, 'invalid_video_id.mp4');
    expect(await File(task.filePath!).readAsString(), 'from yt-dlp');
    expect(controller.history, hasLength(1));
  });

  test('fails when yt-dlp output file is empty', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_empty_ytdlp_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: MockClient((request) async {
        return http.Response('upstream failure', 500, request: request);
      }),
      processStarter: (executable, arguments) async {
        expect(executable, 'yt-dlp');
        final output = File(_ytDlpOutputPath(arguments));
        await output.parent.create(recursive: true);
        await output.writeAsString('');
        return _startNoopProcess();
      },
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_youtubeResource);
    await _waitForStatus(task, DownloadStatus.failed);

    expect(task.errorMessage, contains('下载结果为空文件，已判定为失败'));
    expect(controller.history, isEmpty);
    expect(task.filePath, isNotNull);
    expect(await File(task.filePath!).exists(), isFalse);
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
        final output = File(_ytDlpOutputPath(arguments));
        await output.parent.create(recursive: true);
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
        preferYtDlpForYouTube: false,
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
        preferYtDlpForYouTube: false,
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

  test('prefers yt-dlp for youtube downloads when enabled', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_ytdlp_preferred_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    var ytDlpCalled = false;
    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: _SpyHttpClient(),
      processStarter: (executable, arguments) async {
        ytDlpCalled = true;
        expect(executable, 'yt-dlp');
        final output = File(_ytDlpOutputPath(arguments));
        await output.parent.create(recursive: true);
        await output.writeAsString('preferred yt-dlp');
        return _startNoopProcess();
      },
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_youtubeResource);
    await _waitForStatus(task, DownloadStatus.completed);

    expect(ytDlpCalled, isTrue);
    expect(task.fileName, 'invalid_video_id.mp4');
    expect(await File(task.filePath!).readAsString(), 'preferred yt-dlp');
  });

  test('isolates yt-dlp output from existing download files', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_ytdlp_isolated_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final existingFile = File('${tempDirectory.path}/invalid_video_id.mp4');
    await existingFile.writeAsString('old bytes');

    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: _SpyHttpClient(),
      processStarter: (executable, arguments) async {
        expect(executable, 'yt-dlp');
        final output = File(_ytDlpOutputPath(arguments));
        await output.parent.create(recursive: true);
        await output.writeAsString('new bytes from yt-dlp');
        return _startNoopProcess();
      },
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_youtubeResource);
    await _waitForStatus(task, DownloadStatus.completed);

    expect(task.filePath, isNot(existingFile.path));
    expect(task.fileName, 'invalid_video_id-2.mp4');
    expect(await existingFile.readAsString(), 'old bytes');
    expect(await File(task.filePath!).readAsString(), 'new bytes from yt-dlp');
  });

  test('downloads x resource via yt-dlp isolated workspace', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_x_ytdlp_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: _SpyHttpClient(),
      processStarter: (executable, arguments) async {
        expect(executable, 'yt-dlp');
        final output = File(_ytDlpOutputPath(arguments));
        await output.parent.create(recursive: true);
        await output.writeAsString('x bytes from yt-dlp');
        return _startNoopProcess();
      },
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_xResource);
    await _waitForStatus(task, DownloadStatus.completed);

    expect(task.filePath, isNotNull);
    expect(task.fileName, 'openai_1234567890123456789.mp4');
    expect(await File(task.filePath!).readAsString(), 'x bytes from yt-dlp');
    expect(controller.history, hasLength(1));
  });

  test(
    'prefers browser cookies for x downloads before anonymous mode',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'videodownloader_x_cookies_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final attemptedArgs = <List<String>>[];
      final controller = DownloadQueueController(
        useIoHttpClientForDirectDownloads: false,
        client: _SpyHttpClient(),
        processStarter: (executable, arguments) async {
          expect(executable, 'yt-dlp');
          attemptedArgs.add(List<String>.from(arguments));
          if (arguments.contains('--cookies-from-browser')) {
            final output = File(_ytDlpOutputPath(arguments));
            await output.parent.create(recursive: true);
            await output.writeAsString('x bytes from browser cookies');
            return _startNoopProcess();
          }
          return _startFailingProcess(
            'anonymous fallback should not run first',
          );
        },
        downloadDirectoryResolver: () async => tempDirectory,
        downloadHistoryStore: await _createHistoryStore(tempDirectory),
      );
      addTearDown(controller.dispose);

      final task = controller.enqueue(_xResource);
      await _waitForStatus(task, DownloadStatus.completed);

      expect(attemptedArgs, isNotEmpty);
      expect(
        attemptedArgs.first,
        containsAll(['--cookies-from-browser', 'chrome']),
      );
      expect(
        await File(task.filePath!).readAsString(),
        'x bytes from browser cookies',
      );
    },
  );

  test('maps x no-video yt-dlp error to readable message', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_x_no_video_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final controller = DownloadQueueController(
      useIoHttpClientForDirectDownloads: false,
      client: _SpyHttpClient(),
      processStarter: (executable, arguments) async {
        expect(executable, 'yt-dlp');
        return _startFailingProcess(
          'ERROR: [twitter] 2053349572873990526: No video could be found in this tweet',
        );
      },
      downloadDirectoryResolver: () async => tempDirectory,
      downloadHistoryStore: await _createHistoryStore(tempDirectory),
    );
    addTearDown(controller.dispose);

    final task = controller.enqueue(_xResource);
    await _waitForStatus(task, DownloadStatus.failed);

    expect(task.errorMessage, contains('没有检测到可下载的视频媒体'));
    expect(task.errorMessage, contains('可能是图片推文、纯文本推文'));
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

Future<Process> _startFailingProcess(String stderrLine) {
  if (Platform.isWindows) {
    return Process.start('cmd', ['/c', 'echo $stderrLine 1>&2 & exit 1']);
  }

  final escapedLine = stderrLine.replaceAll("'", "'\\''");
  return Process.start('sh', ['-c', "echo '$escapedLine' 1>&2; exit 1"]);
}

String _ytDlpOutputPath(List<String> arguments, {String extension = 'mp4'}) {
  final outputIndex = arguments.indexOf('-o');
  expect(outputIndex, isNot(-1));
  final template = arguments[outputIndex + 1];
  return template.replaceAll('%(ext)s', extension);
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

const _xResource = SourceResource(
  title: 'X 视频：@openai/1234567890123456789',
  url: 'https://x.com/openai/status/1234567890123456789',
  type: SourceResourceType.video,
  platform: SourcePlatform.x,
  host: 'x.com',
  sizeHint: 'X 下载任务 · 使用 yt-dlp 加入下载队列',
  requiresYtDlp: true,
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
