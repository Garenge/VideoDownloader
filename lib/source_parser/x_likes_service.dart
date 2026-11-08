import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'x_login_bridge.dart';

class XLikedPost {
  const XLikedPost({
    required this.id,
    required this.text,
    required this.author,
    required this.createdAt,
    required this.url,
    required this.replies,
    required this.reposts,
    required this.likes,
    required this.views,
    required this.mediaUrl,
  });

  final String id;
  final String text;
  final String author;
  final String? createdAt;
  final String? url;
  final String? replies;
  final String? reposts;
  final String? likes;
  final String? views;
  final String? mediaUrl;
}

class XLikesResponse {
  const XLikesResponse({
    required this.posts,
    required this.rawJson,
    required this.statusCode,
    required this.endpoint,
  });

  final List<XLikedPost> posts;
  final String rawJson;
  final int statusCode;
  final Uri endpoint;
}

class XLikesService {
  static final Uri _likesPage = Uri.parse('https://x.com/i/history/likes');

  void dispose() {}

  Future<XLikesResponse> fetchLikes() async {
    try {
      debugPrint(
        'lib/source_parser/x_likes_service.dart#fetchLikes: '
        'stage=loadLoggedInLikesPage',
      );
      final rawJson = await XLoginBridge.fetchLikesJson().timeout(
        const Duration(seconds: 20),
      );
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        throw XLikesException(decoded['error'] as String);
      }
      return XLikesResponse(
        posts: _decodePosts(decoded),
        rawJson: _prettyJson(rawJson),
        statusCode: 200,
        endpoint: _likesPage,
      );
    } on TimeoutException {
      debugPrint(
        'lib/source_parser/x_likes_service.dart#fetchLikes: '
        'stage=loadLoggedInLikesPage timeout=true',
      );
      throw const XLikesException('X 点赞页面加载超时，请确认已登录并检查网络');
    } on FormatException {
      throw const XLikesException('X 点赞页面返回的数据不是有效 JSON');
    }
  }

  List<XLikedPost> _decodePosts(Object? decoded) {
    final rawPosts = decoded is Map<String, dynamic>
        ? decoded['posts']
        : decoded;
    if (rawPosts is! List) return const [];
    return rawPosts
        .whereType<Map<String, dynamic>>()
        .map(_postFromJson)
        .toList();
  }

  XLikedPost _postFromJson(Map<String, dynamic> json) {
    return XLikedPost(
      id: '${json['id'] ?? ''}',
      text: '${json['text'] ?? ''}',
      author: '${json['author'] ?? '未知用户'}',
      createdAt: json['createdAt'] as String?,
      url: json['url'] as String?,
      replies: json['replies'] as String?,
      reposts: json['reposts'] as String?,
      likes: json['likes'] as String?,
      views: json['views'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
    );
  }

  String _prettyJson(String rawJson) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(rawJson));
    } on FormatException {
      return rawJson;
    }
  }
}

class XLikesException implements Exception {
  const XLikesException(this.message);

  final String message;

  @override
  String toString() => message;
}
