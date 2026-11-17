import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/downloaded_file_batch_actions.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';
import 'package:videodownloader/source_parser/downloaded_files_selection.dart';
import 'package:videodownloader/source_parser/ios/ios_media_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('batch export sends all paths in one native request', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosMediaBridge.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(IosMediaBridge.channel, null),
    );
    final selection = DownloadedFilesSelection();
    addTearDown(selection.dispose);
    await DownloadedFileBatchActions.share([
      DownloadedFile('/Documents/123-1.jpg', 10, DateTime(2026)),
      DownloadedFile('/Documents/123-2.mp4', 20, DateTime(2026)),
    ], selection);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'exportFiles');
    expect(calls.single.arguments, [
      '/Documents/123-1.jpg',
      '/Documents/123-2.mp4',
    ]);
    expect(selection.busy, isFalse);
  });
}
