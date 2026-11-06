import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'source_parser/download_history_store.dart';
import 'source_parser/download_settings_store.dart';
import 'source_parser/incoming_link_bridge.dart';
import 'source_parser/parse_history_store.dart';
import 'source_parser/proxy_settings_store.dart';
import 'source_parser/source_parser_home_page.dart';
import 'source_parser/source_parser_service.dart';

void main() {
  runApp(const VideoDownloaderApp());
}

class VideoDownloaderApp extends StatefulWidget {
  const VideoDownloaderApp({
    super.key,
    this.parserService,
    this.parseHistoryStore,
    this.downloadHistoryStore,
    this.downloadSettingsStore,
    this.proxySettingsStore,
    this.xVideoPreflightProbe,
    this.incomingLinkListenable,
  });

  final SourceParserService? parserService;
  final ParseHistoryStore? parseHistoryStore;
  final DownloadHistoryStore? downloadHistoryStore;
  final DownloadSettingsStore? downloadSettingsStore;
  final ProxySettingsStore? proxySettingsStore;
  final XVideoPreflightProbe? xVideoPreflightProbe;
  final ValueListenable<IncomingLinkEvent?>? incomingLinkListenable;

  @override
  State<VideoDownloaderApp> createState() => _VideoDownloaderAppState();
}

class _VideoDownloaderAppState extends State<VideoDownloaderApp> {
  IncomingLinkBridge? _incomingLinkBridge;

  ValueListenable<IncomingLinkEvent?>? get _resolvedIncomingLinkListenable {
    return widget.incomingLinkListenable ??
        _incomingLinkBridge?.incomingLinkListenable;
  }

  @override
  void initState() {
    super.initState();
    if (widget.incomingLinkListenable != null) {
      return;
    }

    _incomingLinkBridge = IncomingLinkBridge();
    unawaited(_incomingLinkBridge!.initialize());
  }

  @override
  void dispose() {
    _incomingLinkBridge?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F6F73),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Source Parser',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        useMaterial3: true,
      ),
      home: SourceParserHomePage(
        parserService: widget.parserService,
        parseHistoryStore: widget.parseHistoryStore,
        downloadHistoryStore: widget.downloadHistoryStore,
        downloadSettingsStore: widget.downloadSettingsStore,
        proxySettingsStore: widget.proxySettingsStore,
        xVideoPreflightProbe: widget.xVideoPreflightProbe,
        incomingLinkListenable: _resolvedIncomingLinkListenable,
      ),
    );
  }
}
