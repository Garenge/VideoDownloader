import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../source_resource.dart';
import '../x_login_bridge.dart';
import '../x_media_url.dart';
import 'ios_media_bridge.dart';

/// 直接请求 X 的公开嵌入接口，不通过第三方解析服务。
class XPublicVideoResolver {
  XPublicVideoResolver({
    Future<String> Function(String)? tokenGenerator,
    Duration requestTimeout = const Duration(seconds: 20),
  }) : _tokenGenerator =
           tokenGenerator ??
           (Platform.isIOS
               ? const IosMediaBridge().xToken
               : XLoginBridge.publicMediaToken),
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
      throw SourceParserException('X 公开媒体解析失败：HTTP ${response.statusCode}');
    }
    return _extract(jsonDecode(response.body), id);
  }

  List<SourceResource> _extract(Object? decoded, String id) {
    if (decoded is! Map) {
      throw const SourceParserException('X 返回了无法识别的媒体信息');
    }
    final media = decoded['mediaDetails'];
    final resources = <SourceResource>[];
    if (media is List) {
      for (final item in media.whereType<Map>()) {
        if (item['type'] == 'photo') {
          final url = item['media_url_https']?.toString();
          if (url != null && xMediaType(url) == SourceResourceType.image) {
            resources.add(
              _resource(
                originalXImageUrl(url),
                SourceResourceType.image,
                id,
                resources.length + 1,
              ),
            );
          }
          continue;
        }
        final video = item['video_info'];
        final variants = video is Map ? video['variants'] : null;
        if (variants is! List) continue;
        final mp4s = variants.whereType<Map>().where(_isMp4).toList()
          ..sort((a, b) => _bitrate(b).compareTo(_bitrate(a)));
        if (mp4s.isEmpty) continue;
        resources.add(
          _resource(
            mp4s.first['url'] as String,
            SourceResourceType.video,
            id,
            resources.length + 1,
          ),
        );
      }
    }
    if (resources.isEmpty) {
      throw const SourceParserException(
        'X 公开接口未提供可下载的图片或 MP4。请通过右上角账号入口登录 X 后重试；帖子也可能没有媒体或受访问限制。',
      );
    }
    final seen = <String>{};
    return resources.where((item) => seen.add(item.url)).toList();
  }

  SourceResource _resource(
    String url,
    SourceResourceType type,
    String id,
    int index,
  ) => SourceResource(
    title: 'X ${type.displayName}：$id · $index',
    url: url,
    type: type,
    platform: SourcePlatform.x,
    host: Uri.parse(url).host,
    sizeHint: 'X 公开${type.displayName} · 应用内下载',
  );

  bool _isMp4(Map item) {
    return item['content_type'] == 'video/mp4' &&
        xMediaType(item['url']?.toString() ?? '') == SourceResourceType.video;
  }

  int _bitrate(Map value) => (value['bitrate'] as num?)?.toInt() ?? 0;
}
