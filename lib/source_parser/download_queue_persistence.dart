import 'dart:async';

import 'package:flutter/foundation.dart';

import 'download_queue_controller.dart';
import 'download_queue_store.dart';

/// Coalesces progress updates while immediately saving structural changes.
class DownloadQueuePersistence {
  DownloadQueuePersistence(this.store, this.tasks);

  final DownloadQueueStore store;
  final List<DownloadTask> tasks;
  Timer? _timer;
  String? _lastStructure;
  bool _loaded = false;
  bool _disposed = false;

  Future<void> restore() async {
    try {
      final restored = await store.load();
      if (_disposed) return;
      final ids = tasks.map((task) => task.id).toSet();
      tasks.addAll(restored.where((task) => !ids.contains(task.id)));
    } on Object catch (error) {
      _log('restore', error);
    } finally {
      _loaded = true;
    }
  }

  void changed() {
    if (!_loaded || _disposed) return;
    final structure = tasks
        .map(
          (task) =>
              '${task.id}:${task.status}:${task.directoryPath}:${task.filePath}',
        )
        .join('|');
    if (structure != _lastStructure) {
      _lastStructure = structure;
      unawaited(flush());
    } else {
      _timer ??= Timer(const Duration(milliseconds: 500), () {
        _timer = null;
        unawaited(flush());
      });
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!_loaded) return;
    try {
      await store.save(tasks);
    } on Object catch (error) {
      _log('flush', error);
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(flush());
  }

  void _log(String method, Object error) {
    debugPrint('download_queue_persistence.dart#$method: 保存或恢复下载队列失败 $error');
  }
}
