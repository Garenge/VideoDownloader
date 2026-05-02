import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/parse_history_store.dart';

void main() {
  test('stores recent parse urls with dedupe and max item limit', () async {
    final store = await _createStore(maxItems: 3);

    await store.add('https://example.com/one');
    await store.add('https://example.com/two');
    await store.add('https://example.com/three');
    final urls = await store.add('https://example.com/two');

    expect(urls, [
      'https://example.com/two',
      'https://example.com/three',
      'https://example.com/one',
    ]);

    final limitedUrls = await store.add('https://example.com/four');

    expect(limitedUrls, [
      'https://example.com/four',
      'https://example.com/two',
      'https://example.com/three',
    ]);
  });

  test('clears recent parse urls', () async {
    final store = await _createStore();

    await store.add('https://example.com/demo');
    await store.clear();

    expect(await store.load(), isEmpty);
  });
}

Future<ParseHistoryStore> _createStore({int maxItems = 10}) async {
  final directory = await Directory.systemTemp.createTemp(
    'videodownloader_history_test_',
  );
  addTearDown(() => directory.delete(recursive: true));

  return ParseHistoryStore(
    maxItems: maxItems,
    fileResolver: () async => File('${directory.path}/parse_history.json'),
  );
}
