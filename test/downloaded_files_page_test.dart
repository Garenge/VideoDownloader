import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';
import 'package:videodownloader/source_parser/downloaded_files_page.dart';

void main() {
  testWidgets('file list searches names and reverses date order', (
    tester,
  ) async {
    final store = _Files();
    final queue = DownloadQueueController(downloadHistoryStore: _History());
    addTearDown(queue.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadedFilesPage(queue: queue, store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('new.mp4'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('new.mp4')).dy,
      lessThan(tester.getTopLeft(find.text('old.mp4')).dy),
    );
    await tester.tap(find.byTooltip('改为最早优先'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('old.mp4')).dy,
      lessThan(tester.getTopLeft(find.text('new.mp4')).dy),
    );
    await tester.enterText(find.byType(TextField), 'NEW');
    await tester.pumpAndSettle();
    expect(find.text('new.mp4'), findsOneWidget);
    expect(find.text('old.mp4'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'file deletion requires confirmation and removes associated history',
    (tester) async {
      final store = _Files();
      final history = _History();
      final queue = DownloadQueueController(downloadHistoryStore: history);
      addTearDown(queue.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DownloadedFilesPage(queue: queue, store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('文件操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.deleted, isEmpty);
      await tester.tap(find.byTooltip('文件操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(store.deleted, ['/downloads/new.mp4']);
      expect(find.text('new.mp4'), findsNothing);
      expect(queue.history, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Files extends DownloadedFileStore {
  _Files() : super(directories: () async => [], activePaths: () => {});
  final deleted = <String>[];
  final files = [
    DownloadedFile('/downloads/new.mp4', 2048, DateTime(2026, 11, 5)),
    DownloadedFile('/downloads/old.mp4', 1024, DateTime(2026, 11, 4)),
  ];
  @override
  Future<List<DownloadedFile>> scan() async => List.of(files);
  @override
  Future<void> delete(DownloadedFile file) async {
    deleted.add(file.path);
    files.removeWhere((item) => item.path == file.path);
  }
}

class _History extends DownloadHistoryStore {
  final records = [
    DownloadHistoryRecord(
      fileName: 'new.mp4',
      filePath: '/downloads/new.mp4',
      sourceUrl: 'https://example.com',
      completedAt: DateTime(2026),
    ),
  ];
  @override
  Future<List<DownloadHistoryRecord>> load() async => List.of(records);
  @override
  Future<List<DownloadHistoryRecord>> remove(String path) async {
    records.removeWhere((record) => record.filePath == path);
    return List.of(records);
  }
}
