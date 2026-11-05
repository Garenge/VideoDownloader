import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';

void main() {
  test(
    'removing one record preserves files and other records after reload',
    () async {
      final store = await _createStore();
      final directory = await Directory.systemTemp.createTemp('history_media_');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/video.mp4',
      ).writeAsString('video');
      await store.add(_record('video.mp4', file.path));
      await store.add(_record('other.mp4', '/other.mp4'));
      await store.remove(file.path);
      expect((await store.load()).single.filePath, '/other.mp4');
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'concurrent history additions and removals do not lose records',
    () async {
      final store = await _createStore();
      await store.add(_record('one.mp4', '/one.mp4'));
      await Future.wait([
        store.remove('/one.mp4'),
        store.add(_record('two.mp4', '/two.mp4')),
        store.add(_record('three.mp4', '/three.mp4')),
      ]);
      expect((await store.load()).map((record) => record.filePath), [
        '/three.mp4',
        '/two.mp4',
      ]);
    },
  );

  test(
    'stores completed download records with dedupe and max item limit',
    () async {
      final store = await _createStore(maxItems: 2);

      await store.add(_record('one.mp4', '/tmp/one.mp4'));
      await store.add(_record('two.mp4', '/tmp/two.mp4'));
      final records = await store.add(_record('one-new.mp4', '/tmp/one.mp4'));

      expect(records.map((item) => item.fileName), ['one-new.mp4', 'two.mp4']);

      final limitedRecords = await store.add(
        _record('three.mp4', '/tmp/three.mp4'),
      );

      expect(limitedRecords.map((item) => item.fileName), [
        'three.mp4',
        'one-new.mp4',
      ]);
    },
  );

  test('clears completed download records', () async {
    final store = await _createStore();

    await store.add(_record('demo.mp4', '/tmp/demo.mp4'));
    await store.clear();

    expect(await store.load(), isEmpty);
  });
}

Future<DownloadHistoryStore> _createStore({int maxItems = 50}) async {
  final directory = await Directory.systemTemp.createTemp(
    'videodownloader_download_history_test_',
  );
  addTearDown(() => directory.delete(recursive: true));

  return DownloadHistoryStore(
    maxItems: maxItems,
    fileResolver: () async => File('${directory.path}/download_history.json'),
  );
}

DownloadHistoryRecord _record(String fileName, String filePath) {
  return DownloadHistoryRecord(
    fileName: fileName,
    filePath: filePath,
    sourceUrl: 'https://example.com/$fileName',
    completedAt: DateTime(2026, 5, 1, 10, 30),
  );
}
