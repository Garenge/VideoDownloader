part of 'source_parser_service.dart';

List<SourceResource> _extractResources(
  dom.Document document,
  Uri pageUri,
  SourcePlatform platform,
) {
  final collector = _ResourceCollector(pageUri, platform);

  _extractImageElements(document, collector);
  _extractVideoElements(document, collector);
  _extractMetaResources(document, collector);
  _extractLinkedResources(document, collector);
  _extractDataAttributeResources(document, collector);
  _extractJsonLdResources(document, collector);
  _extractInlineScriptResources(document, collector);

  return collector.resources;
}

List<SourceResource> _mergeResources(List<SourceResource> resources) {
  final seenKeys = <String>{};
  final mergedResources = <SourceResource>[];

  for (final resource in resources) {
    final key = '${resource.type.name}|${resource.url}';
    if (seenKeys.add(key)) {
      mergedResources.add(resource);
    }
  }

  return mergedResources;
}

void _extractImageElements(
  dom.Document document,
  _ResourceCollector collector,
) {
  for (final element in document.querySelectorAll('img')) {
    collector.add(
      url: element.attributes['src'],
      type: SourceResourceType.image,
      title: _firstText([
        element.attributes['alt'],
        element.attributes['title'],
        '图片资源',
      ]),
      sizeHint: _imageSizeHint(element),
    );
    _addSrcSet(
      element.attributes['srcset'],
      SourceResourceType.image,
      collector,
    );
  }

  for (final element in document.querySelectorAll('picture source')) {
    _addSrcSet(
      element.attributes['srcset'],
      SourceResourceType.image,
      collector,
    );
  }
}

void _extractVideoElements(
  dom.Document document,
  _ResourceCollector collector,
) {
  for (final element in document.querySelectorAll('video')) {
    collector.add(
      url: element.attributes['src'],
      type: SourceResourceType.video,
      title: _firstText([element.attributes['title'], '视频资源']),
      sizeHint: _videoSizeHint(element),
    );
    collector.add(
      url: element.attributes['poster'],
      type: SourceResourceType.image,
      title: '视频封面',
      sizeHint: 'poster',
    );
  }

  for (final element in document.querySelectorAll('video source, source')) {
    final src = element.attributes['src'];
    final type = _typeFromUrlOrMime(src, element.attributes['type']);
    collector.add(
      url: src,
      type: type,
      title: _titleForType(type),
      sizeHint: element.attributes['type'] ?? _extensionHint(src),
    );
  }
}

void _extractMetaResources(
  dom.Document document,
  _ResourceCollector collector,
) {
  for (final element in document.querySelectorAll('meta')) {
    final key = _metaKey(element);
    final content = element.attributes['content'];
    if (key == null || content == null) {
      continue;
    }

    final type = _metaResourceType(key, content);
    if (type == null) {
      continue;
    }

    collector.add(
      url: content,
      type: type,
      title: _metaTitle(key, type),
      sizeHint: _extensionHint(content),
    );
  }
}

void _extractLinkedResources(
  dom.Document document,
  _ResourceCollector collector,
) {
  for (final element in document.querySelectorAll('[src], [href]')) {
    final rawUrl = element.attributes['src'] ?? element.attributes['href'];
    final type = _typeFromUrlOrMime(rawUrl, element.attributes['type']);

    if (type == SourceResourceType.other && !_looksDownloadable(rawUrl)) {
      continue;
    }

    collector.add(
      url: rawUrl,
      type: type,
      title: _titleForType(type),
      sizeHint: element.attributes['type'] ?? _extensionHint(rawUrl),
    );
  }
}

void _extractDataAttributeResources(
  dom.Document document,
  _ResourceCollector collector,
) {
  for (final element in document.querySelectorAll('*')) {
    for (final entry in element.attributes.entries) {
      final key = entry.key.toString().toLowerCase();
      final value = entry.value.trim();
      if (value.isEmpty) {
        continue;
      }
      if (!_looksLikeMediaAttribute(key, value)) {
        continue;
      }

      final type = _typeFromUrlOrMime(value, key);
      collector.add(
        url: value,
        type: type,
        title: _titleForAttribute(key, type),
        sizeHint: _attributeSizeHint(key, value),
      );
    }
  }
}

