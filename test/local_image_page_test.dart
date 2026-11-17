import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';
import 'package:videodownloader/source_parser/player/local_image_page.dart';

void main() {
  late Directory directory;
  late List<DownloadedFile> files;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('image_preview_');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
    );
    files = [
      for (var index = 0; index < 3; index++)
        DownloadedFile(
          '${directory.path}/$index.png',
          bytes.length,
          DateTime(2026),
        ),
    ];
    for (final file in files) {
      File(file.path).writeAsBytesSync(bytes);
    }
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => LocalImagePage(file: files[1], files: files),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  Finder image() => find.byType(InteractiveViewer).hitTestable().first;

  testWidgets('pinch zoom does not turn pages or dismiss the gallery', (
    tester,
  ) async {
    await show(tester);
    final center = tester.getCenter(image());
    final left = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 1,
    );
    final right = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await left.moveBy(const Offset(-60, 0));
    await right.moveBy(const Offset(60, 0));
    await tester.pump();
    await left.moveBy(const Offset(-30, 0));
    await right.moveBy(const Offset(30, 0));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(
      tester
          .widget<InteractiveViewer>(image())
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('image paging follows queue and keeps index on axis changes', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.drag(image(), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.drag(image(), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(find.text('已经是最后一张图片'), findsOneWidget);
    await tester.tap(find.byTooltip('图片切换方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上下滑动切换'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.drag(image(), const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'zoomed panning does not change images; double tap restores paging',
    (tester) async {
      await show(tester);
      final point = tester.getCenter(image());
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InteractiveViewer>(image())
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await tester.drag(image(), const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      await tester.drag(image(), const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing images show an error and can still page or swipe to exit',
    (tester) async {
      File(files[1].path).deleteSync();
      await show(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('无法读取图片'), findsWidgets);
      await tester.drag(image(), const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.drag(image(), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(find.byType(LocalImagePage), findsNothing);
    },
  );
}
