import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'download_activity_overlay.dart';
import 'download_history_store.dart';
import 'download_settings.dart';
import 'download_settings_sheet.dart';
import 'download_settings_store.dart';
import 'download_queue_controller.dart';
import 'download_queue_panel.dart';
import 'parse_history_store.dart';
import 'proxied_http_client_factory.dart';
import 'proxy_settings_sheet.dart';
import 'proxy_settings_store.dart';
import 'resource_http_client_scope.dart';
import 'resource_thumbnail_image.dart';
import 'source_parser_service.dart';
import 'source_resource.dart';

part 'source_parser_resource_widgets.dart';

class _ToolProbeResult {
  const _ToolProbeResult(this.ok, this.version, this.errorMessage);

  final bool ok;
  final String? version;
  final String? errorMessage;
}

typedef ExternalBrowserOpener = Future<void> Function(String url);

Future<void> _defaultExternalBrowserOpener(String url) async {
  final trimmed = url.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw StateError('无效的 URL');
  }

  final launchTarget = uri.toString();

  // 桌面端不走 url_launcher 的 MethodChannel，避免 macOS 等板块上出现
  // MissingPluginException（热重载未全量重建、或嵌入未注册插件时仍可用系统命令打开）。
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await _launchHttpUrlViaDesktopShell(launchTarget);
    return;
  }

  final launched = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (!launched) {
    debugPrint(
      'lib/source_parser/source_parser_home_page.dart#_defaultExternalBrowserOpener: '
      'launchUrl returned false uri=$uri',
    );
    throw StateError('无法打开浏览器');
  }
}

Future<void> _launchHttpUrlViaDesktopShell(String launchTarget) async {
  if (Platform.isMacOS) {
    final result = await Process.run('open', [launchTarget]);
    if (result.exitCode != 0) {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_launchHttpUrlViaDesktopShell: '
        'macOS open failed exit=${result.exitCode} stderr=${result.stderr}',
      );
      throw StateError(
        result.stderr.toString().trim().isEmpty
            ? 'exit ${result.exitCode}'
            : result.stderr.toString().trim(),
      );
    }
    return;
  }

  if (Platform.isWindows) {
    final result = await Process.run('cmd', [
      '/c',
      'start',
      '',
      launchTarget,
    ]);
    if (result.exitCode != 0) {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_launchHttpUrlViaDesktopShell: '
        'Windows start failed exit=${result.exitCode} stderr=${result.stderr}',
      );
      throw StateError(
        result.stderr.toString().trim().isEmpty
            ? 'exit ${result.exitCode}'
            : result.stderr.toString().trim(),
      );
    }
    return;
  }

  final result = await Process.run('xdg-open', [launchTarget]);
  if (result.exitCode != 0) {
    debugPrint(
      'lib/source_parser/source_parser_home_page.dart#_launchHttpUrlViaDesktopShell: '
      'xdg-open failed exit=${result.exitCode} stderr=${result.stderr}',
    );
    throw StateError(
      result.stderr.toString().trim().isEmpty
          ? 'exit ${result.exitCode}'
          : result.stderr.toString().trim(),
    );
  }
}

class SourceParserHomePage extends StatefulWidget {
  const SourceParserHomePage({
    super.key,
    this.parserService,
    this.parseHistoryStore,
    this.downloadHistoryStore,
    this.proxySettingsStore,
    this.externalBrowserOpener,
  });

  final SourceParserService? parserService;
  final ParseHistoryStore? parseHistoryStore;
  final DownloadHistoryStore? downloadHistoryStore;
  final ProxySettingsStore? proxySettingsStore;
  final ExternalBrowserOpener? externalBrowserOpener;

  @override
  State<SourceParserHomePage> createState() => _SourceParserHomePageState();
}

