import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef ProxySettingsFileResolver = Future<File> Function();

class ProxySettingsStore {
  ProxySettingsStore({ProxySettingsFileResolver? fileResolver})
    : _fileResolver = fileResolver ?? _defaultFile;

  final ProxySettingsFileResolver _fileResolver;

  Future<String?> load() async {
    final file = await _fileResolver();
    if (!file.existsSync()) {
      return null;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }

      final raw = decoded['proxy'];
      if (raw is! String) {
        return null;
      }

      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> save(String? proxySpec) async {
    final file = await _fileResolver();
    await file.parent.create(recursive: true);
    final normalized = proxySpec?.trim();
    if (normalized == null || normalized.isEmpty) {
      await file.writeAsString(jsonEncode({'proxy': ''}));
      return;
    }

    await file.writeAsString(jsonEncode({'proxy': normalized}));
  }

  static Future<File> _defaultFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/proxy_settings.json');
  }
}
