import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/media_conversion_controller.dart';

void main() {
  test('converts m3u8 history record to mp4 and records history', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_conversion_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final inputFile = File('${tempDirectory.path}/sample.m3u8');
    await inputFile.writeAsString('#EXTM3U\n#EXT-X-VERSION:3\n');

    final historyRecords = <DownloadHistoryRecord>[];
    final controller = MediaConversionController(
      historyRecorder: (record) async {
        historyRecords.add(record);
      },
      processStarter: (executable, arguments) async {
        expect(executable, 'ffmpeg');
        expect(arguments, contains(inputFile.path));
        expect(arguments, contains('-progress'));
        expect(arguments, contains('pipe:1'));
        final outputPath = arguments.last;
        return _startProgressProcess(File(outputPath));
      },
    );
    addTearDown(controller.dispose);

    final task = controller.enqueueM3u8ToMp4(
      DownloadHistoryRecord(
        fileName: 'sample.m3u8',
        filePath: inputFile.path,
        sourceUrl: 'https://example.com/sample.m3u8',
        completedAt: DateTime(2026, 5, 6, 10, 0),
      ),
    );

    await _waitForStatus(task, MediaConversionStatus.completed);

    expect(task.outputFilePath, isNotNull);
    expect(await File(task.outputFilePath!).readAsString(), 'converted mp4');
    expect(task.progress, 1);
    expect(historyRecords, hasLength(1));
    expect(historyRecords.single.fileName, 'sample.mp4');
    expect(historyRecords.single.filePath, task.outputFilePath);
  });

  test('retry reruns a failed conversion task', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'videodownloader_conversion_retry_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final inputFile = File('${tempDirectory.path}/retry.m3u8');
    await inputFile.writeAsString('#EXTM3U\n');

    var attempt = 0;
    final controller = MediaConversionController(
      historyRecorder: (_) async {},
      processStarter: (executable, arguments) async {
        attempt += 1;
        if (attempt == 1) {
          throw ProcessException(executable, arguments, 'ffmpeg failed');
        }
        return _startProgressProcess(File(arguments.last));
      },
    );
    addTearDown(controller.dispose);

    final task = controller.enqueueM3u8ToMp4(
      DownloadHistoryRecord(
        fileName: 'retry.m3u8',
        filePath: inputFile.path,
        sourceUrl: 'https://example.com/retry.m3u8',
        completedAt: DateTime(2026, 5, 6, 10, 0),
      ),
    );

    await _waitForStatus(task, MediaConversionStatus.failed);
    expect(task.errorMessage, isNotNull);

    controller.retry(task);
    await _waitForStatus(task, MediaConversionStatus.completed);

    expect(task.outputFilePath, isNotNull);
    expect(await File(task.outputFilePath!).readAsString(), 'converted mp4');
  });
}

Future<void> _waitForStatus(
  MediaConversionTask task,
  MediaConversionStatus status, {
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

Future<Process> _startProgressProcess(File output) {
  if (Platform.isWindows) {
    return Process.start('cmd', [
      '/c',
      [
        'echo ffmpeg version n6.1',
        'echo   Duration: 00:00:04.00, start: 0.000000, bitrate: 0 kb/s 1^>^&2',
        'echo out_time_us=1000000',
        'echo progress=continue',
        'echo out_time_us=4000000',
        'echo progress=end',
        'echo converted mp4> "${output.path}"',
      ].join(' & '),
    ]);
  }

  final escapedPath = output.path.replaceAll("'", "'\\''");
  return Process.start('sh', [
    '-c',
    [
      "echo 'ffmpeg version n6.1' 1>&2",
      "echo '  Duration: 00:00:04.00, start: 0.000000, bitrate: 0 kb/s' 1>&2",
      "echo 'out_time_us=1000000'",
      "echo 'progress=continue'",
      "echo 'out_time_us=4000000'",
      "echo 'progress=end'",
      "printf 'converted mp4' > '$escapedPath'",
    ].join('; '),
  ]);
}
