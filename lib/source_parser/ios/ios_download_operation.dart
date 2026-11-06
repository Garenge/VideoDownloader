import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../download_queue_controller.dart';

/// 将连接等待、读取媒体流和原生处理统一纳入队列的取消语义。
class IosDownloadOperation {
  IosDownloadOperation({
    required this.task,
    required this.isCanceled,
    required this.onProgress,
  });

  final DownloadTask task;
  final bool Function() isCanceled;
  final void Function() onProgress;

  Future<T> wait<T>(Future<T> future) async {
    final canceled = Completer<T>();
    final timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (isCanceled() && !canceled.isCompleted) {
        canceled.completeError(const DownloadCanceledException());
      }
    });
    try {
      checkCanceled();
      return await Future.any([
        future.timeout(const Duration(minutes: 2)),
        canceled.future,
      ]);
    } finally {
      timer.cancel();
    }
  }

  void checkCanceled() {
    if (isCanceled()) throw const DownloadCanceledException();
  }

  Future<void> save(
    Stream<List<int>> stream,
    File file, {
    required int expectedBytes,
    int offset = 0,
    int completedBytes = 0,
  }) async {
    final iterator = StreamIterator(stream);
    final sink = file.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    task.receivedBytes = completedBytes + offset;
    onProgress();
    try {
      while (await wait(iterator.moveNext())) {
        checkCanceled();
        sink.add(iterator.current);
        task.receivedBytes += iterator.current.length;
        final total = task.totalBytes;
        if (total != null && total > 0) {
          task.progress = (task.receivedBytes / total).clamp(0, 1);
        }
        onProgress();
      }
      await sink.flush();
    } finally {
      await iterator.cancel();
      await sink.close();
    }
    final received = await file.length();
    if (received == 0 || (expectedBytes > 0 && received != expectedBytes)) {
      throw const DownloadException('媒体数据不完整，请重试下载');
    }
  }
}

class BorrowedHttpClient extends http.BaseClient {
  BorrowedHttpClient(this.client);

  final http.Client client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      client.send(request);

  @override
  void close() {}
}
