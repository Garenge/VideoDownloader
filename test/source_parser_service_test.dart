import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test('parses local fixture site resources through http', () async {
    final server = await _FixtureServer.start();
    addTearDown(server.close);

    final result = await SourceParserService().parse(server.url);

    expect(result.platform, SourcePlatform.other);
    expect(result.resourcesOf(SourceResourceType.image).length, 5);
    expect(result.resourcesOf(SourceResourceType.video).length, 4);
    expect(result.resourcesOf(SourceResourceType.other).length, 1);
  });

  test('detects bilibili platform urls', () async {
    final service = SourceParserService(
      client: MockClient((request) async {
        return http.Response(_minimalHtml, 200, request: request);
      }),
    );

    final result = await service.parse('https://www.bilibili.com/video/BV1xx');

    expect(result.platform, SourcePlatform.bilibili);
  });

  test('parses youtube public oembed thumbnail metadata', () async {
    const watchUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
    final service = SourceParserService(
      client: MockClient((request) async {
        if (request.url.path == '/oembed') {
          expect(
            request.url.queryParameters['url'],
            watchUrl,
          );
          return http.Response(
            jsonEncode({
              'title': 'Demo Video',
              'author_name': 'Demo Channel',
              'thumbnail_url':
                  'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
            }),
            200,
            request: request,
          );
        }

        return http.Response(_minimalHtml, 200, request: request);
      }),
    );

    final result = await service.parse(watchUrl);
    final images = result.resourcesOf(SourceResourceType.image);
    final videos = result.resourcesOf(SourceResourceType.video);

    expect(result.platform, SourcePlatform.youtube);
    expect(images.first.title, 'YouTube 封面：Demo Video');
    expect(
      images.first.url,
      'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    );
    expect(images.first.sizeHint, 'YouTube oEmbed · Demo Channel');
    expect(videos, hasLength(1));
    expect(videos.first.youtubeVideoId, 'dQw4w9WgXcQ');
    expect(videos.first.title, 'YouTube 视频：Demo Video');
    expect(videos.first.url, watchUrl);
  });
}

class _FixtureServer {
  const _FixtureServer(this._server);

  final HttpServer _server;

  String get url => 'http://${_server.address.host}:${_server.port}/';

  static Future<_FixtureServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = Directory('tooling/parser_fixture_site');

    server.listen((request) async {
      final path = request.uri.path == '/' ? '/index.html' : request.uri.path;
      final file = File('${fixture.path}$path');
      final response = request.response;

      if (!file.existsSync()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      response.headers.contentType = _contentType(file.path);
      await response.addStream(file.openRead());
      await response.close();
    });

    return _FixtureServer(server);
  }

  Future<void> close() async {
    await _server.close(force: true);
  }
}

ContentType _contentType(String path) {
  if (path.endsWith('.html')) {
    return ContentType.html;
  }

  if (path.endsWith('.svg')) {
    return ContentType('image', 'svg+xml');
  }

  if (path.endsWith('.json')) {
    return ContentType.json;
  }

  if (path.endsWith('.mp4')) {
    return ContentType('video', 'mp4');
  }

  if (path.endsWith('.webm')) {
    return ContentType('video', 'webm');
  }

  return ContentType.binary;
}

const _minimalHtml = '''
<!doctype html>
<html>
  <body>
    <img src="/cover.png" alt="cover">
  </body>
</html>
''';