void _extractJsonLdResources(
  dom.Document document,
  _ResourceCollector collector,
) {
  final scripts = document.querySelectorAll('script');
  for (final script in scripts) {
    final type = script.attributes['type']?.toLowerCase();
    if (type != 'application/ld+json' && !_looksJsonScriptType(type)) {
      continue;
    }

    final text = script.text.trim();
    if (text.isEmpty) {
      continue;
    }
    final normalizedText = _normalizeEscapedScriptText(text);

    try {
      _collectJsonResource(
        jsonDecode(normalizedText),
        collector,
        scriptType: type ?? 'application/json',
      );
    } on FormatException {
      continue;
    }
  }
}

void _extractInlineScriptResources(
  dom.Document document,
  _ResourceCollector collector,
) {
  for (final script in document.querySelectorAll('script')) {
    final type = script.attributes['type']?.toLowerCase();
    if (type == 'application/ld+json') {
      continue;
    }

    final text = script.text.trim();
    if (text.isEmpty) {
      continue;
    }
    final normalizedText = _normalizeEscapedScriptText(text);

    final scriptBaseUrls = _collectScriptBaseUrls(normalizedText);

    for (final match in _inlineMediaKeyValuePattern.allMatches(normalizedText)) {
      final key = (match.group(1) ?? '').toLowerCase();
      final rawUrl = match.group(2);
      if (rawUrl == null || rawUrl.trim().isEmpty) {
        continue;
      }
      final resourceType = _typeFromUrlOrMime(rawUrl, key);
      collector.add(
        url: rawUrl,
        type: resourceType,
        title: _titleForScriptKey(key, resourceType),
        sizeHint: 'inline script key',
      );
    }

    for (final match in _inlineRelativeMediaKeyValuePattern.allMatches(
      normalizedText,
    )) {
      final key = (match.group(1) ?? '').toLowerCase();
      final rawPath = match.group(2);
      if (rawPath == null || rawPath.trim().isEmpty) {
        continue;
      }
      for (final baseUrl in scriptBaseUrls) {
        final combinedUrl = _combineScriptBaseAndPath(baseUrl, rawPath);
        if (combinedUrl == null) {
          continue;
        }
        final resourceType = _typeFromUrlOrMime(combinedUrl, key);
        collector.add(
          url: combinedUrl,
          type: resourceType,
          title: _titleForScriptKey(key, resourceType),
          sizeHint: 'inline script joined',
        );
      }
    }

    final seenUrls = <String>{};
    for (final match in _inlineMediaUrlPattern.allMatches(normalizedText)) {
      final rawUrl = match.group(1);
      if (rawUrl == null || !seenUrls.add(rawUrl)) {
        continue;
      }
      final resourceType = _typeFromUrlOrMime(rawUrl, null);
      collector.add(
        url: rawUrl,
        type: resourceType,
        title: _titleForScriptUrl(rawUrl, resourceType),
        sizeHint: 'inline script',
      );
    }
  }
}

void _collectJsonResource(
  Object? value,
  _ResourceCollector collector, {
  String scriptType = 'application/ld+json',
  String? currentKey,
  List<String> keyPath = const [],
}) {
  if (value is String) {
    final key = currentKey?.trim().toLowerCase();
    if (key == null || key.isEmpty) {
      return;
    }
    _addJsonStringResource(
      key,
      _normalizeEscapedScriptText(value),
      collector,
      scriptType: scriptType,
      keyPath: keyPath,
    );
    return;
  }

  if (value is List) {
    for (final item in value) {
      _collectJsonResource(
        item,
        collector,
        scriptType: scriptType,
        currentKey: currentKey,
        keyPath: keyPath,
      );
    }
    return;
  }

  if (value is! Map) {
    return;
  }

  for (final entry in value.entries) {
    final key = entry.key.toString().toLowerCase();
    final item = entry.value;
    final nextPath = [...keyPath, key];

    _collectJsonResource(
      item,
      collector,
      scriptType: scriptType,
      currentKey: key,
      keyPath: nextPath,
    );
  }
}

void _addJsonStringResource(
  String key,
  String value,
  _ResourceCollector collector, {
  required String scriptType,
  required List<String> keyPath,
}
) {
  if (_isJsonImageKey(key) || _isGenericImageValueKey(key, keyPath)) {
    collector.add(
      url: value,
      type: SourceResourceType.image,
      title: _jsonImageTitle(scriptType),
      sizeHint: _jsonSizeHint(scriptType, value),
    );
  }

  if (_isJsonVideoKey(key) || _isGenericMediaValueKey(key, keyPath, value)) {
    final type = _typeFromUrlOrMime(value, null);
    collector.add(
      url: value,
      type: type,
      title: _jsonVideoTitle(scriptType, key, type),
      sizeHint: _jsonSizeHint(scriptType, value),
    );
  }
}

