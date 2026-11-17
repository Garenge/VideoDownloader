import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';
import 'package:videodownloader/source_parser/downloaded_files_page.dart';

void main() {
  Future<_Files> show(WidgetTester tester) async {
    final store = _Files();
    final queue = DownloadQueueController(downloadHistoryStore: _History());
    addTearDown(queue.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadedFilesPage(queue: queue, store: store),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets(
    'filtering and search clear selection; select all uses visible files',
    (tester) async {
      final store = await show(tester);
      await tester.tap(find.text('图片'));
      await tester.pumpAndSettle();
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('clip.mp4'), findsNothing);
      await tester.longPress(find.text('photo.jpg'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsOneWidget);
      await tester.tap(find.text('视频'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 项'), findsWidgets);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'CLIP');
      await tester.pumpAndSettle();
      expect(find.text('已选 0 项'), findsWidgets);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('批量删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除 1 个文件？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.deleted, isEmpty);
      await tester.tap(find.text('批量删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(store.deleted, ['/downloads/clip.mp4']);
      expect(store.files.map((file) => file.name), contains('photo.jpg'));
    },
  );

  testWidgets('batch deletion keeps failures selected and reports counts', (
    tester,
  ) async {
    final store = await show(tester);
    store.failPath = '/downloads/clip.mp4';
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除 3 个文件？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已删除 2 项，失败 1 项'), findsOneWidget);
    expect(find.text('已选 1 项'), findsWidgets);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(store.files.single.name, 'clip.mp4');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection controls fit a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final queue = DownloadQueueController(downloadHistoryStore: _History());
    addTearDown(queue.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: DownloadedFilesPage(queue: queue, store: _Files()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 项'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _Files extends DownloadedFileStore {
  _Files() : super(directories: () async => [], activePaths: () => {});
  String? failPath;
  final deleted = <String>[];
  final files = [
    DownloadedFile('/downloads/photo.jpg', 10, DateTime(2026, 11, 17)),
    DownloadedFile('/downloads/clip.mp4', 20, DateTime(2026, 11, 16)),
    DownloadedFile('/downloads/other.mp4', 30, DateTime(2026, 11, 15)),
  ];

  @override
  Future<List<DownloadedFile>> scan() async => List.of(files);

  @override
  Future<void> delete(DownloadedFile file) async {
    if (file.path == failPath) throw StateError('file busy');
    deleted.add(file.path);
    files.removeWhere((item) => item.path == file.path);
  }
}

class _History extends DownloadHistoryStore {
  @override
  Future<List<DownloadHistoryRecord>> load() async => [];

  @override
  Future<List<DownloadHistoryRecord>> remove(String path) async => [];
}
