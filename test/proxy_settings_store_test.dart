import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/proxy_settings_store.dart';

void main() {
  test('load returns null when file missing', () async {
    final store = ProxySettingsStore(
      fileResolver: () async => File('/nonexistent/proxy_settings.json'),
    );

    expect(await store.load(), isNull);
  });

  test('save and load round trip', () async {
    final file = File(
      '${Directory.systemTemp.path}/videodownloader_proxy_test_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });

    final store = ProxySettingsStore(fileResolver: () async => file);

    await store.save('127.0.0.1:7890');
    expect(await store.load(), '127.0.0.1:7890');

    await store.save(null);
    expect(await store.load(), isNull);
  });
}