void _addSrcSet(
  String? srcSet,
  SourceResourceType type,
  _ResourceCollector collector,
) {
  if (srcSet == null || srcSet.trim().isEmpty) {
    return;
  }

  for (final part in srcSet.split(',')) {
    final url = part.trim().split(RegExp(r'\s+')).firstOrNull;
    collector.add(
      url: url,
      type: type,
      title: _titleForType(type),
      sizeHint: 'srcset',
    );
  }
}

String? _metaKey(dom.Element element) {
  return element.attributes['property']?.toLowerCase() ??
      element.attributes['name']?.toLowerCase();
}

SourceResourceType? _metaResourceType(String key, String content) {
  if (key.contains('image')) {
    return SourceResourceType.image;
  }

  if (key.contains('video') || key.contains('player:stream')) {
    return SourceResourceType.video;
  }

  return _looksDownloadable(content) ? _typeFromUrlOrMime(content, null) : null;
}

SourceResourceType _typeFromUrlOrMime(String? url, String? mime) {
  final value = '${mime ?? ''} ${url ?? ''}'.toLowerCase();

  if (value.contains('image/') || _hasExtension(value, _imageExtensions)) {
    return SourceResourceType.image;
  }

  if (value.contains('video/') || _hasExtension(value, _videoExtensions)) {
    return SourceResourceType.video;
  }

  return SourceResourceType.other;
}

bool _looksDownloadable(String? url) {
  if (url == null) {
    return false;
  }

  final value = url.toLowerCase();
  return _hasExtension(value, {
    ..._imageExtensions,
    ..._videoExtensions,
    ..._otherExtensions,
  });
}

bool _looksLikeMediaAttribute(String key, String value) {
  if (!_looksDownloadable(value) && !_looksMediaMimeOrKeyword(key, value)) {
    return false;
  }

  return key.startsWith('data-') ||
      key.contains('video') ||
      key.contains('audio') ||
      key.contains('poster') ||
      key.contains('cover') ||
      key.contains('thumb') ||
      key.contains('src') ||
      key.contains('url') ||
      key.contains('play');
}

String _normalizeEscapedScriptText(String text) {
  return text
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u002F', '/')
      .replaceAll(r'\u002f', '/');
}

bool _looksJsonScriptType(String? type) {
  if (type == null || type.isEmpty) {
    return false;
  }
  return type == 'application/json' ||
      type == 'text/json' ||
      type == 'application/vnd.api+json' ||
      type.endsWith('+json');
}

bool _looksMediaMimeOrKeyword(String key, String value) {
  final lowered = '$key $value'.toLowerCase();
  return lowered.contains('mpegurl') ||
      lowered.contains('dash+xml') ||
      lowered.contains('.m3u8') ||
      lowered.contains('.mpd') ||
      lowered.contains('.mp4') ||
      lowered.contains('.webm') ||
      lowered.contains('.jpg') ||
      lowered.contains('.png');
}

bool _hasExtension(String value, Set<String> extensions) {
  return extensions.any((extension) => value.contains('.$extension'));
}

String _attributeSizeHint(String key, String value) {
  final loweredKey = key.toLowerCase();
  if (loweredKey.contains('poster') ||
      loweredKey.contains('cover') ||
      loweredKey.contains('thumb')) {
    return 'data attribute poster';
  }
  if (loweredKey.contains('m3u8') || value.toLowerCase().contains('.m3u8')) {
    return 'data attribute m3u8';
  }
  if (loweredKey.contains('mpd') || value.toLowerCase().contains('.mpd')) {
    return 'data attribute mpd';
  }
  return 'data attribute';
}

String _jsonSizeHint(String scriptType, String value) {
  if (scriptType == 'application/ld+json') {
    return _extensionHint(value);
  }
  return 'json script · ${_extensionHint(value)}';
}

String _imageSizeHint(dom.Element element) {
  final width = element.attributes['width'];
  final height = element.attributes['height'];

  if (width != null && height != null) {
    return '$width x $height';
  }

  return 'image';
}

