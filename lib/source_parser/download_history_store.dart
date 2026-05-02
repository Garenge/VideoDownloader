import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef DownloadHistoryFileResolver = Future<File> Function();

class DownloadHistoryRecord {
  const DownloadHistoryRecord({
    required this.fileName,
    required this.filePath,
    required this.sourceUrl,
    required this.completedAt,
  });

  final String fileName;
  final String filePath;
  final String sourceUrl;
  final DateTime completedAt;

  Map<String, Object?> toJson() {
    return {
      'fileName': fileName,
      'filePath': filePath,
      'sourceUrl': sourceUrl,
      'completedAt': completedAt.toIso8601String(),
    };
  }

  static DownloadHistoryRecord? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }

    final fileName = value['fileName'];
    final filePath = value['filePath'];
    final sourceUrl = value['sourceUrl'];
    final completedAt = DateTime.tryParse(
      value['completedAt']?.toString() ?? '',
    );

    if (fileName is! String ||
        filePath is! String ||
        sourceUrl is! String ||
        completedAt == null) {
      return null;
    }

    return DownloadHistoryRecord(
      fileName: fileName,
      filePath: filePath,
      sourceUrl: sourceUrl,
      completedAt: completedAt,
    );
  }
}

class DownloadHistoryStore {
  DownloadHistoryStore({
    DownloadHistoryFileResolver? fileResolver,
    this.maxItems = 50,
  }) : _fileResolver = fileResolver ?? _defaultHistoryFile;

  final DownloadHistoryFileResolver _fileResolver;
  final int maxItems;

  Future<List<DownloadHistoryRecord>> load() async {
    final file = await _fileResolver();
    if (!file.existsSync()) {
      return [];
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return [];
      }

      return decoded
          .map(DownloadHistoryRecord.fromJson)
          .nonNulls
          .take(maxItems)
          .toList();
    } on FormatException {
      return [];
    } on FileSystemException {
      return [];
    }
  }

  Future<List<DownloadHistoryRecord>> add(DownloadHistoryRecord record) async {
    final existingRecords = await load();
    final records = [
      record,
      for (final item in existingRecords)
        if (item.filePath != record.filePath) item,
    ].take(maxItems).toList();

    await _write(records);
    return records;
  }

  Future<void> clear() async {
    await _write([]);
  }

  Future<void> _write(List<DownloadHistoryRecord> records) async {
    final file = await _fileResolver();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }

  static Future<File> _defaultHistoryFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/download_history.json');
  }
}
