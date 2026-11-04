part of 'source_parser_service.dart';

Future<List<SourceResource>> _extractYouTubePublicResources(
  http.Client client,
  Uri pageUri,
) async {
  final oEmbedUri = Uri.https('www.youtube.com', '/oembed', {
    'url': pageUri.toString(),
    'format': 'json',
  });

  try {
    final response = await client
        .get(oEmbedUri, headers: const {'User-Agent': 'VideoDownloader/1.0'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 400) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      return const [];
    }

    final thumbnailUrl = decoded['thumbnail_url']?.toString();
    if (thumbnailUrl == null || thumbnailUrl.trim().isEmpty) {
      return const [];
    }

    final title = decoded['title']?.toString().trim();
    final authorName = decoded['author_name']?.toString().trim();
    final collector = _ResourceCollector(pageUri, SourcePlatform.youtube);
    collector.add(
      url: thumbnailUrl,
      type: SourceResourceType.image,
      title: _youtubeTitle(title),
      sizeHint: _youtubeSizeHint(authorName),
    );

    final videoId = VideoId.parseVideoId(pageUri.toString());
    if (videoId != null) {
      collector.add(
        url: pageUri.toString(),
        type: SourceResourceType.video,
        title: _youtubeVideoResourceTitle(title),
        sizeHint: _youtubeVideoSizeHint(authorName),
        youtubeVideoId: videoId,
      );
    }

    return collector.resources;
  } on FormatException {
    return const [];
  } on TimeoutException {
    return const [];
  } on Object {
    return const [];
  }
}

String _youtubeTitle(String? title) {
  if (title == null || title.isEmpty) {
    return 'YouTube 封面';
  }

  return 'YouTube 封面：$title';
}

String _youtubeSizeHint(String? authorName) {
  if (authorName == null || authorName.isEmpty) {
    return 'YouTube oEmbed';
  }

  return 'YouTube oEmbed · $authorName';
}

String _youtubeVideoResourceTitle(String? title) {
  if (title == null || title.isEmpty) {
    return 'YouTube 视频';
  }

  return 'YouTube 视频：$title';
}

String _youtubeVideoSizeHint(String? authorName) {
  if (authorName == null || authorName.isEmpty) {
    return 'YouTube 下载任务 · 点击加入下载队列';
  }

  return 'YouTube 下载任务 · $authorName · 点击加入下载队列';
}
