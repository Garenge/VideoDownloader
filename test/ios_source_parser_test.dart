import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/ios/x_public_video_resolver.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test('iOS resolves each X video to its highest bitrate public MP4', () async {
    final requests = <Uri>[];
    final parser = SourceParserService(
      useNativeDownloads: true,
      xPublicVideoResolver: XPublicVideoResolver(
        tokenGenerator: (id) async {
          expect(id, '1234567890123456789');
          return 'token';
        },
      ),
      client: MockClient((request) async {
        requests.add(request.url);
        expect(request.url.host, 'cdn.syndication.twimg.com');
        expect(request.url.queryParameters['token'], 'token');
        return http.Response(
          jsonEncode({
            'mediaDetails': [
              {'type': 'photo'},
              _video([
                _variant('a-low.mp4', 100),
                _variant('a-high.mp4', 500),
                _variant('bad.mp4', 10000, host: 'untrusted.example'),
                {
                  'url': 'https://video.twimg.com/a.m3u8',
                  'content_type': 'application/x-mpegURL',
                },
              ]),
              _video([_variant('b.mp4', 200)]),
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(parser.dispose);
    final result = await parser.parse(
      'https://x.com/demo/status/1234567890123456789?s=20',
    );
    expect(result.resources.map((r) => r.url), [
      'https://video.twimg.com/a-high.mp4',
      'https://video.twimg.com/b.mp4',
    ]);
    expect(result.resources.every((r) => !r.requiresYtDlp), isTrue);
    expect(requests, hasLength(1));
  });

  for (final status in [200, 403, 429]) {
    test('iOS reports X inaccessible media (HTTP $status)', () async {
      final parser = SourceParserService(
        useNativeDownloads: true,
        xPublicVideoResolver: XPublicVideoResolver(
          tokenGenerator: (_) async => 'token',
        ),
        client: MockClient((_) async => http.Response('{}', status)),
      );
      addTearDown(parser.dispose);
      await expectLater(
        parser.parse('https://x.com/demo/status/123'),
        throwsA(isA<SourceParserException>()),
      );
    });
  }

  test(
    'iOS accepts direct media without fetching the binary as HTML',
    () async {
      final parser = SourceParserService(
        useNativeDownloads: true,
        client: MockClient(
          (_) async => fail('Direct links need no page fetch'),
        ),
      );
      addTearDown(parser.dispose);
      final result = await parser.parse(
        'https://example.com/clip.mp4?token=abc',
      );
      expect(result.resources.single.type, SourceResourceType.video);
      expect(result.resources.single.url, endsWith('?token=abc'));
    },
  );

  test(
    'iOS keeps YouTube task when oEmbed is blocked without fetching watch HTML',
    () async {
      final parser = SourceParserService(
        useNativeDownloads: true,
        client: MockClient((request) async {
          expect(request.url.path, '/oembed');
          return http.Response('blocked', 403);
        }),
      );
      addTearDown(parser.dispose);
      final result = await parser.parse('https://youtu.be/dQw4w9WgXcQ');
      expect(result.resources.single.youtubeVideoId, 'dQw4w9WgXcQ');
    },
  );
}

Map<String, Object> _video(List<Map<String, Object>> variants) => {
  'video_info': {'variants': variants},
};

Map<String, Object> _variant(
  String name,
  int bitrate, {
  String host = 'video.twimg.com',
}) => {
  'url': 'https://$host/$name',
  'content_type': 'video/mp4',
  'bitrate': bitrate,
};
