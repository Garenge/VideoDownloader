import 'dart:io';

import 'package:videodownloader/source_parser/source_parser_service.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stdout.writeln(
      'checkParserUrl: usage: dart run tooling/check_parser_url.dart <url>',
    );
    return;
  }

  final service = SourceParserService();
  final result = await service.parse(args.single);

  stdout.writeln('checkParserUrl: platform=${result.platform.displayName}');
  stdout.writeln('checkParserUrl: total=${result.resources.length}');
  for (final type in SourceResourceType.values) {
    stdout.writeln(
      'checkParserUrl: ${type.displayName}=${result.resourcesOf(type).length}',
    );
  }

  for (final resource in result.resources) {
    stdout.writeln(
      'checkParserUrl: resource type=${resource.type.displayName}, url=${resource.url}',
    );
  }
}
