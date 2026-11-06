import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'download_history_store.dart';
import 'download_settings.dart';
import 'download_engines/x_download_engine.dart';
import 'download_engines/youtube_download_engine.dart';
import 'path_log_label.dart';
import 'reveal_in_finder_macos.dart';
import 'source_resource.dart';
import 'ios/ios_media_bridge.dart';
import 'ios/ios_youtube_download_engine.dart';

typedef DownloadDirectoryResolver = Future<Directory> Function();
typedef FolderOpener = Future<void> Function(String path);
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

enum DownloadStatus {
  pending('等待中'),
  downloading('下载中'),
  completed('已完成'),
  failed('失败'),
  canceled('已取消');

  const DownloadStatus(this.displayName);

  final String displayName;
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.resource,
    required this.fileName,
  });

  final String id;
  final SourceResource resource;
  String fileName;

  DownloadStatus status = DownloadStatus.pending;
  double progress = 0;
  int receivedBytes = 0;
  int? totalBytes;
  String? filePath;
  String? errorMessage;

  /// 当前步骤说明（仅下载进行中时使用，结束后清空）。
  String? statusDetail;

  /// 本次进入「下载中」状态的时间，用于 UI 展示等待时长。
  DateTime? activeStartedAt;
  final List<String> _logs = [];

  List<String> get logs => List.unmodifiable(_logs);

  void clearLogs() {
    _logs.clear();
  }

  void addLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _logs.add('[$timestamp] $message');
  }

  String get logText => _logs.join('\n');

  String get progressLabel {
    final total = totalBytes;
    if (status == DownloadStatus.completed) {
      return '100%';
    }

    if (status == DownloadStatus.pending) {
      return '排队等待中…';
    }

    if (status == DownloadStatus.downloading) {
      final waitSec = _connectingElapsedSeconds;
      if (total != null && total > 0 && receivedBytes == 0) {
        return '0% · 0 B / ${_formatBytes(total)}（缓冲中，已等待 ${waitSec}s）';
      }
      if ((total == null || total <= 0) && receivedBytes == 0) {
        return '连接资源中（已等待 ${waitSec}s；若持续较久请检查网络或代理）…';
      }
    }

    if (total == null || total <= 0) {
      return receivedBytes > 0
          ? '已接收 ${_formatBytes(receivedBytes)}（总大小未知）'
          : '连接资源中…';
    }

    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return '$percent% · ${_formatBytes(receivedBytes)} / ${_formatBytes(total)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }

    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  int get _connectingElapsedSeconds {
    final start = activeStartedAt;
    if (start == null) {
      return 0;
    }
    return DateTime.now().difference(start).inSeconds;
  }
}

final class _PollOutcome<T> {
  const _PollOutcome(this.value);
  final T value;
}

class DownloadQueueController extends ChangeNotifier {
  DownloadQueueController({
    http.Client? client,
    bool? ownClient,
    DownloadDirectoryResolver? downloadDirectoryResolver,
    FolderOpener? folderOpener,
    DownloadHistoryStore? downloadHistoryStore,
    ProcessRunner? processRunner,
    ProcessStarter? processStarter,
    DownloadSettings? downloadSettings,

    /// 为 `true` 时直连下载使用 `dart:io` [HttpClient]，可在连接阶段通过 [cancel] 中断。
    /// 单元测试若使用 [MockClient]，请设为 `false`。
    bool useIoHttpClientForDirectDownloads = true,
  }) : _client = client ?? http.Client(),
       _ownsClient = ownClient ?? (client == null),
       _folderOpener = folderOpener ?? _defaultFolderOpener,
       _downloadHistoryStore = downloadHistoryStore ?? DownloadHistoryStore(),
       _processRunner = processRunner ?? _defaultProcessRunner,
       _processStarter = processStarter ?? _defaultProcessStarter,
       _settings = downloadSettings ?? const DownloadSettings.defaults(),
       _downloadDirectoryResolver =
           downloadDirectoryResolver ?? _defaultDownloadDirectory,
       _useIoHttpClientForDirectDownloads = useIoHttpClientForDirectDownloads {
    unawaited(_loadDownloadHistory());
  }

