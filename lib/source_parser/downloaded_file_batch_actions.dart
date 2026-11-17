import 'package:flutter/material.dart';

import 'download_queue_controller.dart';
import 'downloaded_file_actions.dart';
import 'downloaded_file_store.dart';
import 'downloaded_files_selection.dart';
import 'ios/ios_media_bridge.dart';

class DownloadedFileBatchActions {
  static Future<void> delete({
    required BuildContext context,
    required List<DownloadedFile> files,
    required DownloadedFilesSelection selection,
    required DownloadedFileStore store,
    required DownloadQueueController queue,
    required Future<void> Function() refresh,
  }) async {
    if (files.isEmpty || selection.busy) return;
    selection.setBusy(true);
    try {
      if (!await DownloadedFileActions.confirmDeleteMany(
        context,
        files.length,
      )) {
        return;
      }
      if (!context.mounted) return;
      final failed = await _deleteFiles(files, store, queue);
      if (!context.mounted) return;
      selection.retain(failed);
      await refresh();
      if (!context.mounted) return;
      _reportDeleted(context, files.length, failed.length);
    } finally {
      selection.setBusy(false);
    }
  }

  static void _reportDeleted(BuildContext context, int total, int failed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已删除 ${total - failed} 项，失败 $failed 项'
          '${failed == 0 ? '' : '，请重试所选文件'}',
        ),
      ),
    );
  }

  static Future<List<DownloadedFile>> _deleteFiles(
    List<DownloadedFile> files,
    DownloadedFileStore store,
    DownloadQueueController queue,
  ) async {
    final failed = <DownloadedFile>[];
    for (final file in files) {
      try {
        await store.delete(file);
        await queue.removeFileRecords(file.path);
      } on Object catch (error) {
        debugPrint(
          'downloaded_file_batch_actions.dart#_deleteFiles: '
          '删除失败 path=${file.path} error=$error',
        );
        failed.add(file);
      }
    }
    return failed;
  }

  static Future<void> share(
    List<DownloadedFile> files,
    DownloadedFilesSelection selection,
  ) async {
    if (files.isEmpty || selection.busy) return;
    selection.setBusy(true);
    try {
      await const IosMediaBridge().exportFiles(
        files.map((file) => file.path).toList(),
      );
    } finally {
      selection.setBusy(false);
    }
  }
}
