import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  for (final mixed in [false, true]) {
    test(
      'X authenticated photos with mixed=$mixed retain attachment order',
      () async {
        final parser = SourceParserService(
          useNativeDownloads: true,
          xSessionResolver: (_) async => [
            'https://pbs.twimg.com/media/first.jpg?name=small',
            'https://pbs.twimg.com/media/second?format=png&name=large',
            'https://pbs.twimg.com/media/first.jpg?name=large',
            if (mixed) 'https://video.twimg.com/clip.mp4',
            'https://pbs.twimg.com/profile_images/avatar.jpg',
            'https://pbs.twimg.com/tweet_video_thumb/cover.jpg',
            'https://pbs.twimg.com.evil.example/media/bad.jpg',
            'https://pbs.twimg.com/media/bad.html',
            'https://video.twimg.com/playlist.m3u8',
            'http://pbs.twimg.com/media/insecure.jpg',
          ],
          client: MockClient(
            (_) async => fail('Session must supply attachments'),
          ),
        );
        addTearDown(parser.dispose);
        final result = await parser.parse('https://x.com/demo/status/123');
        expect(result.resources.map((r) => r.url), [
          'https://pbs.twimg.com/media/first.jpg?name=orig',
          'https://pbs.twimg.com/media/second.png?name=orig',
          if (mixed) 'https://video.twimg.com/clip.mp4',
        ]);
        expect(result.resourcesOf(SourceResourceType.image), hasLength(2));
        expect(
          result.resourcesOf(SourceResourceType.video),
          hasLength(mixed ? 1 : 0),
        );
      },
    );
  }
}
