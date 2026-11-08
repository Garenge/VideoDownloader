import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/x_likes_parser.dart';
import 'fixtures/x_likes_fixture.dart';

void main() {
  final endpoint = Uri.parse('https://x.com/i/api/graphql/example/Likes');
  test(
    'decodes media, author, dates and cursor and removes duplicate posts',
    () {
      final response = parseXLikesResponse(
        likesFixture([
          likedEntry('123', media: true),
          likedEntry('123', media: true),
          likedEntry('456'),
        ], cursor: 'next'),
        endpoint: endpoint,
      );
      expect(response.posts.map((post) => post.id), ['123', '456']);
      final post = response.posts.first;
      expect(post.author, '@example');
      expect(post.hasMedia, isTrue);
      expect(post.createdAt, '2026-11-08T06:30:00.000Z');
      expect(post.url, 'https://x.com/i/status/123');
      expect(post.likes, '12');
      expect(response.posts.last.hasMedia, isFalse);
      expect(response.nextCursor, 'next');
    },
  );
  test(
    'supports timeline path and stops on repeated cursor or termination',
    () {
      expect(
        parseXLikesResponse(
          likesFixture([], timeline: 'timeline'),
          endpoint: endpoint,
        ).posts,
        isEmpty,
      );
      expect(
        parseXLikesResponse(
          likesFixture([], cursor: 'same'),
          endpoint: endpoint,
          requestedCursor: 'same',
        ).nextCursor,
        isNull,
      );
      expect(
        parseXLikesResponse(
          likesFixture([], cursor: 'next', terminated: true),
          endpoint: endpoint,
        ).nextCursor,
        isNull,
      );
    },
  );
  test('unwraps visibility results and skips unavailable posts in modules', () {
    final entry = likedEntry('123');
    final content = (entry['content'] as Map)['itemContent'] as Map;
    final results = content['tweet_results'] as Map;
    final tweet = results['result'] as Map;
    tweet['note_tweet'] = {
      'note_tweet_results': {
        'result': {'text': 'Full note'},
      },
    };
    results['result'] = {
      '__typename': 'TweetWithVisibilityResults',
      'tweet': tweet,
    };
    final module = {
      'content': {
        'items': [
          {
            'item': {'itemContent': content},
          },
          {
            'item': {
              'itemContent': {
                'tweet_results': {
                  'result': {'__typename': 'TweetUnavailable'},
                },
              },
            },
          },
        ],
      },
    };
    final response = parseXLikesResponse(
      likesFixture([module]),
      endpoint: endpoint,
    );
    expect(response.posts.single.text, 'Full note');
  });
  test('rejects API errors instead of treating them as an empty list', () {
    expect(
      () => parseXLikesResponse(
        jsonEncode({
          'errors': [
            {'code': 32},
          ],
        }),
        endpoint: endpoint,
      ),
      throwsFormatException,
    );
  });
}
