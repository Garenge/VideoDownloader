import 'dart:convert';

import 'x_likes_models.dart';

XLikesResponse parseXLikesResponse(
  String raw, {
  required Uri endpoint,
  String? requestedCursor,
}) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final data = decoded['data'] as Map<String, dynamic>?;
  final user = data?['user']?['result'];
  final instructions =
      user?['timeline_v2']?['timeline']?['instructions'] ??
      user?['timeline']?['timeline']?['instructions'];
  if (instructions is! List) {
    throw const FormatException('Missing X likes timeline');
  }
  final posts = <String, XLikedPost>{};
  String? cursor;
  var terminated = false;
  for (final instruction in instructions.whereType<Map>()) {
    if (instruction['type'] == 'TimelineTerminateTimeline' &&
        instruction['direction'] == 'Bottom') {
      terminated = true;
    }
    final entries =
        instruction['entries'] ??
        (instruction['entry'] == null ? [] : [instruction['entry']]);
    if (entries is! List) continue;
    for (final entry in entries.whereType<Map>()) {
      final content = entry['content'];
      if (content is! Map) continue;
      if (content['cursorType'] == 'Bottom') {
        cursor = content['value'] as String?;
      }
      _addPost(content['itemContent'], posts);
      final items = content['items'];
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          _addPost(item['item']?['itemContent'], posts);
        }
      }
    }
  }
  return XLikesResponse(
    posts: posts.values.toList(),
    rawJson: const JsonEncoder.withIndent('  ').convert(decoded),
    statusCode: 200,
    endpoint: endpoint,
    nextCursor: terminated || cursor == requestedCursor || cursor == ''
        ? null
        : cursor,
  );
}

void _addPost(Object? content, Map<String, XLikedPost> posts) {
  if (content is! Map) return;
  var result = content['tweet_results']?['result'];
  if (result is! Map) return;
  if (result['__typename'] == 'TweetWithVisibilityResults') {
    result = result['tweet'];
  }
  if (result is! Map || result['legacy'] is! Map) return;
  final legacy = result['legacy'] as Map;
  final id = result['rest_id'] ?? legacy['id_str'];
  if (id is! String || !RegExp(r'^\d+$').hasMatch(id)) return;
  final author = result['core']?['user_results']?['result'];
  final handle =
      author?['core']?['screen_name'] ?? author?['legacy']?['screen_name'];
  final media =
      legacy['extended_entities']?['media'] ?? legacy['entities']?['media'];
  final attachments = media is List ? media.whereType<Map>().toList() : <Map>[];
  posts[id] = XLikedPost(
    id: id,
    text:
        '${result['note_tweet']?['note_tweet_results']?['result']?['text'] ?? legacy['full_text'] ?? ''}',
    author: handle is String && handle.isNotEmpty ? '@$handle' : '未知用户',
    createdAt: _createdAt(legacy['created_at']),
    url: 'https://x.com/i/status/$id',
    replies: legacy['reply_count']?.toString(),
    reposts: legacy['retweet_count']?.toString(),
    likes: legacy['favorite_count']?.toString(),
    views: result['views']?['count']?.toString(),
    mediaUrl: attachments.isEmpty
        ? null
        : attachments.first['media_url_https'] as String?,
    hasMedia: attachments.isNotEmpty,
  );
}

String? _createdAt(Object? raw) {
  if (raw is! String) return null;
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso.toIso8601String();
  final parts = raw.split(' ');
  if (parts.length != 6) return raw;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months.indexOf(parts[1]) + 1;
  if (month == 0) return raw;
  final zone = parts[4];
  if (!RegExp(r'^[+-]\d{4}$').hasMatch(zone)) return raw;
  return DateTime.tryParse(
        '${parts[5]}-${month.toString().padLeft(2, '0')}-${parts[2].padLeft(2, '0')}T${parts[3]}${zone.substring(0, 3)}:${zone.substring(3)}',
      )?.toIso8601String() ??
      raw;
}
