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
  });

  final String title;
  final String url;
  final SourceResourceType type;
  final SourcePlatform platform;
  final String host;
  final String sizeHint;
}

class SourceParserException implements Exception {
  const SourceParserException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
