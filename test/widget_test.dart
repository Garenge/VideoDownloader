import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/main.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/parse_history_store.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';

void main() {
  testWidgets('shows parser home page and parses url', (tester) async {
    await _pumpParsedHomePage(tester);

    expect(find.text('网页资源解析'), findsOneWidget);
    expect(find.text('YouTube'), findsAtLeastNWidgets(1));
    expect(find.text('视频 1'), findsOneWidget);
    expect(find.text('图片 2'), findsOneWidget);
    expect(find.text('其他 1'), findsOneWidget);
    expect(find.text('Photo'), findsAtLeastNWidgets(1));
    expect(find.text('https://cdn.example.com/photo.png'), findsAtLeastNWidgets(1));
    expect(find.text('https://media.example.com/movie.mp4'), findsAtLeastNWidgets(1));
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

    await tester.tap(find.byKey(const ValueKey('clear-parse-history-button')));
    await tester.pumpAndSettle();

    expect(find.text('最近解析'), findsNothing);
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

    final downloadButton = find.byTooltip('下载').first;
    await tester.ensureVisible(downloadButton);
    await tester.tap(downloadButton);
    await tester.pumpAndSettle();

    expect(find.text('下载前提示'), findsOneWidget);
    expect(find.textContaining('HLS 播放列表资源'), findsOneWidget);
    expect(find.textContaining('当前未检测到 ffmpeg'), findsOneWidget);
    expect(find.text('继续下载'), findsOneWidget);
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
    ),
  );

  expect(find.text('等待解析'), findsOneWidget);

  await tester.enterText(
    find.widgetWithText(TextField, '目标 URL'),
    'https://www.youtube.com/watch?v=demo',
  );
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
