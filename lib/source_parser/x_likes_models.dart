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
    this.hasMedia = false,
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
  final bool hasMedia;
}

class XLikesResponse {
  const XLikesResponse({
    required this.posts,
    required this.rawJson,
    required this.statusCode,
    required this.endpoint,
    this.nextCursor,
  });

  final List<XLikedPost> posts;
  final String rawJson;
  final int statusCode;
  final Uri endpoint;
  final String? nextCursor;
}
