import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'download_activity_overlay.dart';
import 'download_history_store.dart';
import 'incoming_link_bridge.dart';
import 'download_settings.dart';
import 'download_settings_sheet.dart';
import 'download_settings_store.dart';
import 'download_queue_controller.dart';
import 'download_queue_panel.dart';
import 'downloaded_files_page.dart';
import 'media_conversion_controller.dart';
import 'media_conversion_panel.dart';
import 'parse_history_store.dart';
import 'path_log_label.dart';
import 'proxied_http_client_factory.dart';
import 'proxy_settings_sheet.dart';
import 'proxy_settings_store.dart';
import 'resource_http_client_scope.dart';
import 'resource_thumbnail_image.dart';
import 'source_parser_service.dart';
import 'source_resource.dart';
import 'x_login_bridge.dart';
import 'parse_failure_message.dart';
import 'ios/ios_download_info.dart';
import 'parser_action_bar.dart';

part 'source_parser_resource_widgets.dart';

class _ToolProbeResult {
  const _ToolProbeResult(this.ok, this.version, this.errorMessage);

  final bool ok;
  final String? version;
  final String? errorMessage;
}

class _IncomingBannerState {
  const _IncomingBannerState({required this.event, required this.receivedAt});

  final IncomingLinkEvent event;
  final DateTime receivedAt;

  String get label {
    switch (event.origin) {
      case 'share_extension':
        return '来自 iOS 分享';
      case 'direct_open':
        return '来自外部链接';
      default:
        return '来自外部唤起';
    }
  }
}

enum _HeaderMenuAction {
  xLogin,
  xLogout,
  downloadSettings,
  selectDownloadDirectory,
  resetDownloadDirectory,
}

typedef ExternalBrowserOpener = Future<void> Function(String url);
typedef XVideoPreflightProbe =
    Future<XVideoPreflightResult> Function(SourceResource resource);

class XVideoPreflightResult {
  const XVideoPreflightResult({required this.errorMessage, this.debugLog});

  final String? errorMessage;
  final String? debugLog;

  bool get ok => errorMessage == null;
}

final class _XPreflightAttempt {
  const _XPreflightAttempt({required this.label, required this.args});

