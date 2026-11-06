import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/ios/ios_download_operation.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  late Directory directory;
  late DownloadTask task;
  late bool canceled;
  late IosDownloadOperation operation;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ios-download-test-');
    task = DownloadTask(
      id: 'test',
      fileName: 'video.mp4',
      resource: const SourceResource(
        title: 'video',
        url: 'https://example.com/video.mp4',
        type: SourceResourceType.video,
        platform: SourcePlatform.other,
        host: 'example.com',
        sizeHint: '',
      ),
    );
    canceled = false;
    operation = IosDownloadOperation(
      task: task,
      isCanceled: () => canceled,
      onProgress: () {},
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('saves all chunks and counts bytes', () async {
    final file = File('${directory.path}/video.mp4');
    await operation.save(
      Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]),
      file,
      expectedBytes: 4,
    );
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(task.receivedBytes, 4);
  });

  test('rejects truncated and empty successful responses', () async {
    final file = File('${directory.path}/video.mp4');
    await expectLater(
      operation.save(Stream.value([1]), file, expectedBytes: 20),
      throwsA(isA<DownloadException>()),
    );
    await expectLater(
      operation.save(const Stream.empty(), file, expectedBytes: 0),
      throwsA(isA<DownloadException>()),
    );
  });

  test(
    'appends resumed media and includes previously completed audio or video',
    () async {
      final file = File('${directory.path}/video.mp4');
      await file.writeAsBytes([1, 2]);
      task.totalBytes = 14;
      await operation.save(
        Stream.value([3, 4]),
        file,
        expectedBytes: 4,
        offset: 2,
        completedBytes: 10,
      );
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
      expect(task.receivedBytes, 14);
      expect(task.progress, 1);
    },
  );

  test('cancels an idle stream without waiting for the next chunk', () async {
    var subscriptionCanceled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        subscriptionCanceled = true;
      },
    );
    final future = operation.save(
      stream.stream,
      File('${directory.path}/video.mp4'),
      expectedBytes: 5,
    );
    final expectation = expectLater(
      future,
      throwsA(isA<DownloadCanceledException>()),
    );
    canceled = true;
    await expectation.timeout(const Duration(seconds: 2));
    expect(subscriptionCanceled, isTrue);
    await stream.close();
  });
}