  http.Client _client;
  bool _ownsClient;
  final bool _useIoHttpClientForDirectDownloads;
  final FolderOpener _folderOpener;
  final DownloadHistoryStore _downloadHistoryStore;
  final ProcessRunner _processRunner;
  final ProcessStarter _processStarter;
  DownloadSettings _settings;
  final DownloadDirectoryResolver _downloadDirectoryResolver;
  final List<DownloadTask> _tasks = [];
  final List<DownloadHistoryRecord> _history = [];
  final Set<String> _cancelRequestedTaskIds = {};

  Directory? _selectedDirectory;
  bool _isRunning = false;
  Timer? _downloadElapsedTicker;
  HttpClient? _activeDownloadHttpClient;
  DownloadTask? _activeTask;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  List<DownloadHistoryRecord> get history => List.unmodifiable(_history);
  bool get hasTasks => _tasks.isNotEmpty;
  bool get hasHistory => _history.isNotEmpty;
  String? get selectedDirectoryPath => _selectedDirectory?.path;
  DownloadSettings get settings => _settings;
  Set<String> get activeFilePaths => {
    if (_activeTask?.status == DownloadStatus.downloading)
      if (_activeTask?.filePath case final String path) path,
  };

  Future<List<Directory>> fileDirectories() async => [
    await _downloadDirectoryResolver(),
    ?_selectedDirectory,
    for (final record in _history) File(record.filePath).parent,
  ];

  void removeTask(DownloadTask task) {
    if (!_tasks.contains(task)) return;
    cancel(task);
    _tasks.remove(task);
    notifyListeners();
  }

  void clearFinishedTasks() {
    _tasks.removeWhere(
      (task) =>
          task.status != DownloadStatus.pending &&
          task.status != DownloadStatus.downloading,
    );
    notifyListeners();
  }

  Future<void> removeHistory(String path) async {
    final records = await _downloadHistoryStore.remove(path);
    _history
      ..clear()
      ..addAll(records);
    notifyListeners();
  }

  Future<void> removeFileRecords(String path) async {
    await removeHistory(path);
    _tasks.removeWhere(
      (task) =>
          task.filePath == path && task.status == DownloadStatus.completed,
    );
    notifyListeners();
  }

  Future<void> updateDownloadSettings(DownloadSettings settings) async {
    _settings = settings;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopDownloadElapsedTicker();
    try {
      _activeDownloadHttpClient?.close(force: true);
    } on Object {
      // ignore
    }
    _activeDownloadHttpClient = null;
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  void replaceHttpClient(http.Client newClient) {
    if (_ownsClient) {
      _client.close();
    }

    _client = newClient;
    _ownsClient = true;
    notifyListeners();
  }

  DownloadTask enqueue(SourceResource resource) {
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      resource: resource,
      fileName: _fileNameFor(resource),
    );

    _tasks.insert(0, task);
    notifyListeners();
    unawaited(_runNext());
    return task;
  }

  void setDownloadDirectory(String path) {
    _selectedDirectory = Directory(path);
    notifyListeners();
  }

  void resetDownloadDirectory() {
    _selectedDirectory = null;
    notifyListeners();
  }

  void cancel(DownloadTask task) {
    if (task.status == DownloadStatus.pending) {
      task.status = DownloadStatus.canceled;
      notifyListeners();
      return;
    }

    if (task.status == DownloadStatus.downloading) {
      _cancelRequestedTaskIds.add(task.id);
      try {
        _activeDownloadHttpClient?.close(force: true);
      } on Object {
        // ignore
      }
      notifyListeners();
    }
  }

