import 'package:http/http.dart' as http;

import '../parse_failure_message.dart';
import '../source_resource.dart';
import '../x_login_bridge.dart';
import 'x_public_video_resolver.dart';

/// A logged-in webpage uses its own on-device cookies; no session secrets enter Dart.
class IosXVideoResolver {
  IosXVideoResolver({
    required XPublicVideoResolver publicResolver,
    Future<List<String>?> Function(Uri)? sessionResolver,
  }) : _publicResolver = publicResolver,
       _sessionResolver = sessionResolver ?? XLoginBridge.resolveIosVideo;

  final XPublicVideoResolver _publicResolver;
  final Future<List<String>?> Function(Uri) _sessionResolver;

  Future<List<SourceResource>> resolve(http.Client client, Uri page) async {
    try {
      final sessionUrls = await _sessionResolver(page);
      if (sessionUrls == null) {
        return await _publicResolver.resolve(client, page);
      }
      final urls = sessionUrls.toSet().where(_isTrustedVideo).toList();
      if (urls.isEmpty) {
        throw const SourceParserException('当前账号未能读取此帖子的 MP4，请检查登录状态或帖子访问权限。');
      }
      return [
        for (var index = 0; index < urls.length; index++)
          SourceResource(
            title: 'X 视频 · ${index + 1}',
            url: urls[index],
            type: SourceResourceType.video,
            platform: SourcePlatform.x,
            host: Uri.parse(urls[index]).host,
            sizeHint: 'X 登录会话 · 应用内下载',
          ),
      ];
    } on Object catch (error) {
      throw SourceParserException(parseFailureMessage(error));
    }
  }

  bool _isTrustedVideo(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'video.twimg.com' ||
            uri.host.endsWith('.video.twimg.com'));
  }
}
