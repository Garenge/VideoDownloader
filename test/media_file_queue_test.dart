import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';
import 'package:videodownloader/source_parser/downloaded_files_sort.dart';
import 'package:videodownloader/source_parser/player/media_file_queue.dart';
import 'package:videodownloader/source_parser/player/media_swipe.dart';

void main() {
  test('names sort naturally with large identifiers and case differences', () {
    final names = ['123-10.mp4', '123-2.mp4', '123-1.mp4']
      ..sort(compareFileNames);
    expect(names, ['123-1.mp4', '123-2.mp4', '123-10.mp4']);
    expect(compareFileNames('FILE2', 'file10'), lessThan(0));
    expect(
      compareFileNames(
        '99999999999999999999999999',
        '100000000000000000000000000',
      ),
      lessThan(0),
    );
  });

  test('preview queue preserves filtered order and the opening position', () {
    final first = DownloadedFile('/b.mp4', 1, DateTime(2026));
    final second = DownloadedFile('/a.mp4', 2, DateTime(2026));
    final files = [first, second];
    final queue = MediaFileQueue(second, files);
    files.clear();
    expect(queue.positionLabel, '2 / 2');
    expect(queue.current, second);
    expect(queue.move(1), isFalse);
    expect(queue.move(-1), isTrue);
    expect(queue.current, first);
    expect(queue.move(-1), isFalse);
  });

  test('short drags do not switch; deliberate distance or flick does', () {
    expect(swipeOffset(-10, -2000), 0);
    expect(swipeOffset(-35, 0), 0);
    expect(swipeOffset(-70, 0), 1);
    expect(swipeOffset(70, 0), -1);
    expect(swipeOffset(-20, -800), 1);
  });
}