  /// 将失败或已取消任务重新加入待下载队列（保留同一 [DownloadTask] 与 [id]）。
  void retry(DownloadTask task) {
    if (task.status != DownloadStatus.failed &&
        task.status != DownloadStatus.canceled) {
      return;
    }

    task.status = DownloadStatus.pending;
    task.progress = 0;
    task.receivedBytes = 0;
    task.totalBytes = null;
    task.filePath = null;
    task.errorMessage = null;
    task.statusDetail = null;
    task.activeStartedAt = null;
    task.fileName = _fileNameFor(task.resource);
    task.clearLogs();
    task.addLog(
      'lib/source_parser/download_queue_controller.dart#retry: 用户触发重试',
    );
    _cancelRequestedTaskIds.remove(task.id);
    notifyListeners();
    unawaited(_runNext());
  }

  Future<void> openDownloadedFolder(DownloadTask task) async {
    final filePath = task.filePath;
    if (filePath == null || task.status != DownloadStatus.completed) {
      throw const DownloadException('下载完成后才能打开文件夹');
    }
    if (!await File(filePath).exists()) {
      throw DownloadException('下载文件不存在，可能已被移动或删除：${pathLogLabel(filePath)}');
    }
    final directoryPath = _containingDirectoryPathFor(filePath);
    final fileLabel = pathLogLabel(filePath);
    final directoryLabel = pathLogLabel(directoryPath);
    task.addLog(
      'lib/source_parser/download_queue_controller.dart#openDownloadedFolder: '
      'request file=$fileLabel directory=$directoryLabel',
    );
    debugPrint(
      'lib/source_parser/download_queue_controller.dart#openDownloadedFolder: '
      'request file=$fileLabel directory=$directoryLabel',
    );
    try {
      await _folderOpener(filePath);
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#openDownloadedFolder: '
        'success file=$fileLabel directory=$directoryLabel',
      );
      debugPrint(
        'lib/source_parser/download_queue_controller.dart#openDownloadedFolder: '
        'success file=$fileLabel directory=$directoryLabel',
      );
    } on Object catch (error) {
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#openDownloadedFolder: '
        'failed file=$fileLabel directory=$directoryLabel error=$error',
      );
      debugPrint(
        'lib/source_parser/download_queue_controller.dart#openDownloadedFolder: '
        'failed file=$fileLabel directory=$directoryLabel error=$error',
      );
      rethrow;
    }
  }

  Future<void> openHistoryFolder(DownloadHistoryRecord record) async {
    final file = File(record.filePath);
    if (!await file.exists()) {
      throw DownloadException(
        '历史文件不存在，可能已被移动或删除：${pathLogLabel(record.filePath)}',
      );
    }
    final directoryPath = _containingDirectoryPathFor(record.filePath);
    final fileLabel = pathLogLabel(record.filePath);
    final directoryLabel = pathLogLabel(directoryPath);
    debugPrint(
      'lib/source_parser/download_queue_controller.dart#openHistoryFolder: '
      'request file=$fileLabel directory=$directoryLabel',
    );
    try {
      await _folderOpener(record.filePath);
      debugPrint(
        'lib/source_parser/download_queue_controller.dart#openHistoryFolder: '
        'success file=$fileLabel directory=$directoryLabel',
      );
    } on Object catch (error) {
      debugPrint(
        'lib/source_parser/download_queue_controller.dart#openHistoryFolder: '
        'failed file=$fileLabel directory=$directoryLabel error=$error',
      );
      rethrow;
    }
  }

  Future<void> clearHistory() async {
    await _downloadHistoryStore.clear();
    _history.clear();
    notifyListeners();
  }

  Future<void> addHistoryRecord(DownloadHistoryRecord record) async {
    final records = await _downloadHistoryStore.add(record);
    _history
      ..clear()
      ..addAll(records);
    notifyListeners();
  }

  Future<void> _loadDownloadHistory() async {
    final records = await _downloadHistoryStore.load();
    _history
      ..clear()
      ..addAll(records);
    notifyListeners();
  }

  Future<void> _runNext() async {
    if (_isRunning) {
      return;
    }

    final task = _tasks.reversed
        .where((item) => item.status == DownloadStatus.pending)
        .firstOrNull;
    if (task == null) {
      return;
    }

    _isRunning = true;
    await _download(task);
    _isRunning = false;
    unawaited(_runNext());
  }

  Future<void> _download(DownloadTask task) async {
    File? outputFile;
    _activeTask = task;
    try {
      task.clearLogs();
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#_download: start url=${task.resource.url}',
      );
      task.status = DownloadStatus.downloading;
      task.errorMessage = null;
      task.statusDetail = '准备下载…';
      task.activeStartedAt = DateTime.now();
      _startDownloadElapsedTicker();
      notifyListeners();

      final directory =
          _selectedDirectory ?? await _downloadDirectoryResolver();
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#_download: directory=${pathLogLabel(directory.path)}',
      );
      await directory.create(recursive: true);

      if (task.resource.youtubeVideoId != null) {
        task.addLog(
          'lib/source_parser/download_queue_controller.dart#_download: engine=youtube',
        );
        outputFile = await _downloadYouTube(task, directory);
      } else if (task.resource.requiresYtDlp) {
        if (Platform.isIOS) {
          throw const DownloadException('请重新解析该链接，iOS 使用应用内下载引擎');
        }
        task.addLog(
          'lib/source_parser/download_queue_controller.dart#_download: engine=x_yt_dlp',
        );
        outputFile = await _downloadX(task, directory);
      } else {
        task.addLog(
          'lib/source_parser/download_queue_controller.dart#_download: engine=http',
        );
        outputFile = await _downloadHttp(task, directory);
      }
      await _validateDownloadedFile(task, outputFile);
      if (_cancelRequestedTaskIds.contains(task.id)) {
        throw const DownloadCanceledException();
      }

      task.progress = 1;
      task.status = DownloadStatus.completed;
      task.statusDetail = null;
      task.activeStartedAt = null;
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#_download: completed file=${pathLogLabel(task.filePath ?? '-')}',
      );
      await _recordCompletedDownload(task);
      notifyListeners();
    } on DownloadCanceledException {
      _cancelRequestedTaskIds.remove(task.id);
      task.status = DownloadStatus.canceled;
      task.errorMessage = null;
      task.statusDetail = null;
      task.activeStartedAt = null;
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#_download: canceled by user',
      );
      await outputFile?.deleteIfExists();
      notifyListeners();
    } on Object catch (error) {
      task.status = DownloadStatus.failed;
      task.errorMessage = _friendlyDownloadError(error);
      task.statusDetail = null;
      task.activeStartedAt = null;
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#_download: failed error=$error',
      );
      await outputFile?.deleteIfExists();
      notifyListeners();
    } finally {
      _activeTask = null;
      _cancelRequestedTaskIds.remove(task.id);
      _stopDownloadElapsedTicker();
    }
  }

  Future<void> _validateDownloadedFile(
    DownloadTask task,
    File? outputFile,
  ) async {
    if (outputFile == null) {
      throw const DownloadException('下载未生成输出文件');
    }
    if (!await outputFile.exists()) {
      throw DownloadException('下载输出文件不存在：${pathLogLabel(outputFile.path)}');
    }
    final fileSize = await outputFile.length();
    task.filePath = outputFile.path;
    task.totalBytes = fileSize;
    task.receivedBytes = fileSize;
    task.addLog(
      'lib/source_parser/download_queue_controller.dart#_validateDownloadedFile: '
      'file=${pathLogLabel(outputFile.path)} size=$fileSize',
    );
    if (fileSize <= 0) {
      final emptyFileMessage = switch (task.resource.platform) {
        SourcePlatform.youtube =>
          '下载结果为空文件，已判定为失败；请重试，或检查 yt-dlp / YouTube 下载设置',
        SourcePlatform.x => '下载结果为空文件，已判定为失败；请确认该推文包含视频且当前可公开访问后重试',
        _ => '下载结果为空文件，已判定为失败；请重试',
      };
      throw DownloadException(emptyFileMessage);
    }
  }

  void _startDownloadElapsedTicker() {
    if (_downloadElapsedTicker != null) {
      return;
    }
    _downloadElapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_tasks.any((t) => t.status == DownloadStatus.downloading)) {
        _stopDownloadElapsedTicker();
        return;
      }
      notifyListeners();
    });
  }

  void _stopDownloadElapsedTicker() {
    _downloadElapsedTicker?.cancel();
    _downloadElapsedTicker = null;
  }

  Future<File> _downloadHttp(DownloadTask task, Directory directory) async {
    if (Platform.isIOS && task.resource.requiresFfmpegPostProcess) {
      throw const DownloadException('iOS 暂不支持 HLS / DASH 清单下载，请选择 MP4 直链资源');
    }
    if (!_useIoHttpClientForDirectDownloads) {
      return _downloadHttpWithPackageClient(task, directory);
    }

    File? outputFile;
    final uri = Uri.parse(task.resource.url);
    final ioClient = HttpClient();
    _activeDownloadHttpClient = ioClient;
    try {
      task.statusDetail = '直连：连接服务器…';
      notifyListeners();

      outputFile = await _uniqueFile(directory, task.fileName);

      final req = await _pollUntilCancelOr<HttpClientRequest>(
        ioClient.getUrl(uri),
        task,
        onAbortRequestedConnection: () => ioClient.close(force: true),
      );

      req.headers.set(HttpHeaders.userAgentHeader, 'VideoDownloader/1.0');

      final ioResponse = await _pollUntilCancelOr<HttpClientResponse>(
        req.close(),
        task,
        onAbortRequestedConnection: req.abort,
      );

      if (ioResponse.statusCode < 200 || ioResponse.statusCode >= 400) {
        throw DownloadException('HTTP ${ioResponse.statusCode}');
      }
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#_downloadHttp: http=${ioResponse.statusCode} contentLength=${ioResponse.contentLength}',
      );

      final contentLength = ioResponse.contentLength;
      task.totalBytes = contentLength >= 0 ? contentLength : null;
      task.statusDetail = task.totalBytes != null && task.totalBytes! > 0
          ? '直连下载中（已知文件大小）…'
          : '直连下载中（未提供总大小，进度为估算）…';
      task.filePath = outputFile.path;

      final sink = outputFile.openWrite();
      try {
        await for (final chunk in ioResponse) {
          if (_cancelRequestedTaskIds.contains(task.id)) {
            try {
              ioClient.close(force: true);
            } on Object {
              // ignore
            }
            throw const DownloadCanceledException();
          }

          task.receivedBytes += chunk.length;
          if (task.statusDetail != null && task.receivedBytes > 0) {
            task.statusDetail = null;
          }
          final totalBytes = task.totalBytes;
          if (totalBytes != null && totalBytes > 0) {
            task.progress = task.receivedBytes / totalBytes;
          }

          sink.add(chunk);
          notifyListeners();
        }
      } finally {
        await sink.close();
      }

      return outputFile;
    } on DownloadCanceledException {
      await outputFile?.deleteIfExists();
      rethrow;
    } on Object catch (error, stackTrace) {
      await outputFile?.deleteIfExists();
      if (_cancelRequestedTaskIds.contains(task.id)) {
        throw const DownloadCanceledException();
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (identical(_activeDownloadHttpClient, ioClient)) {
        _activeDownloadHttpClient = null;
      }
      try {
        ioClient.close(force: false);
      } on Object {
        // ignore
      }
    }
  }

  /// 在 [package:http] 直连路径下轮询取消（无法中断底层 TCP，适合测试桩）。
  Future<File> _downloadHttpWithPackageClient(
    DownloadTask task,
    Directory directory,
  ) async {
    File? outputFile;
    try {
      task.statusDetail = '直连：连接服务器…';
      notifyListeners();

      outputFile = await _uniqueFile(directory, task.fileName);

      final request = http.Request('GET', Uri.parse(task.resource.url));
      final response = await _pollUntilCancelOr<http.StreamedResponse>(
        _client.send(request).timeout(const Duration(seconds: 90)),
        task,
        onAbortRequestedConnection: () {},
      );

      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw DownloadException('HTTP ${response.statusCode}');
      }
      task.addLog(
        'lib/source_parser/download_queue_controller.dart#_downloadHttpWithPackageClient: http=${response.statusCode} contentLength=${response.contentLength ?? -1}',
      );

      task.statusDetail =
          response.contentLength != null && response.contentLength! > 0
          ? '直连下载中（已知文件大小）…'
          : '直连下载中（未提供总大小，进度为估算）…';
      task.totalBytes = response.contentLength;
      task.filePath = outputFile.path;

      final sink = outputFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          if (_cancelRequestedTaskIds.contains(task.id)) {
            throw const DownloadCanceledException();
          }

          task.receivedBytes += chunk.length;
          if (task.statusDetail != null && task.receivedBytes > 0) {
            task.statusDetail = null;
          }
          final totalBytes = task.totalBytes;
          if (totalBytes != null && totalBytes > 0) {
            task.progress = task.receivedBytes / totalBytes;
          }

          sink.add(chunk);
          notifyListeners();
        }
      } finally {
        await sink.close();
      }

      return outputFile;
    } on DownloadCanceledException {
      await outputFile?.deleteIfExists();
      rethrow;
    } on Object catch (error, stackTrace) {
      await outputFile?.deleteIfExists();
      if (_cancelRequestedTaskIds.contains(task.id)) {
        throw const DownloadCanceledException();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// 约每 100ms 检查一次用户取消；若已请求取消则调用 [onAbortRequestedConnection] 并抛出 [DownloadCanceledException]。
  Future<T> _pollUntilCancelOr<T>(
    Future<T> operation,
    DownloadTask task, {
    required void Function() onAbortRequestedConnection,
  }) async {
    final outcome = operation.then((v) => _PollOutcome<T>(v));
    while (true) {
      final winner = await Future.any<Object?>([
        outcome,
        Future<Object?>.delayed(const Duration(milliseconds: 100)),
      ]);
      if (winner is _PollOutcome<T>) {
        return winner.value;
      }
      if (_cancelRequestedTaskIds.contains(task.id)) {
        try {
          onAbortRequestedConnection();
        } on Object {
          // ignore
        }
        throw const DownloadCanceledException();
      }
    }
  }

  Future<File> _downloadYouTube(DownloadTask task, Directory directory) async {
    if (Platform.isIOS) {
      return IosYouTubeDownloadEngine(client: _client).download(
        task: task,
        directory: directory,
        settings: _settings,
        processRunner: _processRunner,
        processStarter: _processStarter,
        isCancelRequested: () => _cancelRequestedTaskIds.contains(task.id),
        onProgressUpdated: notifyListeners,
      );
    }
    final engine = YouTubeDownloadEngine(httpClient: _client);
    return engine.download(
      task: task,
      directory: directory,
      settings: _settings,
      processRunner: _processRunner,
      processStarter: _processStarter,
      isCancelRequested: () => _cancelRequestedTaskIds.contains(task.id),
      onProgressUpdated: notifyListeners,
    );
  }

  Future<File> _downloadX(DownloadTask task, Directory directory) async {
    const engine = XDownloadEngine();
    return engine.download(
      task: task,
      directory: directory,
      settings: _settings,
      processRunner: _processRunner,
      processStarter: _processStarter,
      isCancelRequested: () => _cancelRequestedTaskIds.contains(task.id),
      onProgressUpdated: notifyListeners,
    );
  }

  static String _friendlyDownloadError(Object error) {
    if (error is DownloadException) {
      return error.message;
    }
    return 'lib/source_parser/download_queue_controller.dart#_download: $error';
  }

  Future<void> _recordCompletedDownload(DownloadTask task) async {
    final filePath = task.filePath;
    if (filePath == null) {
      return;
    }

    final records = await _downloadHistoryStore.add(
      DownloadHistoryRecord(
        fileName: task.fileName,
        filePath: filePath,
        sourceUrl: task.resource.url,
        completedAt: DateTime.now(),
      ),
    );
    _history
      ..clear()
      ..addAll(records);
  }

  static Future<Directory> _defaultDownloadDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return Directory('${documentsDirectory.path}/VideoDownloader');
  }

  static Future<void> _defaultFolderOpener(String path) async {
    if (Platform.isIOS) {
      await const IosMediaBridge().exportFile(path);
      return;
    }
    final entityType = FileSystemEntity.typeSync(path);
    if (entityType == FileSystemEntityType.notFound) {
      throw DownloadException(
        'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: 路径不存在：${pathLogLabel(path)}',
      );
    }

    final absolutePath = _absolutePathForOpen(path, entityType);
    final pathLabel = pathLogLabel(absolutePath);
    debugPrint(
      'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: '
      'platform=${Platform.operatingSystem} entityType=$entityType path=$pathLabel',
    );

    if (Platform.isMacOS) {
      final revealed = await tryRevealPathWithNsWorkspace(absolutePath);
      debugPrint(
        'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: '
        'nsWorkspaceResult=$revealed path=$pathLabel',
      );
      if (revealed) {
        return;
      }

      debugPrint(
        'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: '
        'NSWorkspace 打开失败，回退 /usr/bin/open path=$pathLabel',
      );
      final result = await Process.run(
        '/usr/bin/open',
        entityType == FileSystemEntityType.file
            ? ['-R', absolutePath]
            : [absolutePath],
      );
      debugPrint(
        'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: '
        'fallback open exit=${result.exitCode} stdout=${result.stdout} stderr=${result.stderr}',
      );
      if (result.exitCode != 0) {
        throw DownloadException(
          'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: macOS open 失败: ${result.stderr}',
        );
      }
      return;
    }

    if (Platform.isWindows) {
      final winPath = absolutePath.replaceAll('/', r'\');
      final result = await Process.run(
        r'C:\Windows\explorer.exe',
        entityType == FileSystemEntityType.file
            ? ['/select,', winPath]
            : [winPath],
      );
      debugPrint(
        'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: '
        'windows explorer exit=${result.exitCode} stdout=${result.stdout} stderr=${result.stderr}',
      );
      if (!_windowsExplorerExitLooksSuccessful(result.exitCode)) {
        throw DownloadException(
          'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: Windows explorer 失败: ${result.stderr}',
        );
      }
      return;
    }

    final result = await Process.run('xdg-open', [
      entityType == FileSystemEntityType.file
          ? File(absolutePath).parent.path
          : absolutePath,
    ]);
    debugPrint(
      'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: '
      'xdg-open exit=${result.exitCode} stdout=${result.stdout} stderr=${result.stderr}',
    );
    if (result.exitCode != 0) {
      throw DownloadException(
        'lib/source_parser/download_queue_controller.dart#_defaultFolderOpener: Linux xdg-open 失败: ${result.stderr}',
      );
    }
  }

  /// `explorer.exe` 在「成功启动 Finder 窗口」时仍常返回 `1`，不能仅凭非 0 判定失败。
  static bool _windowsExplorerExitLooksSuccessful(int exitCode) {
    return exitCode == 0 || exitCode == 1;
  }

  static String _absolutePathForOpen(String path, FileSystemEntityType type) {
    try {
      if (type == FileSystemEntityType.file) {
        return File(path).resolveSymbolicLinksSync();
      }
      return Directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return type == FileSystemEntityType.file
          ? File(path).absolute.path
          : Directory(path).absolute.path;
    }
  }

  static String _containingDirectoryPathFor(String filePath) {
    return File(
      _absolutePathForOpen(filePath, FileSystemEntityType.file),
    ).parent.path;
  }

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) async {
    ProcessException? lastNotFoundError;
    for (final candidate in _processExecutableCandidates(executable)) {
      try {
        return await Process.run(candidate, arguments);
      } on ProcessException catch (error) {
        if (!_isExecutableNotFound(error)) {
          rethrow;
        }
        lastNotFoundError = error;
      }
    }

    throw lastNotFoundError ??
        ProcessException(executable, arguments, 'No such file or directory');
  }

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments,
  ) async {
    ProcessException? lastNotFoundError;
    for (final candidate in _processExecutableCandidates(executable)) {
      try {
        return await Process.start(candidate, arguments);
      } on ProcessException catch (error) {
        if (!_isExecutableNotFound(error)) {
          rethrow;
        }
        lastNotFoundError = error;
      }
    }

    throw lastNotFoundError ??
        ProcessException(executable, arguments, 'No such file or directory');
  }

  static bool _isExecutableNotFound(ProcessException error) {
    final message = error.message.toLowerCase();
    return message.contains('no such file or directory') ||
        message.contains('cannot find the file') ||
        message.contains('not found');
  }

  static List<String> _processExecutableCandidates(String executable) {
    if (executable.contains('/') || executable.contains(r'\')) {
      return [executable];
    }

    final home = Platform.environment['HOME'];
    final names = Platform.isWindows
        ? {executable, '$executable.exe'}
        : {executable};
    final directories = <String>[
      if (Platform.isMacOS) ...['/opt/homebrew/bin', '/usr/local/bin'],
      if (!Platform.isWindows) '/usr/bin',
      if (home != null && home.trim().isNotEmpty) '$home/.local/bin',
    ];

    return <String>[
      executable,
      for (final directory in directories)
        for (final name in names) '$directory/$name',
    ];
  }

  static Future<File> _uniqueFile(Directory directory, String fileName) async {
    final parts = _splitFileName(fileName);
    var index = 1;
    var file = File('${directory.path}/$fileName');

    while (await file.exists()) {
      index += 1;
      file = File('${directory.path}/${parts.name}-$index${parts.extension}');
    }

    return file;
  }

  static _FileNameParts _splitFileName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
      return _FileNameParts(fileName, '');
    }

    return _FileNameParts(
      fileName.substring(0, dotIndex),
      fileName.substring(dotIndex),
    );
  }

  static String _fileNameFor(SourceResource resource) {
    final uri = Uri.tryParse(resource.url);
    final rawName = uri?.pathSegments
        .where((part) => part.isNotEmpty)
        .lastOrNull;
    final baseName = rawName == null || rawName.trim().isEmpty
        ? resource.title
        : rawName;
    final sanitizedName = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');

    if (sanitizedName.contains('.')) {
      return sanitizedName;
    }

    return '$sanitizedName.${_fallbackExtension(resource.type)}';
  }

  static String _fallbackExtension(SourceResourceType type) {
    return switch (type) {
      SourceResourceType.video => 'mp4',
      SourceResourceType.image => 'jpg',
      SourceResourceType.other => 'bin',
    };
  }
}

class _FileNameParts {
  const _FileNameParts(this.name, this.extension);

  final String name;
  final String extension;
}

class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

class DownloadCanceledException implements Exception {
  const DownloadCanceledException();
}

extension on File {
  Future<void> deleteIfExists() async {
    if (await exists()) {
      await delete();
    }
  }
}