class _SourceParserHomePageState extends State<SourceParserHomePage>
    with TickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _resourceSearchController = TextEditingController();
  late final TabController _resourceTypeTabController;
  SourceParserService? _parserService;
  DownloadQueueController? _downloadQueueController;
  late final ParseHistoryStore _parseHistoryStore;
  ProxySettingsStore? _proxySettingsStore;
  late final DownloadSettingsStore _downloadSettingsStore;
  DownloadSettings _downloadSettings = const DownloadSettings.defaults();
  DownloadToolStatus _downloadToolStatus = const DownloadToolStatus.unknown();
  String? _savedProxySpec;
  bool _networkReady = false;
  bool _downloadSettingsReady = false;
  bool _downloadToolStatusReady = false;
  bool _hasShownStartupToolWarning = false;

  SourceParseResult? _result;
  List<String> _recentUrls = [];
  String? _selectedHost;
  String? _selectedExtension;
  String? _errorText;
  bool _isParsing = false;
  DateTime? _parseStartedAt;
  Timer? _parseElapsedTicker;
  bool _downloadPanelOpen = false;

  @override
  void initState() {
    super.initState();
    _resourceTypeTabController = TabController(length: 4, vsync: this);
    _parseHistoryStore = widget.parseHistoryStore ?? ParseHistoryStore();
    _resourceSearchController.addListener(_handleResourceSearchChanged);
    _downloadSettingsStore = DownloadSettingsStore();
    unawaited(_loadDownloadSettings());
    unawaited(_refreshDownloadToolStatus());

    if (widget.parserService != null) {
      _parserService = widget.parserService;
      _downloadQueueController = DownloadQueueController(
        downloadHistoryStore: widget.downloadHistoryStore,
        downloadSettings: _downloadSettings,
      );
      _savedProxySpec = null;
      _networkReady = true;
    } else {
      _proxySettingsStore = widget.proxySettingsStore ?? ProxySettingsStore();
      unawaited(_bootstrapOwnedNetworkClients());
    }

    _loadRecentUrls();
  }

  Future<void> _bootstrapOwnedNetworkClients() async {
    final store = _proxySettingsStore!;
    final spec = await store.load();
    if (!mounted) {
      return;
    }

    final parserClient = ProxiedHttpClientFactory.create(spec);
    final downloadClient = ProxiedHttpClientFactory.create(spec);

    setState(() {
      _parserService = SourceParserService(
        client: parserClient,
        ownClient: true,
      );
      _downloadQueueController = DownloadQueueController(
        client: downloadClient,
        ownClient: true,
        downloadHistoryStore: widget.downloadHistoryStore,
        downloadSettings: _downloadSettings,
      );
      _savedProxySpec = spec;
      _networkReady = true;
    });
  }

  Future<void> _loadDownloadSettings() async {
    final settings = await _downloadSettingsStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _downloadSettings = settings;
      _downloadSettingsReady = true;
    });
    await _downloadQueueController?.updateDownloadSettings(settings);
    _maybeShowStartupToolWarning();
  }

  Future<void> _refreshDownloadToolStatus() async {
    DownloadToolStatus status = const DownloadToolStatus.unknown();

    final ytDlp = await _probeTool('yt-dlp', const ['--version']);
    status = status.copyWith(
      ytDlpAvailable: ytDlp.ok,
      ytDlpVersion: ytDlp.version,
      checkedAt: DateTime.now(),
    );

    final ffmpeg = await _probeTool('ffmpeg', const ['-version']);
    status = status.copyWith(
      ffmpegAvailable: ffmpeg.ok,
      ffmpegVersion: ffmpeg.version,
      checkedAt: DateTime.now(),
    );
    final blockedMessage = ytDlp.errorMessage ?? ffmpeg.errorMessage;
    if (blockedMessage != null &&
        blockedMessage.contains('Operation not permitted')) {
      status = status.copyWith(
        externalCommandBlocked: true,
        externalCommandBlockReason: blockedMessage,
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _downloadToolStatus = status;
      _downloadToolStatusReady = true;
    });
    _maybeShowStartupToolWarning();
  }

  void _maybeShowStartupToolWarning() {
    if (!mounted || _hasShownStartupToolWarning) {
      return;
    }
    if (!_downloadSettingsReady || !_downloadToolStatusReady) {
      return;
    }

    final shouldWarnBlocked = _downloadToolStatus.externalCommandBlocked;
    final shouldWarnMissingYtDlp =
        _downloadSettings.enableYtDlpFallback &&
        !_downloadToolStatus.ytDlpAvailable &&
        !_downloadToolStatus.externalCommandBlocked;
    final shouldWarnMissingFfmpeg = !_downloadToolStatus.ffmpegAvailable;

    if (!shouldWarnBlocked &&
        !shouldWarnMissingYtDlp &&
        !shouldWarnMissingFfmpeg) {
      return;
    }

    _hasShownStartupToolWarning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final messages = <String>[
        if (shouldWarnBlocked)
          '检测到当前运行环境禁止执行外部命令（可能是 macOS 沙箱限制），yt-dlp 兜底不可用。',
        if (shouldWarnMissingYtDlp) '未检测到 yt-dlp，YouTube 兜底下载不可用。',
        if (shouldWarnMissingFfmpeg) '未检测到 ffmpeg，部分音视频合并/转封装可能失败。',
      ];

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('下载环境自检提示'),
            content: Text(messages.join('\n')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(_openDownloadSettings());
                },
                child: const Text('打开下载设置'),
              ),
            ],
          );
        },
      );
    });
  }

  Future<_ToolProbeResult> _probeTool(
    String executable,
    List<String> args,
  ) async {
    final candidates = _probeExecutableCandidates(executable);
    for (final candidate in candidates) {
      final result = await _runToolProbe(candidate, args);
      if (result.ok) {
        return result;
      }
      // If command exists but returns non-zero, don't keep trying other paths.
      if (result.errorMessage != null &&
          !result.errorMessage!.contains('No such file or directory')) {
        return result;
      }
    }
    final existingPath = _findExistingExecutablePath(candidates);
    if (existingPath != null) {
      return _ToolProbeResult(true, '已安装 ($existingPath)', null);
    }
    return const _ToolProbeResult(false, null, 'No such file or directory');
  }

  Future<_ToolProbeResult> _runToolProbe(
    String executable,
    List<String> args,
  ) async {
    try {
      final result = await Process.run(executable, args);
      if (result.exitCode != 0) {
        final err = (result.stderr ?? '').toString().trim();
        return _ToolProbeResult(false, null, err.isEmpty ? null : err);
      }

      final out = (result.stdout ?? '').toString().trim();
      final firstLine = out.split('\n').first.trim();
      return _ToolProbeResult(true, firstLine.isEmpty ? null : firstLine, null);
    } on ProcessException catch (error) {
      return _ToolProbeResult(false, null, error.message);
    } on Object catch (error) {
      return _ToolProbeResult(false, null, error.toString());
    }
  }

  List<String> _probeExecutableCandidates(String executable) {
    return <String>[
      executable,
      '/opt/homebrew/bin/$executable',
      '/usr/local/bin/$executable',
      '/usr/bin/$executable',
      '/Users/garenge/.local/bin/$executable',
    ];
  }

  String? _findExistingExecutablePath(List<String> candidates) {
    for (final candidate in candidates) {
      if (!candidate.startsWith('/')) {
        continue;
      }
      final file = File(candidate);
      if (file.existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _openDownloadSettings() async {
    await showDownloadSettingsDialog(
      context: context,
      initialSettings: _downloadSettings,
      toolStatus: _downloadToolStatus,
      onApply: (settings) async {
        await _downloadSettingsStore.save(settings);
        await _downloadQueueController?.updateDownloadSettings(settings);
        if (!mounted) {
          return;
        }
        setState(() {
          _downloadSettings = settings;
        });
      },
    );
  }

  @override
  void dispose() {
    _parseElapsedTicker?.cancel();
    _urlController.dispose();
    _resourceSearchController.dispose();
    if (widget.parserService == null) {
      _parserService?.dispose();
    }
    _downloadQueueController?.dispose();
    _resourceTypeTabController.dispose();
    super.dispose();
  }

  Future<void> _openProxySettings() async {
    await showProxySettingsDialog(
      context: context,
      initialProxySpec: _savedProxySpec,
      onApply: _persistProxyAndApplyClients,
    );
  }

  Future<void> _persistProxyAndApplyClients(String? spec) async {
    await _proxySettingsStore!.save(spec);
    final parserClient = ProxiedHttpClientFactory.create(spec);
    final downloadClient = ProxiedHttpClientFactory.create(spec);
    _parserService!.replaceHttpClient(parserClient);
    _downloadQueueController!.replaceHttpClient(downloadClient);
    if (!mounted) {
      return;
    }

    setState(() {
      _savedProxySpec = spec;
    });
  }

  void _handleResourceSearchChanged() {
    setState(() {});
  }

  Future<void> _loadRecentUrls() async {
    final urls = await _parseHistoryStore.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _recentUrls = urls;
    });
  }

  Future<void> _handleParse() async {
    final error = _parserService!.validate(_urlController.text);
    if (error != null) {
      setState(() {
        _errorText = error;
      });
      return;
    }

    setState(() {
      _errorText = null;
      _selectedHost = null;
      _selectedExtension = null;
      _resourceSearchController.clear();
      _isParsing = true;
      _parseStartedAt = DateTime.now();
    });
    _startParseElapsedTicker();

    try {
      final result = await _parserService!.parse(_urlController.text);
      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
      });
      _resourceTypeTabController.index = 0;
      _logParseResult(result);
      await _saveParsedUrl(result.originalUrl);
    } on SourceParserException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorText = error.message;
        _result = null;
      });
    } finally {
      _stopParseElapsedTicker();
      if (mounted) {
        setState(() {
          _isParsing = false;
          _parseStartedAt = null;
        });
      }
    }
  }

  void _startParseElapsedTicker() {
    _parseElapsedTicker?.cancel();
    _parseElapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isParsing) {
        _parseElapsedTicker?.cancel();
        _parseElapsedTicker = null;
        return;
      }
      setState(() {});
    });
  }

  void _stopParseElapsedTicker() {
    _parseElapsedTicker?.cancel();
    _parseElapsedTicker = null;
  }

  Future<void> _handleOpenInBrowser() async {
    final error = _parserService!.validate(_urlController.text);
    if (error != null) {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleOpenInBrowser: '
        'validation failed input=${_urlController.text.trim()} message=$error',
      );
      setState(() {
        _errorText = error;
      });
      return;
    }

    final url = _urlController.text.trim();
    setState(() {
      _errorText = null;
    });

    try {
      await (widget.externalBrowserOpener ?? _defaultExternalBrowserOpener)(
        url,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已在浏览器打开')));
    } on SourceParserException catch (error) {
      _showOpenBrowserError(error.message, attemptedUrl: url);
    } on Object catch (error) {
      _showOpenBrowserError(error.toString(), attemptedUrl: url);
    }
  }

  void _showOpenBrowserError(String message, {required String attemptedUrl}) {
    debugPrint(
      'lib/source_parser/source_parser_home_page.dart#_showOpenBrowserError: '
      'attemptedUrl=$attemptedUrl message=$message',
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('打开浏览器失败：$message')));
  }

  void _logParseResult(SourceParseResult result) {
    final videoCount = result.resourcesOf(SourceResourceType.video).length;
    final imageCount = result.resourcesOf(SourceResourceType.image).length;
    final otherCount = result.resourcesOf(SourceResourceType.other).length;
    debugPrint(
      'lib/source_parser/source_parser_home_page.dart#_handleParse: '
      'parsed platform=${result.platform.label}, total=${result.resources.length}, '
      'video=$videoCount, image=$imageCount, other=$otherCount, '
      'url=${result.originalUrl}',
    );

    for (final resource in result.resources) {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleParse: '
        'resource type=${resource.type.name}, title=${resource.title}, '
        'host=${resource.host}, ext=${resource.fileExtension}, url=${resource.url}',
      );
    }
  }

  Future<void> _saveParsedUrl(String url) async {
    final urls = await _parseHistoryStore.add(url);
    if (!mounted) {
      return;
    }

    setState(() {
      _recentUrls = urls;
    });
  }

  Future<void> _clearRecentUrls() async {
    await _parseHistoryStore.clear();
    if (!mounted) {
      return;
    }

    setState(() {
      _recentUrls = [];
    });
  }

  void _selectRecentUrl(String url) {
    _urlController.text = url;
  }

  void _handleDownload(SourceResource resource) {
    final task = _downloadQueueController!.enqueue(resource);
    setState(() {
      _downloadPanelOpen = true;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已加入下载队列：${task.fileName}')));
  }

  void _toggleDownloadPanel() {
    setState(() {
      _downloadPanelOpen = !_downloadPanelOpen;
    });
  }

  void _closeDownloadPanel() {
    setState(() {
      _downloadPanelOpen = false;
    });
  }

  int _activeDownloadBadgeCount() {
    final tasks = _downloadQueueController!.tasks;
    return tasks
        .where(
          (task) =>
              task.status == DownloadStatus.pending ||
              task.status == DownloadStatus.downloading,
        )
        .length;
  }

  Future<void> _handleSelectDownloadDirectory() async {
    final directoryPath = await getDirectoryPath(confirmButtonText: '选择保存目录');
    if (directoryPath == null || directoryPath.trim().isEmpty) {
      return;
    }

    _downloadQueueController!.setDownloadDirectory(directoryPath);
  }

  void _handleResetDownloadDirectory() {
    _downloadQueueController!.resetDownloadDirectory();
  }

  Future<void> _handleOpenDownloadedFolder(DownloadTask task) async {
    try {
      await _downloadQueueController!.openDownloadedFolder(task);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开文件夹失败：$error')));
    }
  }

  Future<void> _handleOpenHistoryFolder(DownloadHistoryRecord record) async {
    try {
      await _downloadQueueController!.openHistoryFolder(record);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开历史文件夹失败：$error')));
    }
  }

  Future<void> _handleCopyTaskLogs(DownloadTask task) async {
    final logs = task.logText.trim();
    if (logs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前任务暂无可复制日志')));
      return;
    }

    final text = [
      '[Download Debug Log]',
      'taskId=${task.id}',
      'status=${task.status.name}',
      'fileName=${task.fileName}',
      'url=${task.resource.url}',
      if (task.errorMessage != null) 'error=${task.errorMessage}',
      '---',
      logs,
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('下载日志已复制，可直接粘贴给我')));
  }

  void _selectHost(String? host) {
    setState(() {
      _selectedHost = host;
    });
  }

  void _selectExtension(String? extension) {
    setState(() {
      _selectedExtension = extension;
    });
  }

  void _clearResourceFilters() {
    setState(() {
      _selectedHost = null;
      _selectedExtension = null;
      _resourceSearchController.clear();
    });
  }

  double _resourceTabViewBodyHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return math.min(580, math.max(360, h * 0.48));
  }

  @override
  Widget build(BuildContext context) {
    if (!_networkReady) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ResourceHttpClientScope(
          client: _parserService!.resourceHttpClient,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 100),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(context),
                            const SizedBox(height: 22),
                            _buildParserPanel(context),
                            const SizedBox(height: 20),
                            _buildDownloadSettingsSection(context),
                            const SizedBox(height: 20),
                            _buildResultSection(context),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              AnimatedBuilder(
                animation: _downloadQueueController!,
                builder: (context, _) {
                  final controller = _downloadQueueController!;
                  return DownloadActivityOverlay(
                    panelOpen: _downloadPanelOpen,
                    onTogglePanel: _toggleDownloadPanel,
                    onClosePanel: _closeDownloadPanel,
                    activeDownloadCount: _activeDownloadBadgeCount(),
                    queuePanel: DownloadQueuePanel(
                      tasks: controller.tasks,
                      onCancel: controller.cancel,
                      onRetry: controller.retry,
                      onOpenFolder: _handleOpenDownloadedFolder,
                      onCopyLogs: _handleCopyTaskLogs,
                    ),
                    historyPanel: DownloadHistoryPanel(
                      records: controller.history,
                      onOpenFolder: _handleOpenHistoryFolder,
                      onClear: controller.clearHistory,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.travel_explore, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '网页资源解析',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '粘贴链接，识别视频、图片和其他可下载资源',
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (widget.parserService == null) ...[
          if (_savedProxySpec != null && _savedProxySpec!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: _savedProxySpec!,
                child: Icon(
                  Icons.vpn_key,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          IconButton(
            key: const ValueKey('proxy-settings-button'),
            tooltip: '代理设置',
            onPressed: _openProxySettings,
            icon: const Icon(Icons.settings_ethernet),
          ),
        ],
      ],
    );
  }

  Widget _buildParserPanel(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: '目标 URL',
                hintText: 'https://www.youtube.com/watch?v=...',
                errorText: _errorText,
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) {
                if (!_isParsing) {
                  _handleParse();
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _buildPlatformHints(context)),
                const SizedBox(width: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('open-in-browser-button'),
                      onPressed: _handleOpenInBrowser,
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('在浏览器打开'),
                    ),
                    FilledButton.icon(
                      onPressed: _isParsing ? null : _handleParse,
                      icon: _isParsing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: Text(_isParsing ? '解析中' : '解析'),
                    ),
                  ],
                ),
              ],
            ),
            if (_isParsing) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '正在请求网页并解析资源，耗时取决于网络与页面复杂度，请稍候…',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_parseStartedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  '已等待 ${DateTime.now().difference(_parseStartedAt!).inSeconds}s',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
            if (_recentUrls.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildRecentUrlHistory(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentUrlHistory(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '最近解析',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('clear-parse-history-button'),
              onPressed: _clearRecentUrls,
              icon: const Icon(Icons.delete_outline),
              label: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final url in _recentUrls)
              ActionChip(
                key: ValueKey('recent-url-$url'),
                avatar: const Icon(Icons.history, size: 18),
                label: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: () => _selectRecentUrl(url),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlatformHints(BuildContext context) {
    final platforms = SourcePlatform.values;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final platform in platforms)
          Chip(
            avatar: Icon(_platformIcon(platform), size: 18),
            label: Text(platform.displayName),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _buildResultSection(BuildContext context) {
    if (_isParsing) {
      return _buildLoadingState(context);
    }

    final result = _result;
    if (result == null) {
      return _buildEmptyState(context);
    }

    final filtered = _resourcesMatchingFilters(result);
    final message = result.message;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryBar(context, result),
        const SizedBox(height: 14),
        _buildResourceFilters(result),
        const SizedBox(height: 14),
        if (result.resources.isEmpty && message != null)
          _buildNoResources(context, message)
        else if (result.resources.isEmpty)
          _buildNoResources(context, '没有在网页源码中发现可直接下载的资源')
        else
          _buildResourceTypeTabsPanel(
            context,
            result,
            filtered,
            result.originalUrl,
          ),
      ],
    );
  }

  Widget _buildResourceTypeTabsPanel(
    BuildContext context,
    SourceParseResult result,
    List<SourceResource> filtered,
    String imageRequestReferrer,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tabVideos = filtered
        .where((r) => r.type == SourceResourceType.video)
        .toList();
    final tabImages = filtered
        .where((r) => r.type == SourceResourceType.image)
        .toList();
    final tabOthers = filtered
        .where((r) => r.type == SourceResourceType.other)
        .toList();

    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: colorScheme.surface,
            child: TabBar(
              controller: _resourceTypeTabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              tabs: [
                Tab(text: '全部 ${filtered.length}'),
                Tab(text: '视频 ${tabVideos.length}'),
                Tab(text: '图片 ${tabImages.length}'),
                Tab(text: '其他 ${tabOthers.length}'),
              ],
            ),
          ),
          SizedBox(
            height: _resourceTabViewBodyHeight(context),
            child: TabBarView(
              controller: _resourceTypeTabController,
              children: [
                _buildResourceTileScrollList(
                  context,
                  filtered,
                  imageRequestReferrer,
                ),
                _buildResourceTileScrollList(
                  context,
                  tabVideos,
                  imageRequestReferrer,
                ),
                _buildResourceTileScrollList(
                  context,
                  tabImages,
                  imageRequestReferrer,
                ),
                _buildResourceTileScrollList(
                  context,
                  tabOthers,
                  imageRequestReferrer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceTileScrollList(
    BuildContext context,
    List<SourceResource> resources,
    String imageRequestReferrer,
  ) {
    if (resources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '当前分类下没有资源',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final resource in resources) ...[
            _ResourceTile(
              resource: resource,
              imageRequestReferrer: imageRequestReferrer,
              onDownload: () => _handleDownload(resource),
            ),
            if (resource != resources.last) const Divider(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadSettingsSection(BuildContext context) {
    return AnimatedBuilder(
      animation: _downloadQueueController!,
      builder: (context, _) {
        return DownloadSettingsPanel(
          selectedDirectoryPath:
              _downloadQueueController!.selectedDirectoryPath,
          downloadSettings: _downloadSettings,
          toolStatus: _downloadToolStatus,
          onSelectDirectory: _handleSelectDownloadDirectory,
          onResetDirectory: _handleResetDownloadDirectory,
          onOpenDownloadSettings: _openDownloadSettings,
        );
      },
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: const Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在读取网页源码并提取资源'),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.manage_search,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              '等待解析',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '支持抖音、X、YouTube、Bilibili，其他来源会归入其他分类。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(BuildContext context, SourceParseResult result) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(_platformIcon(result.platform)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.platform.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    result.originalUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _CountPill(label: '资源', count: result.resources.length),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceFilters(SourceParseResult result) {
    final hosts = _filterValues(
      result.resources.map((resource) => resource.host),
    );
    final extensions = _filterValues(
      result.resources.map((resource) => resource.fileExtension),
    );

    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('resource-search-field'),
              controller: _resourceSearchController,
              decoration: const InputDecoration(
                labelText: '搜索资源',
                hintText: '文件名、host、扩展名',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FilterMenu(
                  key: const ValueKey('host-filter-menu'),
                  label: 'Host',
                  value: _selectedHost,
                  values: hosts,
                  onChanged: _selectHost,
                ),
                _FilterMenu(
                  key: const ValueKey('extension-filter-menu'),
                  label: '扩展名',
                  value: _selectedExtension,
                  values: extensions,
                  onChanged: _selectExtension,
                ),
                TextButton.icon(
                  key: const ValueKey('clear-resource-filters-button'),
                  onPressed: _clearResourceFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('清空筛选'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResources(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  List<SourceResource> _resourcesMatchingFilters(SourceParseResult result) {
    final query = _resourceSearchController.text.trim().toLowerCase();

    return result.resources.where((resource) {
      final selectedHost = _selectedHost;
      if (selectedHost != null && resource.host != selectedHost) {
        return false;
      }

      final selectedExtension = _selectedExtension;
      if (selectedExtension != null &&
          resource.fileExtension != selectedExtension) {
        return false;
      }

      if (query.isNotEmpty && !resource.searchableText.contains(query)) {
        return false;
      }

      return true;
    }).toList();
  }

  List<String> _filterValues(Iterable<String> values) {
    final normalizedValues =
        values.where((value) => value.trim().isNotEmpty).toSet().toList()
          ..sort();
    return normalizedValues;
  }

  BoxDecoration _panelDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }

  IconData _platformIcon(SourcePlatform platform) {
    return switch (platform) {
      SourcePlatform.douyin => Icons.music_video,
      SourcePlatform.x => Icons.alternate_email,
      SourcePlatform.youtube => Icons.play_circle,
      SourcePlatform.bilibili => Icons.ondemand_video,
      SourcePlatform.other => Icons.public,
    };
  }
}
