import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/path_log_label.dart';

void main() {
  test('path labels omit parent directories across path formats', () {
    expect(pathLogLabel('/Users/demo/Downloads/video.mp4'), 'video.mp4');
    expect(pathLogLabel(r'C:\Users\demo\Downloads\video.mp4'), 'video.mp4');
    expect(pathLogLabel('/Users/demo/Downloads/'), 'Downloads');
    expect(pathLogLabel(' video.mp4 '), 'video.mp4');
  });

  test('empty path labels use a placeholder', () {
    expect(pathLogLabel(''), '-');
    expect(pathLogLabel('   '), '-');
  });
}
