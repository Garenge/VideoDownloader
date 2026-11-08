import 'dart:convert';

Map<String, Object?> likedEntry(String id, {bool media = false}) => {
  'entryId': 'tweet-$id',
  'content': {
    'itemContent': {
      'tweet_results': {
        'result': {
          '__typename': 'Tweet',
          'rest_id': id,
          'core': {
            'user_results': {
              'result': {
                'core': {'screen_name': 'example'},
              },
            },
          },
          'legacy': {
            'full_text': 'Post $id',
            'created_at': 'Sun Nov 08 06:30:00 +0000 2026',
            'favorite_count': 12,
            if (media)
              'extended_entities': {
                'media': [
                  {'type': 'video'},
                ],
              },
          },
        },
      },
    },
  },
};

String likesFixture(
  List<Map<String, Object?>> entries, {
  String? cursor,
  bool terminated = false,
  String timeline = 'timeline_v2',
}) => jsonEncode({
  'data': {
    'user': {
      'result': {
        timeline: {
          'timeline': {
            'instructions': [
              {
                'type': 'TimelineAddEntries',
                'entries': [
                  ...entries,
                  if (cursor != null)
                    {
                      'content': {'cursorType': 'Bottom', 'value': cursor},
                    },
                ],
              },
              if (terminated)
                {'type': 'TimelineTerminateTimeline', 'direction': 'Bottom'},
            ],
          },
        },
      },
    },
  },
});

String likesEnvelope(String raw, {int status = 200}) => jsonEncode({
  'statusCode': status,
  'endpoint': 'https://x.com/i/api/graphql/example/Likes',
  'rawJson': raw,
});
