import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'download_settings.dart';

typedef DownloadSettingsFileResolver = Future<File> Function();

class DownloadSettingsStore {
  DownloadSettingsStore({DownloadSettingsFileResolver? fileResolver})
    : _fileResolver = fileResolver ?? _defaultFile;

  final DownloadSettingsFileResolver _fileResolver;

  Future<DownloadSettings> load() async {
    final file = await _fileResolver();
    if (!file.existsSync()) {
      return const DownloadSettings.defaults();
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const DownloadSettings.defaults();
      }

      return DownloadSettings.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      return const DownloadSettings.defaults();
    } on FileSystemException {
      return const DownloadSettings.defaults();
    }
  }

  Future<void> save(DownloadSettings settings) async {
    final file = await _fileResolver();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  static Future<File> _defaultFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/download_settings.json');
  }
}

