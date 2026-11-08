import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'download_resource_identity.dart';

typedef DownloadHistoryFileResolver = Future<File> Function();

class DownloadHistoryRecord {
  const DownloadHistoryRecord({
    required this.fileName,
    required this.filePath,
    required this.sourceUrl,
    required this.completedAt,
    this.resourceIdentity,
  });

  final String fileName;
  final String filePath;
  final String sourceUrl;
  final DateTime completedAt;
  final String? resourceIdentity;

  String get downloadIdentity =>
      resourceIdentity ?? downloadResourceIdentity(sourceUrl);

  String get fileExtension {
    final path = filePath.toLowerCase();
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == path.length - 1) {
      return '';
    }
    return path.substring(dotIndex + 1);
  }

  bool get isM3u8 => fileExtension == 'm3u8';

  Map<String, Object?> toJson() {
    return {
      'fileName': fileName,
      'filePath': filePath,
      'sourceUrl': sourceUrl,
      'completedAt': completedAt.toIso8601String(),
      if (resourceIdentity != null) 'resourceIdentity': resourceIdentity,
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
      resourceIdentity: value['resourceIdentity'] is String
          ? value['resourceIdentity'] as String
          : null,
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
  Future<void> _pendingWrite = Future<void>.value();

  Future<List<DownloadHistoryRecord>> load() async {
    await _pendingWrite;
    return _read();
  }

  Future<List<DownloadHistoryRecord>> _read() async {
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

  Future<List<DownloadHistoryRecord>> add(DownloadHistoryRecord record) =>
      _update(
        (existingRecords) => [
          record,
          for (final item in existingRecords)
            if (item.filePath != record.filePath) item,
        ].take(maxItems).toList(),
      );

  Future<List<DownloadHistoryRecord>> remove(String path) => _update(
    (records) => records.where((item) => item.filePath != path).toList(),
  );

  Future<void> clear() async {
    await _update((_) => []);
  }

  Future<List<DownloadHistoryRecord>> _update(
    List<DownloadHistoryRecord> Function(List<DownloadHistoryRecord>) change,
  ) {
    final operation = _pendingWrite.then((_) async {
      final records = change(await _read());
      await _write(records);
      return records;
    });
    _pendingWrite = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
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
