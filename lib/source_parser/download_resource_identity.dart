/// Keeps direct URLs exact while recognizing alternate YouTube video links.
String downloadResourceIdentity(String url, {String? youtubeVideoId}) {
  final videoId = youtubeVideoId ?? _youtubeVideoId(url);
  return videoId == null ? url : 'youtube:$videoId';
}

String? _youtubeVideoId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments;
  if (host == 'youtu.be' && segments.isNotEmpty) {
    return segments.first.isEmpty ? null : segments.first;
  }
  if (host != 'youtube.com' && !host.endsWith('.youtube.com')) return null;
  final queryId = uri.queryParameters['v'];
  if (uri.path == '/watch' && queryId != null && queryId.isNotEmpty) {
    return queryId;
  }
  if (segments.length >= 2 &&
      const {'shorts', 'embed', 'live'}.contains(segments.first)) {
    return segments[1].isEmpty ? null : segments[1];
  }
  return null;
}
