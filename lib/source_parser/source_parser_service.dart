import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'source_resource.dart';

class SourceParserService {
  SourceParserService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<SourceParseResult> parse(String input) async {
    final uri = Uri.parse(input.trim());
    final platform = _detectPlatform(uri);
    final response = await _fetchPage(uri);
    final pageUri = response.request?.url ?? uri;
    final document = html_parser.parse(response.body);
    final resources = _extractResources(document, pageUri, platform);

    return SourceParseResult(
      originalUrl: pageUri.toString(),
      platform: platform,
      resources: resources,
      message: resources.isEmpty ? '没有在网页源码中发现可直接下载的资源' : null,
    );
  }

  String? validate(String input) {
    final url = input.trim();
    if (url.isEmpty) {
      return '请先粘贴一个网页 URL';
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '请输入包含 http 或 https 的完整 URL';
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '当前仅支持 http / https 链接';
    }

    return null;
  }

  Future<http.Response> _fetchPage(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'User-Agent': 'VideoDownloader/1.0'})
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw SourceParserException('网页请求失败：HTTP ${response.statusCode}');
      }

      return response;
    } on SourceParserException {
      rethrow;
    } on TimeoutException {
      throw const SourceParserException('网页请求超时，请稍后重试');
    } on Object catch (error) {
      throw SourceParserException(
        'lib/source_parser/source_parser_service.dart#_fetchPage: 请求失败: $error',
      );
    }
  }

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
    _extractJsonLdResources(document, collector);

    return collector.resources;
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

  void _extractJsonLdResources(
    dom.Document document,
    _ResourceCollector collector,
  ) {
    final scripts = document.querySelectorAll(
      'script[type="application/ld+json"]',
    );
    for (final script in scripts) {
      final text = script.text.trim();
      if (text.isEmpty) {
        continue;
      }

      try {
        _collectJsonResource(jsonDecode(text), collector);
      } on FormatException {
        continue;
      }
    }
  }

  void _collectJsonResource(Object? value, _ResourceCollector collector) {
    if (value is List) {
      for (final item in value) {
        _collectJsonResource(item, collector);
      }
      return;
    }

    if (value is! Map) {
      return;
    }

    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      final item = entry.value;

      if (item is String) {
        _addJsonStringResource(key, item, collector);
      } else {
        _collectJsonResource(item, collector);
      }
    }
  }

  void _addJsonStringResource(
    String key,
    String value,
    _ResourceCollector collector,
  ) {
    if (key == 'image' || key == 'thumbnailurl') {
      collector.add(
        url: value,
        type: SourceResourceType.image,
        title: 'JSON-LD 图片',
        sizeHint: _extensionHint(value),
      );
    }

    if (key == 'contenturl' || key == 'embedurl') {
      final type = _typeFromUrlOrMime(value, null);
      collector.add(
        url: value,
        type: type,
        title: _titleForType(type),
        sizeHint: _extensionHint(value),
      );
    }
  }

  SourcePlatform _detectPlatform(Uri? uri) {
    final host = uri?.host.toLowerCase() ?? '';

    if (host.contains('douyin.com') || host.contains('iesdouyin.com')) {
      return SourcePlatform.douyin;
    }

    if (host == 'x.com' || host.endsWith('.x.com')) {
      return SourcePlatform.x;
    }

    if (host.contains('twitter.com')) {
      return SourcePlatform.x;
    }

    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return SourcePlatform.youtube;
    }

    if (host.contains('bilibili.com') || host == 'b23.tv') {
      return SourcePlatform.bilibili;
    }

    return SourcePlatform.other;
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

    return _looksDownloadable(content)
        ? _typeFromUrlOrMime(content, null)
        : null;
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

  bool _hasExtension(String value, Set<String> extensions) {
    return extensions.any((extension) => value.contains('.$extension'));
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
}

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
  }) {
    final resolvedUrl = _resolveUrl(url);
    if (resolvedUrl == null) {
      return;
    }

    final key = '${type.name}|$resolvedUrl';
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
