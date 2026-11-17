import 'dart:io';

import 'source_resource.dart';

/// Preserve the parser's attachment order even when only a subset is queued.
List<SourceResource> withAttachmentSources(
  List<SourceResource> resources,
  Uri page,
) => [
  for (var index = 0; index < resources.length; index++)
    resources[index].withAttachmentSource(
      page.toString(),
      index + 1,
      resources.length,
    ),
];

String? xPostBaseName(SourceResource resource) {
  if (resource.platform != SourcePlatform.x) return null;
  final page = Uri.tryParse(resource.sourcePageUrl ?? resource.url);
  final id = RegExp(
    r'/status/(\d+)(?:/|$)',
  ).firstMatch(page?.path ?? '')?.group(1);
  if (id == null) return null;
  final index = resource.attachmentIndex;
  return (resource.attachmentCount ?? 1) > 1 && index != null
      ? '$id-$index'
      : id;
}

String downloadFileName(SourceResource resource) {
  final postName = xPostBaseName(resource);
  final extension = resource.fileExtension == 'unknown'
      ? switch (resource.type) {
          SourceResourceType.video => 'mp4',
          SourceResourceType.image => 'jpg',
          SourceResourceType.other => 'bin',
        }
      : resource.fileExtension;
  if (postName != null) return '$postName.$extension';
  return _directFileName(resource, extension);
}

String _directFileName(SourceResource resource, String extension) {
  final raw = Uri.tryParse(
    resource.url,
  )?.pathSegments.where((part) => part.isNotEmpty).lastOrNull;
  final name = (raw == null || raw.trim().isEmpty ? resource.title : raw)
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  return name.contains('.') ? name : '$name.$extension';
}

/// Parenthesized collision numbers cannot be mistaken for attachment indexes.
Future<File> uniqueDownloadFile(Directory directory, String fileName) async {
  final dot = fileName.lastIndexOf('.');
  final name = dot <= 0 ? fileName : fileName.substring(0, dot);
  final extension = dot <= 0 ? '' : fileName.substring(dot);
  var file = File('${directory.path}/$fileName');
  var copy = 1;
  while (await file.exists() || await File('${file.path}.part').exists()) {
    copy++;
    file = File('${directory.path}/$name ($copy)$extension');
  }
  return file;
}
