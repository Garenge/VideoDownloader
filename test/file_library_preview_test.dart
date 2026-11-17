import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/downloaded_files_page.dart';
import 'package:videodownloader/source_parser/player/local_image_page.dart';
import 'package:videodownloader/source_parser/player/local_video_page.dart';

import 'helpers/file_library_fixture.dart';

void main() {
  testWidgets(
    'previews receive only matching files in the selected sort order',
    (tester) async {
      final queue = DownloadQueueController(
        downloadHistoryStore: EmptyLibraryHistory(),
      );
      addTearDown(queue.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DownloadedFilesPage(queue: queue, store: FileLibraryFixture()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('名字 · 升序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('post-10.mp4'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      final video = tester.widget<LocalVideoPage>(find.byType(LocalVideoPage));
      expect(video.file.name, 'post-10.mp4');
      expect(video.files.map((file) => file.name), [
        'post-2.mp4',
        'post-10.mp4',
      ]);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'post-1.jpg');
      await tester.pumpAndSettle();
      await tester.tap(find.text('post-1.jpg', skipOffstage: true).last);
      await tester.pumpAndSettle();
      final image = tester.widget<LocalImagePage>(find.byType(LocalImagePage));
      expect(image.files.map((file) => file.name), ['post-1.jpg']);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
