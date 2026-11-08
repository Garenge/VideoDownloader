import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/main.dart';
import 'package:videodownloader/source_parser/app_settings_page.dart';
import 'package:videodownloader/source_parser/download_queue_panel.dart';
import 'package:videodownloader/source_parser/download_settings.dart';
import 'package:videodownloader/source_parser/download_tasks_page.dart';
import 'package:videodownloader/source_parser/incoming_link_bridge.dart';
import 'helpers/workspace_fixture.dart';

void main() {
  late WorkspaceParser parser;
  late MemorySettingsStore settings;
  late ValueNotifier<IncomingLinkEvent?> incoming;
  setUp(() {
    parser = WorkspaceParser();
    settings = MemorySettingsStore();
    incoming = ValueNotifier(null);
  });
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      VideoDownloaderApp(
        parserService: parser,
        downloadSettingsStore: settings,
        parseHistoryStore: WorkspaceParseHistory(),
        downloadHistoryStore: WorkspaceDownloadHistory(),
        incomingLinkListenable: incoming,
      ),
    );
    await tester.pumpAndSettle();
  }

  void share(int sequence, {String origin = 'share_extension'}) {
    incoming.value = IncomingLinkEvent(
      sequence: sequence,
      url: 'https://example.com/$sequence',
      source: 'test',
      origin: origin,
    );
  }

  Future<List<String>> queuedUrls(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('download-tasks-button')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    return tester
        .widget<DownloadQueuePanel>(find.byType(DownloadQueuePanel))
        .tasks
        .map((task) => task.resource.url)
        .toList();
  }

  testWidgets('tabs preserve input and background resume closes task page', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '目标 URL'),
      'https://example.com/new',
    );
    await tester.tap(find.text('文件').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.textContaining('文件 ·'), findsOneWidget);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '目标 URL'))
          .controller!
          .text,
      'https://example.com/new',
    );
    await queuedUrls(tester);
    expect(find.byType(DownloadTasksPage), findsOneWidget);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(DownloadTasksPage), findsNothing);
    expect(find.widgetWithText(TextField, '目标 URL'), findsOneWidget);
  });
  testWidgets(
    'sharing parses only by default and settings persist the switch',
    (tester) async {
      await pumpHome(tester);
      share(1);
      await tester.pumpAndSettle();
      expect(parser.parsed, ['https://example.com/1']);
      expect(await queuedUrls(tester), isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsPage), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('share-auto-download-switch')),
      );
      await tester.pumpAndSettle();
      expect(settings.value.shareAutoDownload, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      share(2, origin: 'direct_open');
      await tester.pumpAndSettle();
      expect(await queuedUrls(tester), isEmpty);
    },
  );
  testWidgets('cold shares wait for settings and queue each result once', (
    tester,
  ) async {
    final ready = Completer<DownloadSettings>();
    settings = MemorySettingsStore(ready: ready);
    parser.firstParse = Completer<void>();
    await pumpHome(tester);
    share(1);
    share(2);
    expect(parser.parsed, isEmpty);
    ready.complete(
      const DownloadSettings.defaults().copyWith(shareAutoDownload: true),
    );
    await tester.pump();
    await tester.pump();
    expect(parser.parsed, ['https://example.com/1']);
    await tester.runAsync(() async {
      parser.firstParse!.complete();
      // Queue restoration uses real file I/O before automatic enqueueing.
      for (var i = 0; i < 200 && parser.parsed.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    share(2);
    await tester.pumpAndSettle();
    expect(parser.parsed, ['https://example.com/1', 'https://example.com/2']);
    expect(await queuedUrls(tester), [
      'https://example.com/2.mp4',
      'https://example.com/1.mp4',
    ]);
  });
}
