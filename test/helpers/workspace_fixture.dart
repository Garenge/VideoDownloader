import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/download_settings.dart';
import 'package:videodownloader/source_parser/download_settings_store.dart';
import 'package:videodownloader/source_parser/parse_history_store.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

class MemorySettingsStore extends DownloadSettingsStore {
  MemorySettingsStore({this.ready});
  final Completer<DownloadSettings>? ready;
  DownloadSettings value = const DownloadSettings.defaults();
  @override
  Future<DownloadSettings> load() async =>
      value = await (ready?.future ?? Future.value(value));
  @override
  Future<void> save(DownloadSettings settings) async => value = settings;
}

class WorkspaceParser extends SourceParserService {
  WorkspaceParser()
    : super(client: MockClient((request) async => http.Response('', 200)));
  final List<String> parsed = [];
  Completer<void>? firstParse;
  @override
  Future<SourceParseResult> parse(String url) async {
    parsed.add(url);
    if (parsed.length == 1) await firstParse?.future;
    return SourceParseResult(
      originalUrl: url,
      platform: SourcePlatform.other,
      resources: [
        SourceResource(
          title: 'Shared video',
          url: '$url.mp4',
          type: SourceResourceType.video,
          platform: SourcePlatform.other,
          host: 'example.com',
          sizeHint: '',
        ),
      ],
    );
  }
}

class WorkspaceParseHistory extends ParseHistoryStore {
  WorkspaceParseHistory() : super(fileResolver: () async => File('/unused'));
  @override
  Future<List<String>> load() async => [];
  @override
  Future<List<String>> add(String url) async => [url];
}

class WorkspaceDownloadHistory extends DownloadHistoryStore {
  WorkspaceDownloadHistory() : super(fileResolver: () async => File('/unused'));
  @override
  Future<List<DownloadHistoryRecord>> load() async => [];
}
