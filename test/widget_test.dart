import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/main.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/incoming_link_bridge.dart';
import 'package:videodownloader/source_parser/parse_history_store.dart';
import 'package:videodownloader/source_parser/source_parser_home_page.dart';
import 'package:videodownloader/source_parser/source_resource.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';

void main() {
  testWidgets('unexpected parse timeout displays an error and enables retry', (
    tester,
  ) async {
    final parser = SourceParserService(
      useNativeDownloads: true,
      xSessionResolver: (_) async => throw TimeoutException('network'),
    );
    addTearDown(parser.dispose);
    await tester.pumpWidget(
      VideoDownloaderApp(
        parserService: parser,
        parseHistoryStore: _MemoryParseHistoryStore(),
        downloadHistoryStore: _MemoryDownloadHistoryStore(),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, '目标 URL'),
      'https://x.com/demo/status/123',
    );
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.textContaining('解析请求超时'), findsOneWidget);
    expect(find.text('解析中'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows parser home page and parses url', (tester) async {
    await _pumpParsedHomePage(tester);

    expect(find.text('网页资源解析'), findsOneWidget);
    expect(find.text('YouTube'), findsAtLeastNWidgets(1));
    expect(find.text('视频 1'), findsOneWidget);
    expect(find.text('图片 2'), findsOneWidget);
    expect(find.text('其他 1'), findsOneWidget);
    expect(find.text('Photo'), findsAtLeastNWidgets(1));
    expect(
      find.text('https://cdn.example.com/photo.png'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.text('https://media.example.com/movie.mp4'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.byKey(
        const ValueKey(
          'resource-preview-image-https://cdn.example.com/photo.png',
        ),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('filters parsed resources by search text', (tester) async {
    await _pumpParsedHomePage(tester);

    await tester.enterText(_resourceSearchField, 'movie');
    await tester.pumpAndSettle();

    expect(find.text('Photo'), findsNothing);
    expect(find.text('视频资源'), findsAtLeastNWidgets(1));
  });

  testWidgets('filters parsed resources by host', (tester) async {
    await _pumpParsedHomePage(tester);

    await _selectDropdownValue(
      tester,
      const ValueKey('host-filter-menu'),
      'cdn.example.com',
    );

    expect(find.text('Photo'), findsAtLeastNWidgets(1));
    expect(find.text('视频资源'), findsNothing);
    expect(find.text('Open Graph 图片'), findsNothing);
  });

  testWidgets('filters parsed resources by extension', (tester) async {
    await _pumpParsedHomePage(tester);

    await _selectDropdownValue(
      tester,
      const ValueKey('extension-filter-menu'),
      'jpg',
    );

    expect(find.text('Open Graph 图片'), findsAtLeastNWidgets(1));
    expect(find.text('Photo'), findsNothing);
    expect(find.text('视频资源'), findsNothing);
  });

  testWidgets('clears parsed resource filters', (tester) async {
    await _pumpParsedHomePage(tester);

    await tester.enterText(_resourceSearchField, 'movie');
    await _selectDropdownValue(
      tester,
      const ValueKey('host-filter-menu'),
      'media.example.com',
    );
    final clearButton = find.byKey(
      const ValueKey('clear-resource-filters-button'),
    );
    await tester.ensureVisible(clearButton);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(find.text('Photo'), findsAtLeastNWidgets(1));
    expect(find.text('Open Graph 图片'), findsAtLeastNWidgets(1));
    expect(find.text('视频资源'), findsAtLeastNWidgets(1));
    expect(tester.widget<TextField>(_resourceSearchField).controller?.text, '');
  });

  testWidgets('stores and clears recent parse urls', (tester) async {
    final historyStore = _MemoryParseHistoryStore();

    await _pumpParsedHomePage(tester, parseHistoryStore: historyStore);

    expect(
      find.byKey(const ValueKey('open-recent-urls-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('open-recent-urls-button')));
    await tester.pumpAndSettle();

    expect(find.text('最近解析'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('recent-url-https://www.youtube.com/watch?v=demo'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.widgetWithText(TextField, '目标 URL'), '');
    await tester.tap(
      find.byKey(
        const ValueKey('recent-url-https://www.youtube.com/watch?v=demo'),
      ),
    );
    await tester.pumpAndSettle();

    final urlField = tester.widget<TextField>(
      find.widgetWithText(TextField, '目标 URL'),
    );
    expect(urlField.controller?.text, 'https://www.youtube.com/watch?v=demo');

    await tester.tap(find.byKey(const ValueKey('open-recent-urls-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-parse-history-button')));
    await tester.pumpAndSettle();

    expect(find.text('当前还没有最近解析记录'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open-recent-urls-button')), findsNothing);
    expect(await historyStore.load(), isEmpty);
  });

  testWidgets('warns before downloading hls playlist resources', (
    tester,
  ) async {
    await _pumpParsedHomePage(
      tester,
      htmlFixture: '''
<!doctype html>
<html>
  <body>
    <video>
      <source src="https://media.example.com/stream.m3u8" type="application/vnd.apple.mpegurl">
    </video>
  </body>
</html>
''',
    );

    final downloadButton = find
        .widgetWithIcon(IconButton, Icons.download)
        .first;
    await tester.ensureVisible(downloadButton);
    await tester.tap(downloadButton);
    await tester.pumpAndSettle();

    expect(find.text('下载前提示'), findsOneWidget);
    expect(find.textContaining('HLS 播放列表资源'), findsOneWidget);
    expect(find.textContaining('当前未检测到 ffmpeg'), findsOneWidget);
    expect(find.text('继续下载'), findsOneWidget);
  });

  testWidgets('blocks x download queue entry when preflight finds no video', (
    tester,
  ) async {
    await _pumpParsedHomePage(
      tester,
      htmlFixture: '''
<!doctype html>
<html>
  <body>
    <meta property="og:title" content="X status">
  </body>
</html>
''',
      initialUrl: 'https://x.com/openai/status/1234567890123456789',
      xVideoPreflightProbe: (resource) async {
        expect(resource.platform, SourcePlatform.x);
        return const XVideoPreflightResult(
          errorMessage:
              '这条推文当前没有检测到可下载的视频媒体，已阻止加入下载队列。可能是图片推文、纯文本推文，或公开页面未暴露视频资源。',
          debugLog: '[X Preflight Debug Log]\nmock=true',
        );
      },
    );

    final downloadButton = find.byKey(
      const ValueKey(
        'resource-download-https://x.com/openai/status/1234567890123456789',
      ),
    );
    final button = tester.widget<IconButton>(downloadButton);
    button.onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('X 视频预检失败'), findsOneWidget);
    expect(find.textContaining('已阻止加入下载队列'), findsOneWidget);
    expect(find.text('复制日志'), findsOneWidget);
    expect(find.textContaining('已加入下载队列'), findsNothing);
  });

  testWidgets('shows a resolving indicator while X preflight is pending', (
    tester,
  ) async {
    final preflight = Completer<XVideoPreflightResult>();
    await _pumpParsedHomePage(
      tester,
      htmlFixture: '''
<!doctype html>
<html>
  <body>
    <meta property="og:title" content="X status">
  </body>
</html>
''',
      initialUrl: 'https://x.com/openai/status/1234567890123456789',
      xVideoPreflightProbe: (_) => preflight.future,
    );

    final downloadButton = find.byKey(
      const ValueKey(
        'resource-download-https://x.com/openai/status/1234567890123456789',
      ),
    );
    await tester.ensureVisible(downloadButton);
    tester.widget<IconButton>(downloadButton).onPressed!.call();
    await tester.pump();

    final resolvingButton = tester.widget<IconButton>(downloadButton);
    expect(resolvingButton.onPressed, isNull);
    expect(resolvingButton.tooltip, '正在解析');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    preflight.complete(
      const XVideoPreflightResult(errorMessage: '预检失败', debugLog: 'test'),
    );
    await tester.pumpAndSettle();

    final idleButton = tester.widget<IconButton>(downloadButton);
    expect(idleButton.onPressed, isNotNull);
    expect(idleButton.tooltip, '下载');
    expect(find.text('X 视频预检失败'), findsOneWidget);
  });

  testWidgets('auto parses an incoming link from app intake', (tester) async {
    final incomingLinkListenable = ValueNotifier<IncomingLinkEvent?>(null);
    final parserService = SourceParserService(
      client: MockClient((request) async {
        if (_looksLikeThumbnailRequest(request.url)) {
          return http.Response.bytes(
            _minimalPngBytes,
            200,
            headers: const {'Content-Type': 'image/png'},
          );
        }

        return http.Response(_htmlFixture, 200, request: request);
      }),
    );

    await tester.pumpWidget(
      VideoDownloaderApp(
        parserService: parserService,
        parseHistoryStore: _MemoryParseHistoryStore(),
        downloadHistoryStore: _MemoryDownloadHistoryStore(),
        incomingLinkListenable: incomingLinkListenable,
      ),
    );

    incomingLinkListenable.value = const IncomingLinkEvent(
      sequence: 1,
      url: 'https://www.youtube.com/watch?v=shared_demo',
      source: 'test',
      origin: 'share_extension',
      debugLog: '[Incoming Link Native Log]\norigin=share_extension',
    );

    await _pumpUntilFound(tester, find.text('YouTube'));

    final urlField = tester.widget<TextField>(
      find.widgetWithText(TextField, '目标 URL'),
    );
    expect(
      urlField.controller?.text,
      'https://www.youtube.com/watch?v=shared_demo',
    );
    expect(find.text('视频 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('incoming-link-banner')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('show-incoming-link-logs-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('分享接入日志'), findsOneWidget);
    expect(find.textContaining('origin=share_extension'), findsWidgets);
    expect(find.textContaining('解析成功'), findsOneWidget);
    expect(find.text('复制日志'), findsOneWidget);
  });
}

final _minimalPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

bool _looksLikeThumbnailRequest(Uri url) {
  final path = url.path.toLowerCase();
  if (url.host.endsWith('ytimg.com')) {
    return true;
  }
  if (url.host.contains('youtube.com')) {
    return url.path.contains('cover.') ||
        url.path.endsWith('.jpg') ||
        url.path.endsWith('.jpeg') ||
        url.path.endsWith('.png') ||
        url.path.endsWith('.webp') ||
        url.path.endsWith('.ico');
  }

  final ext = RegExp(
    r'\.(jpg|jpeg|png|webp|gif|bmp|ico)$',
    caseSensitive: false,
  );
  return ext.hasMatch(path);
}

const _htmlFixture = '''
<!doctype html>
<html>
  <head>
    <meta property="og:image" content="/cover.jpg">
    <link rel="preload" href="/metadata.json" as="fetch">
  </head>
  <body>
    <img src="https://cdn.example.com/photo.png" width="640" height="360" alt="Photo">
    <video src="https://media.example.com/movie.mp4"></video>
  </body>
</html>
''';

Finder get _resourceSearchField {
  return find.byKey(const ValueKey('resource-search-field'));
}

Future<void> _pumpParsedHomePage(
  WidgetTester tester, {
  ParseHistoryStore? parseHistoryStore,
  String htmlFixture = _htmlFixture,
  String initialUrl = 'https://www.youtube.com/watch?v=demo',
  Future<XVideoPreflightResult> Function(SourceResource resource)?
  xVideoPreflightProbe,
}) async {
  final parserService = SourceParserService(
    client: MockClient((request) async {
      if (_looksLikeThumbnailRequest(request.url)) {
        return http.Response.bytes(
          _minimalPngBytes,
          200,
          headers: const {'Content-Type': 'image/png'},
        );
      }

      return http.Response(htmlFixture, 200, request: request);
    }),
  );

  await tester.pumpWidget(
    VideoDownloaderApp(
      parserService: parserService,
      parseHistoryStore: parseHistoryStore ?? _MemoryParseHistoryStore(),
      downloadHistoryStore: _MemoryDownloadHistoryStore(),
      xVideoPreflightProbe: xVideoPreflightProbe,
    ),
  );

  expect(find.text('等待解析'), findsOneWidget);

  await tester.enterText(find.widgetWithText(TextField, '目标 URL'), initialUrl);
  await tester.tap(find.text('解析'));
  await _pumpUntilFound(tester, find.text('YouTube'));
}

Future<void> _selectDropdownValue(
  WidgetTester tester,
  Key dropdownKey,
  String value,
) async {
  final dropdown = find.byKey(dropdownKey);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('pumpUntilFound: finder did not appear: $finder');
}

class _MemoryParseHistoryStore extends ParseHistoryStore {
  _MemoryParseHistoryStore() : super(fileResolver: _unusedFile);

  final List<String> _urls = [];

  @override
  Future<List<String>> load() async {
    return List.unmodifiable(_urls);
  }

  @override
  Future<List<String>> add(String url) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      return load();
    }

    _urls
      ..remove(normalizedUrl)
      ..insert(0, normalizedUrl);
    if (_urls.length > maxItems) {
      _urls.removeRange(maxItems, _urls.length);
    }

    return load();
  }

  @override
  Future<void> clear() async {
    _urls.clear();
  }

  static Future<File> _unusedFile() async {
    return File('/unused_parse_history.json');
  }
}

class _MemoryDownloadHistoryStore extends DownloadHistoryStore {
  _MemoryDownloadHistoryStore() : super(fileResolver: _unusedFile);

  final List<DownloadHistoryRecord> _records = [];

  @override
  Future<List<DownloadHistoryRecord>> load() async {
    return List.unmodifiable(_records);
  }

  @override
  Future<List<DownloadHistoryRecord>> add(DownloadHistoryRecord record) async {
    _records
      ..removeWhere((item) => item.filePath == record.filePath)
      ..insert(0, record);
    if (_records.length > maxItems) {
      _records.removeRange(maxItems, _records.length);
    }

    return load();
  }

  @override
  Future<void> clear() async {
    _records.clear();
  }

  static Future<File> _unusedFile() async {
    return File('/unused_download_history.json');
  }
}
