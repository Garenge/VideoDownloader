import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';

void main() {
  late Directory root;
  late Set<String> active;
  late DownloadedFileStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('downloaded_files_test_');
    active = {};
    store = DownloadedFileStore(
      directories: () async => [root, root],
      activePaths: () => active,
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'scans real files without history, excludes partials, links and active downloads',
    () async {
      for (final name in [
        'video.mp4',
        'photo.jpg',
        'active.mp4',
        'video.part',
        '.hidden',
        'file.tmp',
      ]) {
        await File('${root.path}/$name').writeAsString('media');
      }
      active.add('${root.path}/active.mp4');
      await Link('${root.path}/linked.mp4').create('${root.path}/video.mp4');
      final files = await store.scan();
      expect(files.map((file) => file.name).toSet(), {
        'video.mp4',
        'photo.jpg',
      });
      expect(files.first.size, 5);
      active.clear();
      expect((await store.scan()).length, 3);
    },
  );

  test(
    'orders files by modification time and rescans after a new store is created',
    () async {
      final old = await File('${root.path}/old.mp4').writeAsString('old');
      await old.setLastModified(DateTime(2020));
      await File('${root.path}/new.mp4').writeAsString('new');
      final reopened = DownloadedFileStore(
        directories: () async => [root],
        activePaths: () => {},
      );
      expect((await reopened.scan()).map((file) => file.name), [
        'new.mp4',
        'old.mp4',
      ]);
    },
  );

  test('deletes managed files and tolerates an already removed file', () async {
    await File('${root.path}/video.mp4').writeAsString('media');
    final file = (await store.scan()).single;
    await store.delete(file);
    await store.delete(file);
    expect(await store.scan(), isEmpty);
  });

  test(
    'rejects active files and paths outside the download directory',
    () async {
      final outside = await Directory.systemTemp.createTemp(
        'outside_downloads_',
      );
      addTearDown(() => outside.delete(recursive: true));
      final path = '${outside.path}/outside.mp4';
      await File(path).writeAsString('private');
      await expectLater(
        store.delete(DownloadedFile(path, 7, DateTime.now())),
        throwsA(isA<FileSystemException>()),
      );
      final file = await File(
        '${root.path}/active.mp4',
      ).writeAsString('partial');
      active.add(file.path);
      await expectLater(
        store.delete(DownloadedFile(file.path, 7, DateTime.now())),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.exists(), isTrue);
    },
  );
}
