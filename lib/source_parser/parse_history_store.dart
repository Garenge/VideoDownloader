import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef ParseHistoryFileResolver = Future<File> Function();

class ParseHistoryStore {
  ParseHistoryStore({
    ParseHistoryFileResolver? fileResolver,
    this.maxItems = 10,
  }) : _fileResolver = fileResolver ?? _defaultHistoryFile;

  final ParseHistoryFileResolver _fileResolver;
  final int maxItems;

  Future<List<String>> load() async {
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
          .whereType<String>()
          .where((url) => url.trim().isNotEmpty)
          .take(maxItems)
          .toList();
    } on FormatException {
      return [];
    } on FileSystemException {
      return [];
    }
  }

  Future<List<String>> add(String url) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      return load();
    }

    final existingUrls = await load();
    final urls = [
      normalizedUrl,
      for (final item in existingUrls)
        if (item != normalizedUrl) item,
    ].take(maxItems).toList();

    await _write(urls);
    return urls;
  }

  Future<void> clear() async {
    await _write([]);
  }

  Future<void> _write(List<String> urls) async {
    final file = await _fileResolver();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(urls));
  }

  static Future<File> _defaultHistoryFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/parse_history.json');
  }
}
