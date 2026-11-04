import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' show VideoId;

import 'source_resource.dart';

part 'source_platform_detector.dart';
part 'source_common_resource_extractor.dart';
part 'source_resource_collector.dart';
part 'source_x_parser.dart';
part 'source_youtube_parser.dart';

class SourceParserService {
  SourceParserService({http.Client? client, bool? ownClient})
    : _client = client ?? http.Client(),
      _ownsClient = ownClient ?? (client == null);

  http.Client _client;
  bool _ownsClient;

  void replaceHttpClient(http.Client newClient) {
    if (_ownsClient) {
      _client.close();
    }

    _client = newClient;
    _ownsClient = true;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// 与网页解析共用（含 HTTP 代理等），可用于缩略图等需要一致网络栈的请求。
  http.Client get resourceHttpClient => _client;

  Future<SourceParseResult> parse(String input) async {
    final uri = Uri.parse(input.trim());
    final requestedPlatform = _detectPlatform(uri);
    final fallbackPlatformResources = await _extractPlatformResources(
      uri,
      requestedPlatform,
    );

    http.Response response;
    try {
      response = await _fetchPage(uri);
    } on SourceParserException catch (error) {
      if (fallbackPlatformResources.isEmpty) {
        rethrow;
      }

      return SourceParseResult(
        originalUrl: uri.toString(),
        platform: requestedPlatform,
        resources: fallbackPlatformResources,
        message: '网页请求失败，已保留平台下载任务：${error.message}',
      );
    }

    final pageUri = response.request?.url ?? uri;
    final platform = _detectPlatform(pageUri);
    final document = html_parser.parse(response.body);
    final commonResources = _extractResources(document, pageUri, platform);
    final platformResources = pageUri == uri && platform == requestedPlatform
        ? fallbackPlatformResources
        : await _extractPlatformResources(pageUri, platform);
    final resources = _mergeResources([
      ...platformResources,
      ...commonResources,
    ]);

    return SourceParseResult(
      originalUrl: pageUri.toString(),
      platform: platform,
      resources: resources,
      message: resources.isEmpty ? '没有在网页源码中发现可直接下载的资源' : null,
    );
  }

  Future<List<SourceResource>> _extractPlatformResources(
    Uri pageUri,
    SourcePlatform platform,
  ) async {
    return switch (platform) {
      SourcePlatform.youtube => _extractYouTubePublicResources(
        _client,
        pageUri,
      ),
      SourcePlatform.x => Future.value(_extractXResources(pageUri)),
      SourcePlatform.douyin ||
      SourcePlatform.bilibili ||
      SourcePlatform.other => Future.value(const []),
    };
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
}