String _videoSizeHint(dom.Element element) {
  return element.attributes['type'] ?? 'video';
}

String _extensionHint(String? url) {
  if (url == null) {
    return 'resource';
  }

  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  final extension = path.split('.').lastOrNull;
  if (extension == null || extension == path || extension.length > 8) {
    return 'resource';
  }

  return extension.toUpperCase();
}

String _firstText(List<String?> values) {
  return values.firstWhere(
    (value) => value != null && value.trim().isNotEmpty,
  )!;
}

String _metaTitle(String key, SourceResourceType type) {
  if (key.startsWith('og:')) {
    return 'Open Graph ${type.displayName}';
  }

  if (key.startsWith('twitter:')) {
    return 'Twitter ${type.displayName}';
  }

  return _titleForType(type);
}

String _titleForType(SourceResourceType type) {
  return switch (type) {
    SourceResourceType.video => '视频资源',
    SourceResourceType.image => '图片资源',
    SourceResourceType.other => '文件资源',
  };
}

String _titleForAttribute(String key, SourceResourceType type) {
  final loweredKey = key.toLowerCase();
  if (loweredKey.contains('poster') ||
      loweredKey.contains('cover') ||
      loweredKey.contains('thumb')) {
    return '播放器封面';
  }
  if (loweredKey.contains('video') ||
      loweredKey.contains('src') ||
      loweredKey.contains('play')) {
    return '播放器资源';
  }
  return _titleForType(type);
}

String _titleForScriptUrl(String rawUrl, SourceResourceType type) {
  final lowered = rawUrl.toLowerCase();
  if (lowered.contains('.m3u8') || lowered.contains('.mpd')) {
    return '脚本播放器资源';
  }
  if (type == SourceResourceType.image) {
    return '脚本图片资源';
  }
  return _titleForType(type);
}

String _titleForScriptKey(String key, SourceResourceType type) {
  if (_isCoverLikeKey(key)) {
    return '脚本封面资源';
  }
  if (_isPlayerLikeKey(key) || key.contains('manifest')) {
    return '脚本播放器资源';
  }
  return _titleForType(type);
}

bool _isJsonImageKey(String key) {
  return key == 'image' ||
      key == 'thumbnailurl' ||
      key == 'thumbnail_url' ||
      key == 'cover' ||
      key == 'coverurl' ||
      key == 'cover_url' ||
      key == 'poster' ||
      key == 'posterurl' ||
      key == 'poster_url';
}

bool _isJsonVideoKey(String key) {
  return key == 'contenturl' ||
      key == 'content_url' ||
      key == 'embedurl' ||
      key == 'embed_url' ||
      key == 'playurl' ||
      key == 'play_url' ||
      key == 'playaddr' ||
      key == 'play_addr' ||
      key == 'videourl' ||
      key == 'video_url' ||
      key == 'hlsurl' ||
      key == 'hls_url' ||
      key == 'dashurl' ||
      key == 'dash_url' ||
      key == 'manifesturl' ||
      key == 'manifest_url' ||
      key == 'streamurl' ||
      key == 'stream_url' ||
      key == 'playbackurl' ||
      key == 'playback_url' ||
      key == 'src';
}

bool _isGenericMediaValueKey(String key, List<String> keyPath, String value) {
  if (!_looksDownloadable(value) && !_looksMediaMimeOrKeyword(key, value)) {
    return false;
  }

  if (key != 'url' && key != 'src' && key != 'file' && key != 'path') {
    return false;
  }

  return keyPath.any(_isMediaContextKey);
}

bool _isGenericImageValueKey(String key, List<String> keyPath) {
  if (key != 'url' && key != 'src' && key != 'file' && key != 'path') {
    return false;
  }

  return keyPath.any(_isImageContextKey);
}

String _jsonImageTitle(String scriptType) {
  return scriptType == 'application/ld+json' ? 'JSON-LD 图片' : 'JSON 图片资源';
}

String _jsonVideoTitle(
  String scriptType,
  String key,
  SourceResourceType type,
) {
  if (scriptType == 'application/ld+json') {
    return _titleForType(type);
  }
  if (_isPlayerLikeKey(key) || key.contains('manifest')) {
    return 'JSON 播放器资源';
  }
  return 'JSON 视频资源';
}

