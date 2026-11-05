import 'source_resource.dart';

/// Accept only X attachment hosts and paths, excluding avatars and previews.
SourceResourceType? xMediaType(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return null;
  }
  if (uri.host == 'video.twimg.com' || uri.host.endsWith('.video.twimg.com')) {
    return uri.path.toLowerCase().endsWith('.mp4')
        ? SourceResourceType.video
        : null;
  }
  if (uri.host == 'pbs.twimg.com' && uri.path.startsWith('/media/')) {
    final format =
        uri.queryParameters['format'] ?? uri.path.split('.').last.toLowerCase();
    if (const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(format)) {
      return SourceResourceType.image;
    }
  }
  return null;
}

String originalXImageUrl(String value) {
  final uri = Uri.parse(value);
  final query = Map<String, String>.of(uri.queryParameters);
  final format = query.remove('format');
  final path = format != null && !uri.path.split('/').last.contains('.')
      ? '${uri.path}.$format'
      : uri.path;
  return uri
      .replace(path: path, queryParameters: {...query, 'name': 'orig'})
      .toString();
}
