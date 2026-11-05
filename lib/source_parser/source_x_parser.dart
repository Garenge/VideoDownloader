part of 'source_parser_service.dart';

extension _XPlatformParsing on SourceParserService {
  Future<List<SourceResource>> _extractXPlatformResources(Uri pageUri) async {
    if (_normalizedXStatusUri(pageUri) == null) return const [];
    try {
      return await _xPublicResolver.resolve(_client, pageUri);
    } on Object catch (error) {
      debugPrint(
        'lib/source_parser/source_x_parser.dart#_extractXPlatformResources: '
        '公开媒体解析失败，保留视频任务回退：$error',
      );
      return _extractXResources(pageUri);
    }
  }
}

List<SourceResource> _extractXResources(Uri pageUri) {
  final normalizedStatusUri = _normalizedXStatusUri(pageUri);
  if (normalizedStatusUri == null) {
    return const [];
  }

  final collector = _ResourceCollector(normalizedStatusUri, SourcePlatform.x);
  collector.add(
    url: normalizedStatusUri.toString(),
    type: SourceResourceType.video,
    title: _xVideoResourceTitle(normalizedStatusUri),
    sizeHint: _xVideoSizeHint(normalizedStatusUri),
    requiresYtDlp: true,
  );
  return collector.resources;
}

Uri? _normalizedXStatusUri(Uri pageUri) {
  final statusId = _xStatusId(pageUri);
  if (statusId == null) {
    return null;
  }

  final handle = _xHandle(pageUri);
  final path = handle == null
      ? '/i/status/$statusId'
      : '/$handle/status/$statusId';
  return Uri(
    scheme: pageUri.scheme.isEmpty ? 'https' : pageUri.scheme,
    host: pageUri.host,
    path: path,
  );
}

String? _xStatusId(Uri pageUri) {
  final segments = pageUri.pathSegments.where((segment) => segment.isNotEmpty);
  final normalizedSegments = segments.toList();
  final statusIndex = normalizedSegments.indexOf('status');
  if (statusIndex < 0 || statusIndex + 1 >= normalizedSegments.length) {
    return null;
  }

  final statusId = normalizedSegments[statusIndex + 1];
  if (!RegExp(r'^\d+$').hasMatch(statusId)) {
    return null;
  }
  return statusId;
}

String? _xHandle(Uri pageUri) {
  final segments = pageUri.pathSegments.where((segment) => segment.isNotEmpty);
  final normalizedSegments = segments.toList();
  if (normalizedSegments.isEmpty) {
    return null;
  }

  final candidate = normalizedSegments.first.trim();
  if (candidate.isEmpty || candidate == 'i' || candidate == 'status') {
    return null;
  }
  return candidate;
}

String _xVideoResourceTitle(Uri pageUri) {
  final statusId = _xStatusId(pageUri);
  final handle = _xHandle(pageUri);
  if (handle != null && statusId != null) {
    return 'X 视频：@$handle/$statusId';
  }
  if (statusId != null) {
    return 'X 视频：$statusId';
  }
  return 'X 视频';
}

String _xVideoSizeHint(Uri pageUri) {
  final host = pageUri.host.toLowerCase();
  final siteLabel = host.contains('twitter.com') ? 'Twitter/X' : 'X';
  return '$siteLabel 下载任务 · 使用 yt-dlp 加入下载队列';
}