bool _isPlayerLikeKey(String key) {
  return key.contains('play') ||
      key.contains('video') ||
      key.contains('stream') ||
      key.contains('hls') ||
      key.contains('dash') ||
      key.contains('manifest') ||
      key.contains('source') ||
      key.contains('playlist');
}

bool _isCoverLikeKey(String key) {
  return key.contains('cover') ||
      key.contains('poster') ||
      key.contains('thumb') ||
      key.contains('image');
}

bool _isMediaContextKey(String key) {
  return _isPlayerLikeKey(key) ||
      key.contains('source') ||
      key.contains('sources') ||
      key.contains('playlist') ||
      key.contains('streams') ||
      key.contains('medialist') ||
      key.contains('media_list') ||
      key.contains('episode') ||
      key.contains('episodes') ||
      key.contains('quality') ||
      key.contains('qualities') ||
      key.contains('representation') ||
      key.contains('representations') ||
      key.contains('playinfo') ||
      key.contains('play_info');
}

bool _isImageContextKey(String key) {
  return _isCoverLikeKey(key) ||
      key.contains('gallery') ||
      key.contains('preview');
}

const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'avif',
  'bmp',
  'svg',
};

const _videoExtensions = {'mp4', 'webm', 'mov', 'm4v', 'm3u8', 'mpd'};

const _otherExtensions = {'zip', 'pdf', 'json', 'xml', 'txt'};

final _inlineMediaUrlPattern = RegExp(
  r'''["']((?:https?:)?//[^"'\\\s]+\.(?:m3u8|mpd|mp4|webm|mov|m4v|jpg|jpeg|png|webp)(?:\?[^"'\\\s]*)?)["']''',
  caseSensitive: false,
);

final _inlineMediaKeyValuePattern = RegExp(
  r'''(?:"|')?(playUrl|play_url|playAddr|play_addr|videoUrl|video_url|hlsUrl|hls_url|dashUrl|dash_url|manifestUrl|manifest_url|streamUrl|stream_url|playbackUrl|playback_url|cover|coverUrl|cover_url|poster|posterUrl|poster_url|thumbnailUrl|thumbnail_url|src|url|file|path)(?:"|')?\s*[:=]\s*(?:"|')((?:https?:)?//[^"'\\\s]+|/[^"'\\\s]+?\.(?:m3u8|mpd|mp4|webm|mov|m4v|jpg|jpeg|png|webp)(?:\?[^"'\\\s]*)?)(?:"|')''',
  caseSensitive: false,
);

final _inlineRelativeMediaKeyValuePattern = RegExp(
  r'''(?:"|')?(playUrl|play_url|playAddr|play_addr|videoUrl|video_url|hlsUrl|hls_url|dashUrl|dash_url|manifestUrl|manifest_url|streamUrl|stream_url|playbackUrl|playback_url|src|url|file|path)(?:"|')?\s*[:=]\s*(?:"|')([^"'\\\s]+\.(?:m3u8|mpd|mp4|webm|mov|m4v)(?:\?[^"'\\\s]*)?)(?:"|')''',
  caseSensitive: false,
);

final _inlineBaseUrlPattern = RegExp(
  r'''(?:"|')?(baseUrl|base_url|cdnHost|cdn_host|mediaHost|media_host|hostUrl|host_url)(?:"|')?\s*[:=]\s*(?:"|')((?:https?:)?//[^"'\\\s]+)(?:"|')''',
  caseSensitive: false,
);

Set<String> _collectScriptBaseUrls(String text) {
  final results = <String>{};
  for (final match in _inlineBaseUrlPattern.allMatches(text)) {
    final raw = match.group(2);
    if (raw == null || raw.trim().isEmpty) {
      continue;
    }
    results.add(raw.trim());
  }
  return results;
}

String? _combineScriptBaseAndPath(String baseUrl, String rawPath) {
  final normalizedBase = baseUrl.trim();
  final normalizedPath = rawPath.trim();
  if (normalizedBase.isEmpty || normalizedPath.isEmpty) {
    return null;
  }
  if (normalizedPath.startsWith('http://') ||
      normalizedPath.startsWith('https://') ||
      normalizedPath.startsWith('//')) {
    return normalizedPath;
  }
  final baseUri = Uri.tryParse(normalizedBase);
  if (baseUri == null) {
    return null;
  }
  return baseUri.resolve(normalizedPath).toString();
}
