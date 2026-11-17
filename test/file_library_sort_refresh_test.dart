import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';
import 'package:videodownloader/source_parser/downloaded_files_page.dart';

import 'helpers/file_library_fixture.dart';

void main() {
  Future<FileLibraryFixture> show(WidgetTester tester) async {
    final store = FileLibraryFixture();
    final queue = DownloadQueueController(
      downloadHistoryStore: EmptyLibraryHistory(),
    );
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
    'sort menu supports all six orders and reports the chosen order',
    (tester) async {
      await show(tester);
      final orders = {
        '大小 · 从大到小': 'post-2.mp4',
        '大小 · 从小到大': 'post-10.mp4',
        '名字 · 升序': 'post-1.jpg',
        '名字 · 降序': 'post-10.mp4',
        '时间 · 最早优先': 'post-1.jpg',
        '时间 · 最新优先': 'post-10.mp4',
      };
      for (final entry in orders.entries) {
        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.text('已按${entry.key}排序'), findsOneWidget);
        final names = ['post-1.jpg', 'post-2.mp4', 'post-10.mp4']
          ..sort(
            (a, b) => tester
                .getTopLeft(find.text(a))
                .dy
                .compareTo(tester.getTopLeft(find.text(b)).dy),
          );
        expect(names.first, entry.value);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual refresh reports success and disables duplicate requests',
    (tester) async {
      final store = await show(tester);
      expect(find.textContaining('刷新成功'), findsNothing);
      final before = store.scans;
      store.pending = Completer<List<DownloadedFile>>();
      await tester.tap(find.byTooltip('刷新文件'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '刷新文件',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('刷新文件'));
      await tester.pump();
      expect(store.scans, before + 1);
      store.pending!.complete(store.files);
      await tester.pumpAndSettle();
      expect(find.text('刷新成功，共 3 个文件'), findsOneWidget);
    },
  );

  testWidgets('refresh failures show feedback and allow retry', (tester) async {
    final store = await show(tester);
    store.fail = true;
    await tester.tap(find.byTooltip('刷新文件'));
    await tester.pumpAndSettle();
    expect(find.textContaining('刷新失败：'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '刷新文件',
            ),
          )
          .onPressed,
      isNotNull,
    );
    store.fail = false;
    await tester.tap(find.byTooltip('刷新文件'));
    await tester.pumpAndSettle();
    expect(find.text('刷新成功，共 3 个文件'), findsOneWidget);
  });
}
