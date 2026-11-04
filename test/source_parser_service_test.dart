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
    expect(result.resourcesOf(SourceResourceType.image).length, 6);
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
          expect(request.url.queryParameters['url'], watchUrl);
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

  test('creates x download task even when page fetch fails', () async {
    const statusUrl = 'https://x.com/openai/status/1234567890123456789';
    final service = SourceParserService(
      client: MockClient((request) async {
        return http.Response('forbidden', 403, request: request);
      }),
    );

    final result = await service.parse(statusUrl);
    final videos = result.resourcesOf(SourceResourceType.video);

    expect(result.platform, SourcePlatform.x);
    expect(videos, hasLength(1));
    expect(videos.first.url, statusUrl);
    expect(videos.first.requiresYtDlp, isTrue);
    expect(videos.first.title, 'X 视频：@openai/1234567890123456789');
    expect(result.message, contains('网页请求失败，已保留平台下载任务'));
  });

  test(
    'extracts player resources from data attributes and inline scripts',
    () async {
      final service = SourceParserService(
        client: MockClient((request) async {
          return http.Response(
            '''
<!doctype html>
<html>
  <body>
    <div
      data-play-url="/media/master.m3u8"
      data-cover="https://cdn.example.com/poster.jpg"
    ></div>
    <script>
      window.__PLAYER_STATE__ = {
        dash: "https://media.example.com/live/stream.mpd",
        fallback: "https://media.example.com/live/video.mp4"
      };
    </script>
  </body>
</html>
''',
            200,
            request: request,
          );
        }),
      );

      final result = await service.parse('https://example.com/watch/demo');
      final urls = result.resources.map((item) => item.url).toList();

      expect(urls, contains('https://example.com/media/master.m3u8'));
      expect(urls, contains('https://cdn.example.com/poster.jpg'));
      expect(urls, contains('https://media.example.com/live/stream.mpd'));
      expect(urls, contains('https://media.example.com/live/video.mp4'));
    },
  );

  test(
    'extracts nested json script media keys from real-world style player state',
    () async {
      final service = SourceParserService(
        client: MockClient((request) async {
          return http.Response(
            '''
<!doctype html>
<html>
  <body>
    <script type="application/json" id="player-state">
      {
        "player": {
          "video": {
            "playAddr": "/api/media/master.m3u8",
            "dashUrl": "https://cdn.example.com/video/stream.mpd",
            "coverUrl": "https://cdn.example.com/video/poster.webp"
          }
        }
      }
    </script>
    <script>
      window.__NEXT_DATA__ = {
        playbackUrl: "https://media.example.com/fallback/video.mp4",
        posterUrl: "/images/local-poster.jpg"
      };
    </script>
  </body>
</html>
''',
            200,
            request: request,
          );
        }),
      );

      final result = await service.parse('https://example.com/post/123');
      final urls = result.resources.map((item) => item.url).toList();

      expect(urls, contains('https://example.com/api/media/master.m3u8'));
      expect(urls, contains('https://cdn.example.com/video/stream.mpd'));
      expect(urls, contains('https://cdn.example.com/video/poster.webp'));
      expect(urls, contains('https://media.example.com/fallback/video.mp4'));
      expect(urls, contains('https://example.com/images/local-poster.jpg'));
    },
  );

  test(
    'extracts escaped urls and array-based media entries from scripts',
    () async {
      final service = SourceParserService(
        client: MockClient((request) async {
          return http.Response(
            '''
<!doctype html>
<html>
  <body>
    <script type="application/json">
      {
        "playlist": {
          "sources": [
            "https:\\/\\/cdn.example.com\\/live\\/master.m3u8",
            "https:\\/\\/cdn.example.com\\/live\\/backup.m3u8"
          ],
          "posterUrl": "https:\\/\\/cdn.example.com\\/img\\/cover.png"
        }
      }
    </script>
    <script>
      window.__PLAYER__ = {
        sources: [
          {play_url: "https:\\/\\/video.example.com\\/vod\\/main.mp4"},
          {play_url: "\\/vod\\/relative\\/fallback.mp4"}
        ]
      };
    </script>
  </body>
</html>
''',
            200,
            request: request,
          );
        }),
      );

      final result = await service.parse('https://example.com/article/abc');
      final urls = result.resources.map((item) => item.url).toList();

      expect(urls, contains('https://cdn.example.com/live/master.m3u8'));
      expect(urls, contains('https://cdn.example.com/live/backup.m3u8'));
      expect(urls, contains('https://cdn.example.com/img/cover.png'));
      expect(urls, contains('https://video.example.com/vod/main.mp4'));
      expect(urls, contains('https://example.com/vod/relative/fallback.mp4'));
    },
  );

  test(
    'extracts generic url and file keys inside player-style arrays',
    () async {
      final service = SourceParserService(
        client: MockClient((request) async {
          return http.Response(
            '''
<!doctype html>
<html>
  <body>
    <script type="application/json">
      {
        "playInfo": {
          "sources": [
            {"url": "https://cdn.example.com/hls/alpha.m3u8"},
            {"file": "/dash/beta.mpd"},
            {"src": "https://cdn.example.com/vod/gamma.mp4"}
          ],
          "preview": {
            "url": "https://cdn.example.com/posters/preview.jpg"
          }
        }
      }
    </script>
  </body>
</html>
''',
            200,
            request: request,
          );
        }),
      );

      final result = await service.parse('https://example.com/player/page');
      final urls = result.resources.map((item) => item.url).toList();

      expect(urls, contains('https://cdn.example.com/hls/alpha.m3u8'));
      expect(urls, contains('https://example.com/dash/beta.mpd'));
      expect(urls, contains('https://cdn.example.com/vod/gamma.mp4'));
      expect(urls, contains('https://cdn.example.com/posters/preview.jpg'));
    },
  );

  test(
    'extracts media from generalized containers and base-url joins',
    () async {
      final service = SourceParserService(
        client: MockClient((request) async {
          return http.Response(
            '''
<!doctype html>
<html>
  <body>
    <script>
      const baseUrl = "https://media.example.com/assets/";
      window.playerConfig = {
        mediaList: [
          {url: "episode-01/master.m3u8"},
          {file: "episode-01/stream.mpd"}
        ],
        qualities: [
          {src: "episode-01/video.mp4"}
        ],
        representations: [
          {path: "episode-01/backup.m3u8"}
        ]
      };
    </script>
  </body>
</html>
''',
            200,
            request: request,
          );
        }),
      );

      final result = await service.parse('https://example.com/show/42');
      final urls = result.resources.map((item) => item.url).toList();

      expect(
        urls,
        contains('https://media.example.com/assets/episode-01/master.m3u8'),
      );
      expect(
        urls,
        contains('https://media.example.com/assets/episode-01/stream.mpd'),
      );
      expect(
        urls,
        contains('https://media.example.com/assets/episode-01/video.mp4'),
      );
      expect(
        urls,
        contains('https://media.example.com/assets/episode-01/backup.m3u8'),
      );
    },
  );

  test('extracts media from concatenated script url expressions', () async {
    final service = SourceParserService(
      client: MockClient((request) async {
        return http.Response(
          '''
<!doctype html>
<html>
  <body>
    <script>
      const host = "https://cdn.example.com";
      const mediaPath = "/shows/demo/master.m3u8";
      const posterDir = "/images";
      const posterName = "/demo-cover.jpg";
      window.playerState = {
        playUrl: host + mediaPath,
        posterUrl: host + posterDir + posterName
      };
    </script>
  </body>
</html>
''',
          200,
          request: request,
        );
      }),
    );

    final result = await service.parse('https://example.com/watch/demo');
    final urls = result.resources.map((item) => item.url).toList();

    expect(urls, contains('https://cdn.example.com/shows/demo/master.m3u8'));
    expect(urls, contains('https://cdn.example.com/images/demo-cover.jpg'));
  });

  test('deduplicates repeated concatenated media candidates', () async {
    final service = SourceParserService(
      client: MockClient((request) async {
        return http.Response(
          '''
<!doctype html>
<html>
  <body>
    <script>
      const host = "https://media.example.com";
      const path = "/vod/demo/video.mp4";
      window.playerState = {
        qualities: [
          {src: host + path},
          {url: "https://media.example.com/vod/demo/video.mp4"}
        ]
      };
    </script>
  </body>
</html>
''',
          200,
          request: request,
        );
      }),
    );

    final result = await service.parse('https://example.com/watch/demo');
    final videoResources = result.resources
        .where(
          (item) => item.url == 'https://media.example.com/vod/demo/video.mp4',
        )
        .toList();

    expect(videoResources, hasLength(1));
  });

  test('extracts quality hints from json source lists', () async {
    final service = SourceParserService(
      client: MockClient((request) async {
        return http.Response(
          '''
<!doctype html>
<html>
  <body>
    <script type="application/json">
      {
        "playInfo": {
          "sources": [
            {
              "quality": "1080p",
              "url": "https://cdn.example.com/video/full-hd.mp4"
            },
            {
              "height": 720,
              "url": "https://cdn.example.com/video/hd.m3u8"
            },
            {
              "resolution": "1920x1080",
              "file": "/dash/full-hd.mpd"
            }
          ]
        }
      }
    </script>
  </body>
</html>
''',
          200,
          request: request,
        );
      }),
    );

    final result = await service.parse('https://example.com/watch/quality');
    final fullHd = result.resources.firstWhere(
      (item) => item.url == 'https://cdn.example.com/video/full-hd.mp4',
    );
    final hls = result.resources.firstWhere(
      (item) => item.url == 'https://cdn.example.com/video/hd.m3u8',
    );
    final dash = result.resources.firstWhere(
      (item) => item.url == 'https://example.com/dash/full-hd.mpd',
    );

    expect(fullHd.sizeHint, contains('1080p'));
    expect(hls.sizeHint, contains('720p'));
    expect(dash.sizeHint, contains('1080p'));
  });

  test('keeps inline script quality hints on deduplicated media', () async {
    final service = SourceParserService(
      client: MockClient((request) async {
        return http.Response(
          '''
<!doctype html>
<html>
  <body>
    <script>
      window.playerState = {
        sources: [
          {
            label: "HD",
            src: "https://cdn.example.com/video/hd.mp4"
          },
          {
            resolution: "3840x2160",
            url: "https://cdn.example.com/video/uhd.m3u8"
          }
        ]
      };
    </script>
  </body>
</html>
''',
          200,
          request: request,
        );
      }),
    );

    final result = await service.parse('https://example.com/watch/inline');
    final hdResources = result.resources
        .where((item) => item.url == 'https://cdn.example.com/video/hd.mp4')
        .toList();
    final uhd = result.resources.firstWhere(
      (item) => item.url == 'https://cdn.example.com/video/uhd.m3u8',
    );

    expect(hdResources, hasLength(1));
    expect(hdResources.single.sizeHint, contains('HD'));
    expect(uhd.sizeHint, contains('2160p'));
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
