enum SourcePlatform {
  douyin('Douyin', '抖音'),
  x('X', 'X'),
  youtube('YouTube', 'YouTube'),
  bilibili('Bilibili', 'Bilibili'),
  other('Other', '其他');

  const SourcePlatform(this.label, this.displayName);

  final String label;
  final String displayName;
}

enum SourceResourceType {
  video('视频'),
  image('图片'),
  other('其他');

  const SourceResourceType(this.displayName);

  final String displayName;
}

class SourceParseResult {
  const SourceParseResult({
    required this.originalUrl,
    required this.platform,
    required this.resources,
    this.message,
  });

  final String originalUrl;
  final SourcePlatform platform;
  final List<SourceResource> resources;
  final String? message;

  List<SourceResource> resourcesOf(SourceResourceType type) {
    return resources.where((resource) => resource.type == type).toList();
  }
}

class SourceResource {
  const SourceResource({
    required this.title,
    required this.url,
    required this.type,
    required this.platform,
    required this.host,
    required this.sizeHint,
    this.youtubeVideoId,
    this.requiresYtDlp = false,
  });

  final String title;
  final String url;
  final SourceResourceType type;
  final SourcePlatform platform;
  final String host;
  final String sizeHint;

  /// 非空时表示这是 YouTube 资源，应走专用下载引擎而不是对 [url] 做直链 GET。
  final String? youtubeVideoId;
  final bool requiresYtDlp;

  String get fileExtension {
    final path = Uri.tryParse(url)?.path ?? url;
    final name = path.split('/').last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) {
      return 'unknown';
    }

    final extension = name.substring(dotIndex + 1).toLowerCase();
    if (extension.length > 8) {
      return 'unknown';
    }

    return extension;
  }

  bool get isM3u8Playlist => fileExtension == 'm3u8';

  bool get isDashManifest => fileExtension == 'mpd';

  bool get likelyHlsManifest {
    final hint = sizeHint.toLowerCase();
    final loweredUrl = url.toLowerCase();
    return isM3u8Playlist ||
        hint.contains('mpegurl') ||
        hint.contains('application/x-mpegurl') ||
        hint.contains('application/vnd.apple.mpegurl') ||
        loweredUrl.contains('.m3u8');
  }

  bool get requiresFfmpegPostProcess => likelyHlsManifest || isDashManifest;

  List<String> get workflowHints {
    final hints = <String>[];
    if (likelyHlsManifest) {
      hints.add('HLS 播放列表');
    }
    if (isDashManifest) {
      hints.add('DASH 清单');
    }
    if (requiresFfmpegPostProcess) {
      hints.add('需要 ffmpeg');
    }
    if (likelyHlsManifest) {
      hints.add('推荐导出 MP4');
    }
    return hints;
  }

  String get searchableText {
    return '$title $url $host $sizeHint $fileExtension'.toLowerCase();
  }
}

class SourceParserException implements Exception {
  const SourceParserException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
