import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/main.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';

void main() {
  testWidgets('shows parser home page and parses url', (tester) async {
    final parserService = SourceParserService(
      client: MockClient((request) async {
        return http.Response(_htmlFixture, 200, request: request);
      }),
    );

    await tester.pumpWidget(VideoDownloaderApp(parserService: parserService));

    expect(find.text('网页资源解析'), findsOneWidget);
    expect(find.text('等待解析'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/watch?v=demo',
    );
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.text('YouTube'), findsAtLeastNWidgets(1));
    expect(find.text('视频 1'), findsOneWidget);
    expect(find.text('图片 2'), findsOneWidget);
    expect(find.text('其他 1'), findsOneWidget);
  });
}

const _htmlFixture = '''
<!doctype html>
<html>
  <head>
    <meta property="og:image" content="/cover.jpg">
    <link rel="preload" href="/metadata.json" as="fetch">
  </head>
  <body>
    <img src="/photo.png" width="640" height="360" alt="Photo">
    <video src="/movie.mp4"></video>
  </body>
</html>
''';
