import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'source_resource.dart';

typedef DownloadDirectoryResolver = Future<Directory> Function();

enum DownloadStatus {
  pending('等待中'),
  downloading('下载中'),
  completed('已完成'),
  failed('失败'),
  canceled('已取消');

  const DownloadStatus(this.displayName);

  final String displayName;
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.resource,
    required this.fileName,
  });

  final String id;
  final SourceResource resource;
  final String fileName;

  DownloadStatus status = DownloadStatus.pending;
  double progress = 0;
  int receivedBytes = 0;
  int? totalBytes;
  String? filePath;
  String? errorMessage;

  String get progressLabel {
    final total = totalBytes;
    if (status == DownloadStatus.completed) {
      return '100%';
    }

    if (total == null || total == 0) {
      return _formatBytes(receivedBytes);
    }

    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return '$percent% · ${_formatBytes(receivedBytes)} / ${_formatBytes(total)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }

    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class DownloadQueueController extends ChangeNotifier {
  DownloadQueueController({
    http.Client? client,
    DownloadDirectoryResolver? downloadDirectoryResolver,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _downloadDirectoryResolver =
           downloadDirectoryResolver ?? _defaultDownloadDirectory;

  final http.Client _client;
  final bool _ownsClient;
  final DownloadDirectoryResolver _downloadDirectoryResolver;
  final List<DownloadTask> _tasks = [];
  final Set<String> _cancelRequestedTaskIds = {};

  bool _isRunning = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get hasTasks => _tasks.isNotEmpty;

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  DownloadTask enqueue(SourceResource resource) {
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      resource: resource,
      fileName: _fileNameFor(resource),
    );

    _tasks.insert(0, task);
    notifyListeners();
    unawaited(_runNext());
    return task;
  }

  void cancel(DownloadTask task) {
    if (task.status == DownloadStatus.pending) {
      task.status = DownloadStatus.canceled;
      notifyListeners();
      return;
    }

    if (task.status == DownloadStatus.downloading) {
      _cancelRequestedTaskIds.add(task.id);
    }
  }

  Future<void> _runNext() async {
    if (_isRunning) {
      return;
    }

    final task = _tasks.reversed
        .where((item) => item.status == DownloadStatus.pending)
        .firstOrNull;
    if (task == null) {
      return;
    }

    _isRunning = true;
    await _download(task);
    _isRunning = false;
    unawaited(_runNext());
  }

  Future<void> _download(DownloadTask task) async {
    File? outputFile;
    try {
      task.status = DownloadStatus.downloading;
      task.errorMessage = null;
      notifyListeners();

      final directory = await _downloadDirectoryResolver();
      await directory.create(recursive: true);
      outputFile = await _uniqueFile(directory, task.fileName);

      final request = http.Request('GET', Uri.parse(task.resource.url));
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw DownloadException('HTTP ${response.statusCode}');
      }

      task.totalBytes = response.contentLength;
      task.filePath = outputFile.path;

      final sink = outputFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          if (_cancelRequestedTaskIds.remove(task.id)) {
            throw const DownloadCanceledException();
          }

          task.receivedBytes += chunk.length;
          final totalBytes = task.totalBytes;
          if (totalBytes != null && totalBytes > 0) {
            task.progress = task.receivedBytes / totalBytes;
          }

          sink.add(chunk);
          notifyListeners();
        }
      } finally {
        await sink.close();
      }

      task.progress = 1;
      task.status = DownloadStatus.completed;
      notifyListeners();
    } on DownloadCanceledException {
      task.status = DownloadStatus.canceled;
      task.errorMessage = null;
      await outputFile?.deleteIfExists();
      notifyListeners();
    } on Object catch (error) {
      task.status = DownloadStatus.failed;
      task.errorMessage =
          'lib/source_parser/download_queue_controller.dart#_download: $error';
      await outputFile?.deleteIfExists();
      notifyListeners();
    }
  }

  static Future<Directory> _defaultDownloadDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return Directory('${documentsDirectory.path}/VideoDownloader');
  }

  static Future<File> _uniqueFile(Directory directory, String fileName) async {
    final parts = _splitFileName(fileName);
    var index = 1;
    var file = File('${directory.path}/$fileName');

    while (await file.exists()) {
      index += 1;
      file = File('${directory.path}/${parts.name}-$index${parts.extension}');
    }

    return file;
  }

  static _FileNameParts _splitFileName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
      return _FileNameParts(fileName, '');
    }

    return _FileNameParts(
      fileName.substring(0, dotIndex),
      fileName.substring(dotIndex),
    );
  }

  static String _fileNameFor(SourceResource resource) {
    final uri = Uri.tryParse(resource.url);
    final rawName = uri?.pathSegments
        .where((part) => part.isNotEmpty)
        .lastOrNull;
    final baseName = rawName == null || rawName.trim().isEmpty
        ? resource.title
        : rawName;
    final sanitizedName = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');

    if (sanitizedName.contains('.')) {
      return sanitizedName;
    }

    return '$sanitizedName.${_fallbackExtension(resource.type)}';
  }

  static String _fallbackExtension(SourceResourceType type) {
    return switch (type) {
      SourceResourceType.video => 'mp4',
      SourceResourceType.image => 'jpg',
      SourceResourceType.other => 'bin',
    };
  }
}

class _FileNameParts {
  const _FileNameParts(this.name, this.extension);

  final String name;
  final String extension;
}

class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

class DownloadCanceledException implements Exception {
  const DownloadCanceledException();
}

extension on File {
  Future<void> deleteIfExists() async {
    if (await exists()) {
      await delete();
    }
  }
}
