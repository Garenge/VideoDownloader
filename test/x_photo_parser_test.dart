import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/ios/x_public_video_resolver.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  for (final native in [true, false]) {
    for (final mixed in [true, false]) {
      test('X photos and mixed=$mixed media, native=$native', () async {
        final parser = SourceParserService(
          useNativeDownloads: native,
          xSessionResolver: (_) async => null,
          xPublicVideoResolver: XPublicVideoResolver(
            tokenGenerator: (_) async => 'token',
          ),
          client: MockClient((request) async {
            expect(request.url.host, 'cdn.syndication.twimg.com');
            return http.Response(
              jsonEncode({
                'mediaDetails': [
                  photo('https://pbs.twimg.com/media/first.jpg?name=small'),
                  photo(
                    'https://pbs.twimg.com/media/second?format=png&name=small',
                  ),
                  photo('https://pbs.twimg.com/media/first.jpg?name=large'),
                  photo('https://pbs.twimg.com/profile_images/avatar.jpg'),
                  photo('https://pbs.twimg.com.evil.example/media/bad.jpg'),
                  photo('http://pbs.twimg.com/media/insecure.jpg'),
                  if (mixed)
                    {
                      'type': 'video',
                      'media_url_https':
                          'https://pbs.twimg.com/media/cover.jpg',
                      'video_info': {
                        'variants': [variant('low', 100), variant('high', 900)],
                      },
                    },
                ],
                'quoted_tweet': {
                  'mediaDetails': [
                    photo('https://pbs.twimg.com/media/quoted.jpg'),
                  ],
                },
              }),
              200,
            );
          }),
        );
        addTearDown(parser.dispose);
        final result = await parser.parse(
          'https://x.com/demo/status/123/photo/1',
        );
        final images = result.resourcesOf(SourceResourceType.image);
        expect(images.map((r) => r.url), [
          'https://pbs.twimg.com/media/first.jpg?name=orig',
          'https://pbs.twimg.com/media/second.png?name=orig',
        ]);
        expect(images.map((r) => r.fileExtension), ['jpg', 'png']);
        expect(result.resources.every((r) => !r.requiresYtDlp), isTrue);
        final videos = result.resourcesOf(SourceResourceType.video);
        expect(videos, hasLength(mixed ? 1 : 0));
        if (mixed) {
          expect(videos.single.url, 'https://video.twimg.com/high.mp4');
        }
      });
    }
  }
}

Map<String, Object> photo(String url) => {
  'type': 'photo',
  'media_url_https': url,
};

Map<String, Object> variant(String name, int bitrate) => {
  'content_type': 'video/mp4',
  'url': 'https://video.twimg.com/$name.mp4',
  'bitrate': bitrate,
};
