import 'dart:convert';

import 'package:http/http.dart' as http;

import '../source_resource.dart';
import 'ios_media_bridge.dart';

/// 直接请求 X 的公开嵌入接口，不通过第三方解析服务。
class XPublicVideoResolver {
  XPublicVideoResolver({
    Future<String> Function(String)? tokenGenerator,
    Duration requestTimeout = const Duration(seconds: 20),
  }) : _tokenGenerator = tokenGenerator ?? const IosMediaBridge().xToken,
       _requestTimeout = requestTimeout;

  final Future<String> Function(String) _tokenGenerator;
  final Duration _requestTimeout;

  Future<List<SourceResource>> resolve(http.Client client, Uri page) async {
    final match = RegExp(r'/status/(\d+)').firstMatch(page.path);
    if (match == null) {
      throw const SourceParserException('请输入 X / Twitter 帖子详情链接');
    }
    final id = match.group(1)!;
    final token = await _tokenGenerator(id);
    final response = await client
        .get(
          Uri.https('cdn.syndication.twimg.com', '/tweet-result', {
            'id': id,
            'token': token,
            'lang': 'en',
          }),
          headers: const {'User-Agent': 'Googlebot'},
        )
        .timeout(_requestTimeout);
    if (response.statusCode == 429) {
      throw const SourceParserException('X 请求过于频繁，请稍后重试');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SourceParserException('X 拒绝访问，请通过右上角账号入口登录 X 后重试。');
    }
    if (response.statusCode != 200) {
      throw SourceParserException('X 公开视频解析失败：HTTP ${response.statusCode}');
    }
    return _extract(jsonDecode(response.body), id);
  }

  List<SourceResource> _extract(Object? decoded, String id) {
    if (decoded is! Map) {
      throw const SourceParserException('X 返回了无法识别的视频信息');
    }
    final media = decoded['mediaDetails'];
    final resources = <SourceResource>[];
    if (media is List) {
      for (final item in media.whereType<Map>()) {
        final video = item['video_info'];
        final variants = video is Map ? video['variants'] : null;
        if (variants is! List) continue;
        final mp4s = variants.whereType<Map>().where(_isMp4).toList()
          ..sort((a, b) => _bitrate(b).compareTo(_bitrate(a)));
        if (mp4s.isEmpty) continue;
        final uri = Uri.parse(mp4s.first['url'] as String);
        resources.add(
          SourceResource(
            title: 'X 视频：$id · ${resources.length + 1}',
            url: uri.toString(),
            type: SourceResourceType.video,
            platform: SourcePlatform.x,
            host: uri.host,
            sizeHint: 'X 公开视频 · 应用内下载',
          ),
        );
      }
    }
    if (resources.isEmpty) {
      throw const SourceParserException(
        'X 公开接口未提供可下载的 MP4。请通过右上角账号入口登录 X 后重试；帖子也可能没有视频或受访问限制。',
      );
    }
    return resources;
  }

  bool _isMp4(Map item) {
    final uri = Uri.tryParse(item['url']?.toString() ?? '');
    return item['content_type'] == 'video/mp4' &&
        uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'video.twimg.com' ||
            uri.host.endsWith('.video.twimg.com'));
  }

  int _bitrate(Map value) => (value['bitrate'] as num?)?.toInt() ?? 0;
}
