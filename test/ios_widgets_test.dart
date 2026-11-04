import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_activity_overlay.dart';
import 'package:videodownloader/source_parser/download_queue_panel.dart';
import 'package:videodownloader/source_parser/ios/ios_download_info.dart';
import 'package:videodownloader/source_parser/parser_action_bar.dart';

void main() {
  testWidgets('parser controls fit a narrow phone with enlarged text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Center(
              child: SizedBox(
                width: 280,
                child: ParserActionBar(
                  hints: const Text('X · YouTube · 其他平台'),
                  isParsing: false,
                  onOpenBrowser: () {},
                  onParse: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('解析'), findsOneWidget);
  });

  testWidgets(
    'iOS history exports files and hides unsupported conversion',
    (tester) async {
      var exported = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadHistoryPanel(
              records: [
                DownloadHistoryRecord(
                  fileName: 'video.m3u8',
                  filePath: '/Documents/video.m3u8',
                  sourceUrl: 'https://example.com',
                  completedAt: DateTime(2026),
                ),
              ],
              onOpenFolder: (_) {
                exported = true;
              },
              onConvertToMp4: (_) => fail('No desktop conversion on iOS'),
              onClear: () {},
              canConvertToMp4: false,
            ),
          ),
        ),
      );
      expect(find.byTooltip('转 MP4'), findsNothing);
      await tester.tap(find.byTooltip('分享或存储文件'));
      expect(exported, isTrue);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('iOS settings explain foreground and format limits', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showIosDownloadInfo(context),
            child: const Text('设置'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('iPhone 下载'), findsOneWidget);
    expect(find.textContaining('保持 App 在前台'), findsOneWidget);
    expect(find.textContaining('本机合并'), findsOneWidget);
  });

  testWidgets('mobile activity panel has working queue and history tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadActivityOverlay(
            panelOpen: true,
            onTogglePanel: () {},
            onClosePanel: () {},
            activeTaskCount: 0,
            queuePanel: const Text('queue content'),
            conversionPanel: null,
            historyPanel: const Text('history content'),
          ),
        ),
      ),
    );
    expect(find.text('转换'), findsNothing);
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.text('history content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
