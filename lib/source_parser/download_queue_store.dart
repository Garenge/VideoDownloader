import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'download_queue_controller.dart';
import 'download_task_codec.dart';

typedef DownloadQueueFileResolver = Future<File> Function();

/// Serializes snapshots and replaces the file atomically after a flushed write.
class DownloadQueueStore {
  DownloadQueueStore({DownloadQueueFileResolver? fileResolver})
    : _fileResolver = fileResolver ?? _defaultFile;

  final DownloadQueueFileResolver _fileResolver;
  Future<void> _pendingWrite = Future.value();

  Future<List<DownloadTask>> load() async {
    await _pendingWrite;
    final file = await _fileResolver();
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) throw const FormatException('Invalid download queue');
    return decoded.map(DownloadTaskCodec.decode).nonNulls.toList();
  }

  Future<void> save(List<DownloadTask> tasks) {
    final snapshot = jsonEncode(tasks.map(DownloadTaskCodec.encode).toList());
    final operation = _pendingWrite.then((_) => _write(snapshot));
    _pendingWrite = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> _write(String snapshot) async {
    final file = await _fileResolver();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(snapshot, flush: true);
    await temporary.rename(file.path);
  }

  static Future<File> _defaultFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/download_queue.json');
  }
}
