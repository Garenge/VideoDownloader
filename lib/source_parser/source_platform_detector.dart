part of 'source_parser_service.dart';

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