  final String label;
  final List<String> args;
}

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

  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final result = await Process.run('cmd', ['/c', 'start', '', launchTarget]);
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
    this.xVideoPreflightProbe,
    this.incomingLinkListenable,
  });

  final SourceParserService? parserService;
  final ParseHistoryStore? parseHistoryStore;
  final DownloadHistoryStore? downloadHistoryStore;
  final ProxySettingsStore? proxySettingsStore;
  final ExternalBrowserOpener? externalBrowserOpener;
  final XVideoPreflightProbe? xVideoPreflightProbe;
  final ValueListenable<IncomingLinkEvent?>? incomingLinkListenable;

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
  MediaConversionController? _mediaConversionController;
  late final DownloadHistoryStore _downloadHistoryStore;
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
  bool _hasCheckedStartupXLogin = false;
  bool _xAuthenticated = false;
  bool _xAccountStatusLoaded = false;
  String? _xAccountHandle;
  String? _xDisplayName;
  final Set<String> _resolvingResourceUrls = <String>{};

  SourceParseResult? _result;
  List<String> _recentUrls = [];
  String? _selectedHost;
  String? _selectedExtension;
  String? _errorText;
  bool _isParsing = false;
  DateTime? _parseStartedAt;
  Timer? _parseElapsedTicker;
  bool _downloadPanelOpen = false;
  String? _pendingIncomingUrl;
  int _lastHandledIncomingLinkSequence = 0;
  ValueListenable<IncomingLinkEvent?>? _attachedIncomingLinkListenable;
  _IncomingBannerState? _incomingBannerState;
  final List<String> _incomingShareLogLines = <String>[];
  OverlayEntry? _pageToastEntry;
  Timer? _pageToastTimer;

  @override
  void initState() {
    super.initState();
    _resourceTypeTabController = TabController(length: 4, vsync: this);
    _parseHistoryStore = widget.parseHistoryStore ?? ParseHistoryStore();
    _downloadHistoryStore =
        widget.downloadHistoryStore ?? DownloadHistoryStore();
    _resourceSearchController.addListener(_handleResourceSearchChanged);
    _downloadSettingsStore = DownloadSettingsStore();
    unawaited(_refreshXAccountStatus());
    unawaited(_loadDownloadSettings());
    unawaited(_refreshDownloadToolStatus());

    if (widget.parserService != null) {
      _parserService = widget.parserService;
      _downloadQueueController = DownloadQueueController(
        downloadHistoryStore: _downloadHistoryStore,
        downloadSettings: _downloadSettings,
      );
      _mediaConversionController = MediaConversionController(
        historyRecorder: _recordHistoryEntry,
      );
      _savedProxySpec = null;
      _networkReady = true;
    } else {
      _proxySettingsStore = widget.proxySettingsStore ?? ProxySettingsStore();
      unawaited(_bootstrapOwnedNetworkClients());
    }

    _loadRecentUrls();
    _attachIncomingLinkListenable();
  }

  @override
  void didUpdateWidget(covariant SourceParserHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incomingLinkListenable == widget.incomingLinkListenable) {
      return;
    }

    _detachIncomingLinkListenable();
    _attachIncomingLinkListenable();
  }

  Future<void> _bootstrapOwnedNetworkClients() async {
    final store = _proxySettingsStore!;
    final spec = await store.load();
    await _configureIosXProxy(spec);
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
        downloadHistoryStore: _downloadHistoryStore,
        downloadSettings: _downloadSettings,
      );
      _mediaConversionController = MediaConversionController(
        historyRecorder: _recordHistoryEntry,
      );
      _savedProxySpec = spec;
      _networkReady = true;
    });
    unawaited(_consumePendingIncomingUrlIfNeeded());
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
    if (Platform.isIOS) {
      setState(() => _downloadToolStatusReady = true);
      return;
    }
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
    if (Platform.isIOS) return;
    if (!mounted || _hasShownStartupToolWarning) {
      return;
    }
    if (!_downloadSettingsReady || !_downloadToolStatusReady) {
      return;
    }

    final shouldWarnBlocked = _downloadToolStatus.externalCommandBlocked;
    final shouldWarnMissingYtDlp =
        !_downloadToolStatus.ytDlpAvailable &&
        !_downloadToolStatus.externalCommandBlocked;
    final shouldWarnMissingFfmpeg = !_downloadToolStatus.ffmpegAvailable;

    if (!shouldWarnBlocked &&
        !shouldWarnMissingYtDlp &&
        !shouldWarnMissingFfmpeg) {
      _scheduleStartupXLoginPrompt();
      return;
    }

    _hasShownStartupToolWarning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final messages = <String>[
        if (shouldWarnBlocked)
          '检测到当前运行环境禁止执行外部命令（可能是 macOS 沙箱限制），X 下载与 yt-dlp 相关流程不可用。',
        if (shouldWarnMissingYtDlp)
          '未检测到 yt-dlp，X 下载不可用，YouTube 的 yt-dlp 流程也不可用。',
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
      ).then((_) => _scheduleStartupXLoginPrompt());
    });
  }

  void _scheduleStartupXLoginPrompt() {
    if (!Platform.isMacOS || _hasCheckedStartupXLogin) {
      return;
    }
    _hasCheckedStartupXLogin = true;
    unawaited(_showStartupXLoginPrompt());
  }

  Future<void> _showStartupXLoginPrompt() async {
    final authenticated = await _refreshXAccountStatus();
    if (authenticated != false || !mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('登录 X'),
        content: const Text('部分 X 视频需要登录后才能解析和下载。建议现在登录，也可以稍后再登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_openXLogin());
            },
            icon: const Icon(Icons.login),
            label: const Text('登录 X'),
          ),
        ],
      ),
    );
  }

  Future<void> _openXLogin() async {
    try {
      final authenticated = await XLoginBridge.openLogin();
      await _refreshXAccountStatus();
      if (!mounted || authenticated) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未检测到 X 登录状态，请完成登录后重试')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('X 登录流程失败：$error')));
    }
  }

  Future<bool?> _refreshXAccountStatus() async {
    final status = await XLoginBridge.accountStatus();
    if (!mounted || status == null) {
      return null;
    }
    setState(() {
      _xAuthenticated = status['authenticated'] == true;
      _xAccountHandle = status['handle'] as String?;
      _xDisplayName = status['displayName'] as String?;
      _xAccountStatusLoaded = true;
    });
    return _xAuthenticated;
  }

  Future<void> _logoutX() async {
    try {
      await XLoginBridge.logout();
      await _refreshXAccountStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已退出 App 内的 X 账号')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('退出 X 登录失败：$error')));
    }
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
    if (Platform.isIOS) {
      await showIosDownloadInfo(context);
      return;
    }
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
    _hidePageToast();
    _detachIncomingLinkListenable();
    _urlController.dispose();
    _resourceSearchController.dispose();
    if (widget.parserService == null) {
      _parserService?.dispose();
    }
    _downloadQueueController?.dispose();
    _mediaConversionController?.dispose();
    _resourceTypeTabController.dispose();
    super.dispose();
  }

  void _showPageToast(String message) {
    final text = message.trim();
    if (!mounted || text.isEmpty) {
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    _hidePageToast();
    final entry = OverlayEntry(builder: (_) => _buildPageToast(text));
    _pageToastEntry = entry;
    overlay.insert(entry);
    _pageToastTimer = Timer(const Duration(seconds: 2), _hidePageToast);
  }

  void _hidePageToast() {
    _pageToastTimer?.cancel();
    _pageToastTimer = null;
    _pageToastEntry?.remove();
    _pageToastEntry = null;
  }

  Widget _buildPageToast(String message) {
    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6000000),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 20,
                        color: Color(0x33000000),
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      message,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _attachIncomingLinkListenable() {
    final listenable = widget.incomingLinkListenable;
    if (listenable == null) {
      return;
    }

    _attachedIncomingLinkListenable = listenable;
    listenable.addListener(_handleIncomingLinkChanged);
    _handleIncomingLinkChanged();
  }

  void _detachIncomingLinkListenable() {
    _attachedIncomingLinkListenable?.removeListener(_handleIncomingLinkChanged);
    _attachedIncomingLinkListenable = null;
  }

  void _handleIncomingLinkChanged() {
    final event = _attachedIncomingLinkListenable?.value;
    if (event == null || event.sequence <= _lastHandledIncomingLinkSequence) {
      return;
    }

    _lastHandledIncomingLinkSequence = event.sequence;
    _recordIncomingEvent(event);
    unawaited(_applyIncomingUrl(event));
  }

  void _recordIncomingEvent(IncomingLinkEvent event) {
    final bannerState = _IncomingBannerState(
      event: event,
      receivedAt: DateTime.now(),
    );
    if (mounted) {
      setState(() {
        _incomingBannerState = bannerState;
      });
    } else {
      _incomingBannerState = bannerState;
    }

    _appendIncomingShareLog(
      '收到外部链接 source=${event.source} origin=${event.origin} url=${event.url}',
    );
    final nativeDebugLog = event.debugLog?.trim();
    if (nativeDebugLog != null && nativeDebugLog.isNotEmpty) {
      for (final line in nativeDebugLog.split('\n')) {
        _appendIncomingShareLog('native> $line');
      }
    }
  }

  Future<void> _applyIncomingUrl(IncomingLinkEvent event) async {
    final normalizedUrl = event.url.trim();
    if (normalizedUrl.isEmpty) {
      return;
    }

    _urlController.text = normalizedUrl;
    if (!_networkReady || _parserService == null || _isParsing) {
      _pendingIncomingUrl = normalizedUrl;
      if (mounted) {
        setState(() {
          _errorText = null;
        });
      }
      _appendIncomingShareLog(
        '延迟处理外部链接 origin=${event.origin} networkReady=$_networkReady isParsing=$_isParsing',
      );
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_applyIncomingUrl: '
        'queued source=${event.source} origin=${event.origin} networkReady=$_networkReady isParsing=$_isParsing '
        'url=$normalizedUrl',
      );
      return;
    }

    _pendingIncomingUrl = null;
    if (mounted) {
      setState(() {
        _errorText = null;
      });
    }
    debugPrint(
      'lib/source_parser/source_parser_home_page.dart#_applyIncomingUrl: '
      'parsing source=${event.source} origin=${event.origin} url=$normalizedUrl',
    );
    _appendIncomingShareLog('开始自动解析外部链接 url=$normalizedUrl');
    await _handleParse();
  }

  Future<void> _consumePendingIncomingUrlIfNeeded() async {
    final pendingUrl = _pendingIncomingUrl;
    if (pendingUrl == null || !_networkReady || _parserService == null) {
      return;
    }
    if (_isParsing) {
      return;
    }

    debugPrint(
      'lib/source_parser/source_parser_home_page.dart#_consumePendingIncomingUrlIfNeeded: '
      'resuming url=$pendingUrl',
    );
    await _applyIncomingUrl(
      IncomingLinkEvent(
        sequence: _lastHandledIncomingLinkSequence,
        url: pendingUrl,
        source: 'pending',
        origin: _incomingBannerState?.event.origin ?? 'unknown',
      ),
    );
  }

  Future<void> _openProxySettings() async {
    await showProxySettingsDialog(
      context: context,
      initialProxySpec: _savedProxySpec,
      onApply: _persistProxyAndApplyClients,
    );
  }

  Future<void> _persistProxyAndApplyClients(String? spec) async {
    await _configureIosXProxy(spec);
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

  Future<void> _configureIosXProxy(String? spec) async {
    try {
      await XLoginBridge.configureIosProxy(spec);
    } on PlatformException catch (error) {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_configureIosXProxy: '
        '无法配置 X 网页代理 code=${error.code}',
      );
      if (mounted) {
        setState(() => _errorText = error.message ?? 'X 网页代理配置失败');
      }
    }
  }

  void _handleResourceSearchChanged() {
    setState(() {});
  }

  void _handleHeaderMenuAction(_HeaderMenuAction action) {
    switch (action) {
      case _HeaderMenuAction.xLogin:
        unawaited(_openXLogin());
      case _HeaderMenuAction.xLogout:
        unawaited(_logoutX());
      case _HeaderMenuAction.downloadSettings:
        unawaited(_openDownloadSettings());
      case _HeaderMenuAction.selectDownloadDirectory:
        unawaited(_handleSelectDownloadDirectory());
      case _HeaderMenuAction.resetDownloadDirectory:
        _handleResetDownloadDirectory();
    }
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
    final parseUrl = _urlController.text.trim();
    final error = _parserService!.validate(parseUrl);
    if (error != null) {
      _appendParseResultToIncomingShareLogs(
        '解析前校验失败 url=$parseUrl message=$error',
      );
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
    _appendParseResultToIncomingShareLogs('解析开始 url=$parseUrl');

    try {
      final result = await _parserService!.parse(parseUrl);
      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
      });
      _resourceTypeTabController.index = 0;
      _logParseResult(result);
      _appendParseResultToIncomingShareLogs(
        '解析成功 platform=${result.platform.label} total=${result.resources.length} url=${result.originalUrl}',
      );
      await _saveParsedUrl(result.originalUrl);
    } on Object catch (error, stack) {
      if (!mounted) {
        return;
      }
      final message = parseFailureMessage(error);
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleParse: '
        '解析失败 type=${error.runtimeType} message=$message\n$stack',
      );
      _appendParseResultToIncomingShareLogs(
        '解析失败 url=$parseUrl message=$message',
      );
      setState(() {
        _errorText = message;
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
      await _consumePendingIncomingUrlIfNeeded();
    }
  }

  void _appendIncomingShareLog(String message) {
    final timestamp = DateTime.now();
    final line = '[${_formatClockTime(timestamp)}] $message';
    debugPrint(
      'lib/source_parser/source_parser_home_page.dart#_appendIncomingShareLog: '
      '$message',
    );
    _incomingShareLogLines.add(line);
    if (_incomingShareLogLines.length > 80) {
      _incomingShareLogLines.removeRange(0, _incomingShareLogLines.length - 80);
    }
  }

  void _appendParseResultToIncomingShareLogs(String message) {
    final bannerState = _incomingBannerState;
    if (bannerState == null) {
      return;
    }
    final currentUrl = _urlController.text.trim();
    if (currentUrl != bannerState.event.url.trim()) {
      return;
    }
    _appendIncomingShareLog(message);
  }

  String _formatClockTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  void _dismissIncomingBanner() {
    setState(() {
      _incomingBannerState = null;
    });
  }

  Future<void> _showIncomingShareLogsDialog() async {
    final text = _buildIncomingShareLogText();
    if (text == null) {
      _showPageToast('当前还没有可复制的分享接入日志');
      return;
    }

    debugPrint(text);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('分享接入日志'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: SelectableText(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showPageToast('分享接入日志已复制，可直接粘贴给我');
              },
              child: const Text('复制日志'),
            ),
          ],
        );
      },
    );
  }

  String? _buildIncomingShareLogText() {
    if (_incomingShareLogLines.isEmpty) {
      return null;
    }
    final bannerState = _incomingBannerState;
    return [
      '[Share Intake Debug Log]',
      if (bannerState != null) 'label=${bannerState.label}',
      if (bannerState != null) 'origin=${bannerState.event.origin}',
      if (bannerState != null) 'source=${bannerState.event.source}',
      if (bannerState != null) 'url=${bannerState.event.url}',
      '---',
      ..._incomingShareLogLines,
    ].join('\n');
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
      _showPageToast('已在浏览器打开');
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
    _showPageToast('打开浏览器失败：$message');
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

  Future<void> _handleDownload(SourceResource resource) async {
    if (Platform.isIOS && resource.requiresFfmpegPostProcess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('iOS 暂不支持 HLS / DASH 清单下载，请选择 MP4 资源')),
      );
      return;
    }
    if (_resolvingResourceUrls.contains(resource.url)) {
      return;
    }
    if (!Platform.isIOS && _needsDownloadPreflightToast(resource)) {
      _showPageToast('已开启后台解析，正在确认资源是否可下载');
    }
    setState(() => _resolvingResourceUrls.add(resource.url));
    late final XVideoPreflightResult preflightResult;
    try {
      preflightResult = await _maybeProbeXVideoBeforeDownload(resource);
    } finally {
      if (mounted) {
        setState(() => _resolvingResourceUrls.remove(resource.url));
      }
    }

    if (!mounted) {
      return;
    }
    if (!preflightResult.ok) {
      await _showXPreflightFailureDialog(resource, preflightResult);
      return;
    }
    if (resource.requiresFfmpegPostProcess) {
      final confirmed = await _showDownloadPreparationPrompt(resource);
      if (confirmed != true || !mounted) {
        return;
      }
    }
    _enqueueDownload(resource);
  }

  bool _needsDownloadPreflightToast(SourceResource resource) {
    return resource.requiresYtDlp && resource.platform == SourcePlatform.x;
  }

  void _enqueueDownload(SourceResource resource) {
    final task = _downloadQueueController!.enqueue(resource);
    setState(() {
      _downloadPanelOpen = true;
    });
    _showPageToast('已加入下载队列：${task.fileName}');
  }

  Future<XVideoPreflightResult> _maybeProbeXVideoBeforeDownload(
    SourceResource resource,
  ) async {
    if (Platform.isIOS) {
      return const XVideoPreflightResult(errorMessage: null);
    }
    if (!resource.requiresYtDlp || resource.platform != SourcePlatform.x) {
      return const XVideoPreflightResult(errorMessage: null);
    }

    final probe = widget.xVideoPreflightProbe ?? _defaultXVideoPreflightProbe;
    return probe(resource);
  }

  Future<XVideoPreflightResult> _defaultXVideoPreflightProbe(
    SourceResource resource,
  ) async {
    if (Platform.isMacOS) {
      try {
        final result = await XLoginBridge.withCookieFile(
          (cookieFilePath) =>
              _runXVideoPreflight(resource, appCookieFilePath: cookieFilePath),
        );
        if (result != null) {
          return result;
        }
      } on PlatformException catch (error) {
        debugPrint(
          'lib/source_parser/source_parser_home_page.dart#_defaultXVideoPreflightProbe: '
          'app login session unavailable error=${error.code}',
        );
      } on MissingPluginException {
        // Unit tests and non-macOS hosts do not register the native login bridge.
      }
    }
    return _runXVideoPreflight(resource);
  }

  Future<XVideoPreflightResult> _runXVideoPreflight(
    SourceResource resource, {
    String? appCookieFilePath,
  }) async {
    final attempts = _buildXPreflightAttempts(
      resource,
      appCookieFilePath: appCookieFilePath,
    );
    final logs = <String>[];
    XVideoPreflightResult? lastFailure;

    for (final attempt in attempts) {
      try {
        final result = await Process.run(
          _findExistingExecutablePath(_probeExecutableCandidates('yt-dlp')) ??
              'yt-dlp',
          attempt.args,
        );
        final err = (result.stderr ?? '').toString().trim();
        final out = (result.stdout ?? '').toString().trim();
        logs.add(
          _buildXPreflightDebugLog(
            resource: resource,
            label: attempt.label,
            args: attempt.args,
            exitCode: result.exitCode,
            stdoutText: out,
            stderrText: err,
          ),
        );
        if (result.exitCode == 0) {
          return XVideoPreflightResult(
            errorMessage: null,
            debugLog: logs.join('\n\n'),
          );
        }

        final detail = err.isNotEmpty ? err : out;
        lastFailure = XVideoPreflightResult(
          errorMessage: _friendlyXPreflightError(detail, result.exitCode),
          debugLog: logs.join('\n\n'),
        );
      } on ProcessException catch (error) {
        final detail = error.message;
        logs.add(
          _buildXPreflightDebugLog(
            resource: resource,
            label: attempt.label,
            args: attempt.args,
            processError: error.toString(),
          ),
        );
        if (detail.contains('Operation not permitted')) {
          return XVideoPreflightResult(
            errorMessage: '当前环境禁止执行外部命令，暂时无法预检 X 视频，请调整运行环境后重试',
            debugLog: logs.join('\n\n'),
          );
        }
        if (_looksLikeMissingBrowserCookies(detail)) {
          lastFailure = XVideoPreflightResult(
            errorMessage: '当前浏览器登录态不可用，正在尝试其他 X 预检方式',
            debugLog: logs.join('\n\n'),
          );
          continue;
        }
        return XVideoPreflightResult(
          errorMessage: '未检测到 yt-dlp，当前无法预检 X 视频，请先安装后重试',
          debugLog: logs.join('\n\n'),
        );
      } on Object catch (error) {
        logs.add(
          _buildXPreflightDebugLog(
            resource: resource,
            label: attempt.label,
            args: attempt.args,
            processError: error.toString(),
          ),
        );
        return XVideoPreflightResult(
          errorMessage: '预检 X 视频时失败：$error',
          debugLog: logs.join('\n\n'),
        );
      }
    }

    return lastFailure ??
        XVideoPreflightResult(
          errorMessage: 'X 视频预检失败：所有尝试均未成功',
          debugLog: logs.join('\n\n'),
        );
  }

  String _friendlyXPreflightError(String raw, int exitCode) {
    if (raw.contains('No video could be found in this tweet')) {
      return '这条推文当前没有检测到可下载的视频媒体，已阻止加入下载队列。可能是图片推文、纯文本推文，或公开页面未暴露视频资源。';
    }
    if (raw.contains('Login required') ||
        raw.contains('Sign in to confirm') ||
        raw.contains('requested tweet may only be available')) {
      return '这条 X 内容可能需要登录或受可见性限制，已阻止加入下载队列。请先确认浏览器中可以正常访问。';
    }
    if (raw.contains('Private') || raw.contains('private')) {
      return '这条推文可能是私密内容，已阻止加入下载队列。';
    }
    if (raw.contains('404') || raw.contains('not found')) {
      return '这条推文不存在、已删除或当前不可见，已阻止加入下载队列。';
    }
    return 'X 视频预检失败(exit=$exitCode)：$raw';
  }

  String _buildXPreflightDebugLog({
    required SourceResource resource,
    String? label,
    required List<String> args,
    int? exitCode,
    String? stdoutText,
    String? stderrText,
    String? processError,
  }) {
    return [
      '[X Preflight Debug Log]',
      'url=${resource.url}',
      'title=${resource.title}',
      'platform=${resource.platform.name}',
      if (label != null) 'attempt=$label',
      'args=yt-dlp ${args.join(' ')}',
      if (exitCode != null) 'exitCode=$exitCode',
      if (processError != null && processError.isNotEmpty)
        'processError=$processError',
      '---',
      if (stdoutText != null && stdoutText.isNotEmpty) '[stdout]\n$stdoutText',
      if (stderrText != null && stderrText.isNotEmpty) '[stderr]\n$stderrText',
    ].join('\n');
  }

  List<_XPreflightAttempt> _buildXPreflightAttempts(
    SourceResource resource, {
    String? appCookieFilePath,
  }) {
    const browsers = <String>['chrome', 'edge', 'chromium', 'brave'];
    const apis = <String>['graphql', 'syndication'];
    final attempts = <_XPreflightAttempt>[];

    if (appCookieFilePath != null) {
      for (final api in apis) {
        attempts.add(
          _XPreflightAttempt(
            label: 'app-login api:$api',
            args: [
              '--simulate',
              '--no-playlist',
              '--cookies',
              appCookieFilePath,
              '--extractor-args',
              'twitter:api=$api',
              resource.url,
            ],
          ),
        );
      }
    }

    for (final browser in browsers) {
      for (final api in apis) {
        attempts.add(
          _XPreflightAttempt(
            label: 'cookies:$browser api:$api',
            args: [
              '--simulate',
              '--no-playlist',
              '--cookies-from-browser',
              browser,
              '--extractor-args',
              'twitter:api=$api',
              resource.url,
            ],
          ),
        );
      }
    }

    for (final api in apis) {
      attempts.add(
        _XPreflightAttempt(
          label: 'anonymous api:$api',
          args: [
            '--simulate',
            '--no-playlist',
            '--extractor-args',
            'twitter:api=$api',
            resource.url,
          ],
        ),
      );
    }

    return attempts;
  }

  bool _looksLikeMissingBrowserCookies(String raw) {
    return raw.contains('could not find chrome cookies database') ||
        raw.contains('Could not copy Chrome cookie database') ||
        raw.contains('browser is not supported') ||
        raw.contains('could not find edge cookies database') ||
        raw.contains('Failed to decrypt with DPAPI') ||
        raw.contains('Failed to decrypt');
  }

  Future<void> _showXPreflightFailureDialog(
    SourceResource resource,
    XVideoPreflightResult result,
  ) async {
    debugPrint(
      'lib/source_parser/source_parser_home_page.dart#_showXPreflightFailureDialog: '
      'url=${resource.url} message=${result.errorMessage}',
    );
    final debugLog = result.debugLog?.trim();
    if (debugLog != null && debugLog.isNotEmpty) {
      debugPrint(debugLog);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('X 视频预检失败'),
          content: Text(result.errorMessage ?? '预检失败'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
            if (Platform.isMacOS)
              TextButton.icon(
                onPressed: () => _loginXAndRetry(resource, dialogContext),
                icon: const Icon(Icons.login),
                label: const Text('在应用内登录 X'),
              ),
            if (debugLog != null && debugLog.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: debugLog));
                  if (!mounted) {
                    return;
                  }
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  _showPageToast('预检日志已复制，可直接粘贴给我');
                },
                child: const Text('复制日志'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _loginXAndRetry(
    SourceResource resource,
    BuildContext dialogContext,
  ) async {
    Navigator.of(dialogContext).pop();
    try {
      final authenticated = await XLoginBridge.openLogin();
      await _refreshXAccountStatus();
      if (!mounted) {
        return;
      }
      if (!authenticated) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未检测到 X 登录状态，请登录后重试')));
        return;
      }

      final result = await _maybeProbeXVideoBeforeDownload(resource);
      if (!mounted) {
        return;
      }
      if (result.ok) {
        _enqueueDownload(resource);
      } else {
        await _showXPreflightFailureDialog(resource, result);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('X 登录流程失败：$error')));
    }
  }

  Future<bool?> _showDownloadPreparationPrompt(SourceResource resource) {
    final ffmpegReady =
        _downloadToolStatus.ffmpegAvailable &&
        !_downloadToolStatus.externalCommandBlocked;
    final lines = <String>[
      if (resource.likelyHlsManifest) '这是一个 HLS 播放列表资源，下载后通常还需要整理封装。',
      if (resource.isDashManifest) '这是一个 DASH 清单资源，下载后通常还需要额外处理。',
      if (ffmpegReady)
        '当前已检测到 ffmpeg，后续可在历史记录里继续转 MP4。'
      else if (_downloadToolStatus.externalCommandBlocked)
        '当前环境禁止执行 ffmpeg，下载后暂时无法在应用内转 MP4。'
      else
        '当前未检测到 ffmpeg，下载后若要转 MP4，需要先安装 ffmpeg。',
    ];

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('下载前提示'),
          content: Text(lines.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续下载'),
            ),
          ],
        );
      },
    );
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

  int _activeActivityBadgeCount() {
    final downloadCount = _downloadQueueController!.tasks
        .where(
          (task) =>
              task.status == DownloadStatus.pending ||
              task.status == DownloadStatus.downloading,
        )
        .length;
    final conversionCount = _mediaConversionController!.tasks
        .where(
          (task) =>
              task.status == MediaConversionStatus.pending ||
              task.status == MediaConversionStatus.converting,
        )
        .length;
    return downloadCount + conversionCount;
  }

  Future<void> _handleSelectDownloadDirectory() async {
    if (Platform.isIOS) {
      await showIosDownloadInfo(context);
      return;
    }
    final directoryPath = await getDirectoryPath(confirmButtonText: '选择保存目录');
    if (directoryPath == null || directoryPath.trim().isEmpty) {
      return;
    }

    _downloadQueueController!.setDownloadDirectory(directoryPath);
  }

  void _handleResetDownloadDirectory() {
    _downloadQueueController!.resetDownloadDirectory();
  }

  Future<void> _recordHistoryEntry(DownloadHistoryRecord record) async {
    await _downloadQueueController!.addHistoryRecord(record);
  }

  Future<void> _handleOpenDownloadedFolder(DownloadTask task) async {
    final fileLabel = pathLogLabel(task.filePath ?? task.fileName);
    try {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleOpenDownloadedFolder: '
        'click file=$fileLabel status=${task.status.name}',
      );
      await _downloadQueueController!.openDownloadedFolder(task);
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleOpenDownloadedFolder: '
        'success file=$fileLabel',
      );
    } on Object catch (error) {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleOpenDownloadedFolder: '
        'failed file=$fileLabel error=$error',
      );
      if (!mounted) {
        return;
      }

      _showPageToast(Platform.isIOS ? '分享文件失败：$error' : '打开文件夹失败：$error');
    }
  }

  Future<void> _handleOpenHistoryFolder(DownloadHistoryRecord record) async {
    final fileLabel = pathLogLabel(record.filePath);
    try {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleOpenHistoryFolder: '
        'click file=$fileLabel',
      );
      await _downloadQueueController!.openHistoryFolder(record);
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleOpenHistoryFolder: '
        'success file=$fileLabel',
      );
    } on Object catch (error) {
      debugPrint(
        'lib/source_parser/source_parser_home_page.dart#_handleOpenHistoryFolder: '
        'failed file=$fileLabel error=$error',
      );
      if (!mounted) {
        return;
      }

      _showPageToast(Platform.isIOS ? '分享文件失败：$error' : '打开历史文件夹失败：$error');
    }
  }

  Future<void> _handleRemoveHistory(DownloadHistoryRecord record) async {
    try {
      await _downloadQueueController!.removeHistory(record.filePath);
    } on Object catch (error) {
      debugPrint(
        'source_parser_home_page.dart#_handleRemoveHistory: 删除记录失败 error=$error',
      );
      if (mounted) _showPageToast('删除记录失败：$error');
    }
  }

  void _openDownloadedFiles() {
    _closeDownloadPanel();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DownloadedFilesPage(queue: _downloadQueueController!),
      ),
    );
  }

  void _handleConvertHistoryToMp4(DownloadHistoryRecord record) {
    if (_downloadToolStatus.externalCommandBlocked) {
      _showPageToast('当前环境禁止执行 ffmpeg，暂时无法转 MP4');
      return;
    }
    if (!_downloadToolStatus.ffmpegAvailable) {
      _showPageToast('未检测到 ffmpeg，无法转 MP4');
      return;
    }

    final task = _mediaConversionController!.enqueueM3u8ToMp4(record);
    setState(() {
      _downloadPanelOpen = true;
    });
    _showPageToast('已加入转换队列：${task.outputFileName}');
  }

  Future<void> _handleOpenConvertedFolder(MediaConversionTask task) async {
    final outputFilePath = task.outputFilePath;
    if (outputFilePath == null) {
      return;
    }

    try {
      await _downloadQueueController!.openHistoryFolder(
        DownloadHistoryRecord(
          fileName: task.outputFileName,
          filePath: outputFilePath,
          sourceUrl: task.inputRecord.sourceUrl,
          completedAt: DateTime.now(),
        ),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      _showPageToast('打开转换结果失败：$error');
    }
  }

  Future<void> _handleCopyTaskLogs(DownloadTask task) async {
    final logs = task.logText.trim();
    if (logs.isEmpty) {
      _showPageToast('当前任务暂无可复制日志');
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
    _showPageToast('下载日志已复制，可直接粘贴给我');
  }

  Future<void> _handleCopyConversionLogs(MediaConversionTask task) async {
    final logs = task.logText.trim();
    if (logs.isEmpty) {
      _showPageToast('当前转换任务暂无可复制日志');
      return;
    }

    final text = [
      '[Conversion Debug Log]',
      'taskId=${task.id}',
      'status=${task.status.name}',
      'input=${pathLogLabel(task.inputRecord.filePath)}',
      'output=${pathLogLabel(task.outputFilePath ?? task.outputFileName)}',
      if (task.failureSummary != null) 'summary=${task.failureSummary}',
      if (task.errorMessage != null) 'error=${task.errorMessage}',
      '---',
      logs,
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _showPageToast('转换日志已复制，可直接粘贴给我');
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
                            _buildResultSection(context),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              AnimatedBuilder(
                animation: Listenable.merge([
                  _downloadQueueController!,
                  _mediaConversionController!,
                ]),
                builder: (context, _) {
                  final controller = _downloadQueueController!;
                  return DownloadActivityOverlay(
                    panelOpen: _downloadPanelOpen,
                    onTogglePanel: _toggleDownloadPanel,
                    onClosePanel: _closeDownloadPanel,
                    activeTaskCount: _activeActivityBadgeCount(),
                    queuePanel: DownloadQueuePanel(
                      tasks: controller.tasks,
                      onCancel: controller.cancel,
                      onRetry: controller.retry,
                      onOpenFolder: _handleOpenDownloadedFolder,
                      onCopyLogs: _handleCopyTaskLogs,
                      onRemove: controller.removeTask,
                      onClearFinished: controller.clearFinishedTasks,
                    ),
                    conversionPanel: Platform.isIOS
                        ? null
                        : MediaConversionPanel(
                            tasks: _mediaConversionController!.tasks,
                            onCancel: _mediaConversionController!.cancel,
                            onRetry: _mediaConversionController!.retry,
                            onOpenFolder: _handleOpenConvertedFolder,
                            onCopyLogs: _handleCopyConversionLogs,
                          ),
                    historyPanel: DownloadHistoryPanel(
                      records: controller.history,
                      onOpenFolder: _handleOpenHistoryFolder,
                      onConvertToMp4: _handleConvertHistoryToMp4,
                      onClear: controller.clearHistory,
                      canConvertToMp4: !Platform.isIOS,
                      onRemove: (record) => _handleRemoveHistory(record),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final identity = _buildHeaderIdentity(context);
        final actions = _buildHeaderActions(context);
        if (constraints.maxWidth >= 600) {
          return Row(
            children: [
              Expanded(child: identity),
              actions,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      },
    );
  }

  Widget _buildHeaderIdentity(BuildContext context) {
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
      ],
    );
  }

  Widget _buildHeaderActions(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      children: [
        TextButton.icon(
          key: const ValueKey('downloaded-files-button'),
          onPressed: _openDownloadedFiles,
          icon: const Icon(Icons.video_library_outlined),
          label: const Text('文件'),
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
        if (Platform.isMacOS || Platform.isIOS)
          PopupMenuButton<_HeaderMenuAction>(
            key: const ValueKey('x-account-menu-button'),
            tooltip: _xAuthenticated
                ? 'X 已登录${_xAccountHandle == null ? '' : ' · $_xAccountHandle'}'
                : (_xAccountStatusLoaded ? 'X 未登录' : '正在检查 X 登录状态'),
            icon: Icon(
              _xAuthenticated ? Icons.account_circle : Icons.person_outline,
            ),
            onSelected: _handleHeaderMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem<_HeaderMenuAction>(
                enabled: false,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _xAuthenticated
                        ? Icons.account_circle
                        : Icons.person_outline,
                  ),
                  title: Text(
                    _xAuthenticated
                        ? (_xDisplayName?.isNotEmpty == true
                              ? _xDisplayName!
                              : 'X 已登录')
                        : (_xAccountStatusLoaded ? 'X 未登录' : '正在检查 X 登录状态'),
                  ),
                  subtitle: _xAuthenticated && _xAccountHandle != null
                      ? Text(_xAccountHandle!)
                      : null,
                ),
              ),
              PopupMenuItem<_HeaderMenuAction>(
                value: _xAuthenticated
                    ? _HeaderMenuAction.xLogout
                    : _HeaderMenuAction.xLogin,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_xAuthenticated ? Icons.logout : Icons.login),
                  title: Text(_xAuthenticated ? '退出 X 登录' : '登录 X'),
                ),
              ),
            ],
          ),
        PopupMenuButton<_HeaderMenuAction>(
          key: const ValueKey('header-settings-menu-button'),
          tooltip: '更多设置',
          onSelected: _handleHeaderMenuAction,
          itemBuilder: (context) {
            final hasSelectedDirectory =
                _downloadQueueController?.selectedDirectoryPath != null;
            return [
              const PopupMenuItem<_HeaderMenuAction>(
                value: _HeaderMenuAction.downloadSettings,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune),
                  title: Text('下载设置'),
                ),
              ),
              if (!Platform.isIOS)
                const PopupMenuItem<_HeaderMenuAction>(
                  value: _HeaderMenuAction.selectDownloadDirectory,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.folder_open),
                    title: Text('选择保存目录'),
                  ),
                ),
              if (!Platform.isIOS)
                PopupMenuItem<_HeaderMenuAction>(
                  value: _HeaderMenuAction.resetDownloadDirectory,
                  enabled: hasSelectedDirectory,
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.restart_alt),
                    title: Text('重置保存目录'),
                  ),
                ),
            ];
          },
        ),
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
            if (_incomingBannerState != null) ...[
              _buildIncomingBanner(context, _incomingBannerState!),
              const SizedBox(height: 14),
            ],
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
            ParserActionBar(
              hints: _buildPlatformHints(context),
              isParsing: _isParsing,
              onOpenBrowser: _handleOpenInBrowser,
              onParse: _handleParse,
            ),
            if (_recentUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('open-recent-urls-button'),
                  onPressed: _openRecentUrlHistory,
                  icon: const Icon(Icons.history),
                  label: Text('最近解析 (${_recentUrls.length})'),
                ),
              ),
            ],
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
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingBanner(
    BuildContext context,
    _IncomingBannerState bannerState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('incoming-link-banner'),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.ios_share, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bannerState.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '已自动填入链接并开始解析，你可以随时查看这次接入日志。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('show-incoming-link-logs-button'),
                onPressed: _showIncomingShareLogsDialog,
                child: const Text('查看日志'),
              ),
              IconButton(
                key: const ValueKey('dismiss-incoming-link-banner-button'),
                tooltip: '隐藏提示',
                onPressed: _dismissIncomingBanner,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openRecentUrlHistory() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final recentUrls = _recentUrls;
            return AlertDialog(
              title: const Text('最近解析'),
              content: SizedBox(
                width: 560,
                child: recentUrls.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('当前还没有最近解析记录'),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: recentUrls.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final url = recentUrls[index];
                            return ListTile(
                              key: ValueKey('recent-url-$url'),
                              leading: const Icon(Icons.history),
                              title: Text(
                                url,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                _selectRecentUrl(url);
                                Navigator.of(dialogContext).pop();
                              },
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
                TextButton.icon(
                  key: const ValueKey('clear-parse-history-button'),
                  onPressed: recentUrls.isEmpty
                      ? null
                      : () async {
                          await _clearRecentUrls();
                          if (!mounted) {
                            return;
                          }
                          setDialogState(() {});
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清空'),
                ),
              ],
            );
          },
        );
      },
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
              isResolving: _resolvingResourceUrls.contains(resource.url),
              onDownload: () => _handleDownload(resource),
            ),
            if (resource != resources.last) const Divider(height: 14),
          ],
        ],
      ),
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
              Platform.isIOS
                  ? '可解析媒体直链、X 公开视频和 YouTube；其他网页按源码提取资源。'
                  : '支持抖音、X、YouTube、Bilibili，其他来源会归入其他分类。',
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
