import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'downloaded_file_store.dart';
import 'ios/ios_media_bridge.dart';

class DownloadedFileActions {
  static Future<void> open(DownloadedFile file) async {
    if (!await File(file.path).exists()) {
      throw const FileSystemException('文件已被移动或删除');
    }
    if (Platform.isIOS) {
      await const IosMediaBridge().previewFile(file.path);
    } else if (Platform.isMacOS) {
      final result = await Process.run('/usr/bin/open', [file.path]);
      if (result.exitCode != 0) throw const FileSystemException('无法打开文件');
    } else if (!await launchUrl(Uri.file(file.path))) {
      throw const FileSystemException('当前设备无法打开此文件');
    }
  }

  static Future<void> share(DownloadedFile file) async {
    if (Platform.isIOS) {
      await const IosMediaBridge().exportFile(file.path);
    } else {
      await open(file);
    }
  }

  static Future<bool> confirmDelete(
    BuildContext context,
    DownloadedFile file,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除文件？'),
          content: Text('将删除“${file.name}”及对应的下载记录，此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}
