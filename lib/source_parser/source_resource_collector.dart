part of 'source_parser_service.dart';

class _ResourceCollector {
  _ResourceCollector(this.pageUri, this.platform);

  final Uri pageUri;
  final SourcePlatform platform;
  final List<SourceResource> resources = [];
  final Set<String> _seenKeys = {};

  void add({
    required String? url,
    required SourceResourceType type,
    required String title,
    required String sizeHint,
    String? youtubeVideoId,
    bool requiresYtDlp = false,
  }) {
    final resolvedUrl = _resolveUrl(url);
    if (resolvedUrl == null) {
      return;
    }

    final key =
        '${type.name}|$resolvedUrl|${youtubeVideoId ?? ''}|$requiresYtDlp';
    if (!_seenKeys.add(key)) {
      return;
    }

    resources.add(
      SourceResource(
        title: title,
        url: resolvedUrl,
        type: type,
        platform: platform,
        host: Uri.tryParse(resolvedUrl)?.host ?? pageUri.host,
        sizeHint: sizeHint,
        youtubeVideoId: youtubeVideoId,
        requiresYtDlp: requiresYtDlp,
      ),
    );
  }

  String? _resolveUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final trimmed = value.trim();
    if (trimmed.startsWith('data:') || trimmed.startsWith('blob:')) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return null;
    }

    return pageUri.resolveUri(uri).toString();
  }
}
